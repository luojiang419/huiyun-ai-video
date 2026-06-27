import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings.dart';
import '../models/update_info.dart';

class UpdateException implements Exception {
  final String message;
  final Object? cause;

  const UpdateException(this.message, [this.cause]);

  @override
  String toString() => message;
}

class UpdateService {
  static const releaseRepo = 'luojiang419/huiyun-ai-video-releases';
  static const latestUpdateJsonUrl =
      'https://github.com/$releaseRepo/releases/latest/download/update.json';
  static const skippedVersionKey = 'skipped_update_version';

  final Dio? _providedDio;
  final String updateJsonUrl;
  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<UpdateDownloadProxySettings> Function()
  _downloadProxySettingsProvider;
  final String? _appDirectory;

  UpdateService({
    Dio? dio,
    this.updateJsonUrl = latestUpdateJsonUrl,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<UpdateDownloadProxySettings> Function()?
    downloadProxySettingsProvider,
    String? appDirectory,
  }) : _providedDio = dio,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _downloadProxySettingsProvider =
           downloadProxySettingsProvider ?? loadPersistedDownloadProxySettings,
       _appDirectory = appDirectory;

  Future<UpdateInfo?> checkForUpdate({
    required String currentVersion,
    bool includeSkipped = false,
  }) async {
    try {
      final dio = await _createDio();
      final response = await dio.get<dynamic>(
        updateJsonUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final info = UpdateInfo.fromJson(_decodeUpdateJson(response.data));
      if (!isNewerAppVersion(info.version, currentVersion)) {
        return null;
      }
      if (!includeSkipped &&
          !info.mandatory &&
          await isVersionSkipped(info.version)) {
        return null;
      }
      return info;
    } on FormatException catch (error) {
      throw UpdateException('更新清单格式错误: ${error.message}', error);
    } on DioException catch (error) {
      throw UpdateException('检查更新失败: ${error.message}', error);
    } catch (error) {
      throw UpdateException('检查更新失败: $error', error);
    }
  }

  Future<void> skipVersion(String version) async {
    final preferences = await _preferencesProvider();
    await preferences.setString(skippedVersionKey, version);
  }

  Future<bool> isVersionSkipped(String version) async {
    final preferences = await _preferencesProvider();
    return preferences.getString(skippedVersionKey) == version;
  }

  Future<String> downloadInstaller(
    UpdateInfo info, {
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final downloadsDir = Directory(
      path.join(appDirectory, 'data', '.system_update', 'downloads'),
    );
    await downloadsDir.create(recursive: true);

    final targetPath = path.join(downloadsDir.path, info.installerName);
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      if (await verifySha256(targetPath, info.sha256)) {
        return targetPath;
      }
      await targetFile.delete();
    }

    final tempPath = '$targetPath.download';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      final dio = await _createDio();
      await dio.download(
        info.installerUrl,
        tempPath,
        onReceiveProgress: onReceiveProgress,
      );
      if (!await verifySha256(tempPath, info.sha256)) {
        await tempFile.delete();
        throw const UpdateException('安装包校验失败，文件可能已损坏');
      }
      await tempFile.rename(targetPath);
      return targetPath;
    } on DioException catch (error) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw UpdateException('下载安装包失败: ${error.message}', error);
    }
  }

  Future<bool> verifySha256(String filePath, String expectedHash) async {
    final actualHash = await calculateSha256(filePath);
    return actualHash.toUpperCase() == expectedHash.toUpperCase();
  }

  Future<void> launchInstallerAndExit(String installerPath) async {
    final file = File(installerPath);
    if (!await file.exists()) {
      throw UpdateException('安装包不存在: $installerPath');
    }

    await Process.start(
      installerPath,
      const [],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  String get appDirectory {
    if (_appDirectory != null) {
      return _appDirectory;
    }
    return File(Platform.resolvedExecutable).parent.path;
  }

  static Future<String> calculateSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString().toUpperCase();
  }

  Map<String, dynamic> _decodeUpdateJson(dynamic data) {
    final decoded = data is String ? jsonDecode(data) : data;
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('update.json 根节点必须是对象');
  }

  Future<Dio> _createDio() async {
    final dio =
        _providedDio ??
        Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));
    final proxySettings = await _downloadProxySettingsProvider();
    _configureProxy(dio, proxySettings);
    return dio;
  }

  void _configureProxy(Dio dio, UpdateDownloadProxySettings settings) {
    final adapter = dio.httpClientAdapter;
    if (adapter is! IOHttpClientAdapter) {
      return;
    }

    adapter.createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) {
        if (isLocalUri(uri)) {
          return 'DIRECT';
        }
        if (settings.mode == Settings.updateDownloadProxyCustom) {
          return buildCustomProxyRule(settings.customAddress);
        }
        return findSystemProxyRule(uri);
      };
      return client;
    };
  }

  static bool isLocalUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.local');
  }

  static String buildCustomProxyRule(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      return 'DIRECT';
    }
    if (trimmed.toUpperCase().startsWith('PROXY ') ||
        trimmed.toUpperCase().startsWith('SOCKS ')) {
      return trimmed;
    }

    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || uri.port <= 0) {
      return 'DIRECT';
    }

    final hostPort = '${uri.host}:${uri.port}';
    return uri.scheme.toLowerCase().startsWith('socks')
        ? 'SOCKS $hostPort'
        : 'PROXY $hostPort';
  }

  static String findSystemProxyRule(Uri uri) {
    final envProxy = HttpClient.findProxyFromEnvironment(
      uri,
      environment: Platform.environment,
    );
    if (envProxy.trim().isNotEmpty && envProxy != 'DIRECT') {
      return envProxy;
    }
    return _readWindowsSystemProxyRule(uri) ?? 'DIRECT';
  }

  static String? _readWindowsSystemProxyRule(Uri uri) {
    if (!Platform.isWindows) {
      return null;
    }

    final result = Process.runSync('reg', const [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    ]);
    if (result.exitCode != 0) {
      return null;
    }

    final output = '${result.stdout}\n${result.stderr}';
    final proxyEnableMatch = RegExp(
      r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
    ).firstMatch(output);
    if (proxyEnableMatch == null ||
        int.tryParse(proxyEnableMatch.group(1)!, radix: 16) != 1) {
      return null;
    }

    final proxyServerMatch = RegExp(
      r'ProxyServer\s+REG_SZ\s+(.+)',
    ).firstMatch(output);
    final proxyServer = proxyServerMatch?.group(1)?.trim();
    if (proxyServer == null || proxyServer.isEmpty) {
      return null;
    }
    return _proxyRuleFromWindowsProxyServer(proxyServer, uri);
  }

  static String? _proxyRuleFromWindowsProxyServer(String proxyServer, Uri uri) {
    if (!proxyServer.contains('=')) {
      return buildCustomProxyRule(proxyServer);
    }

    final entries = <String, String>{};
    for (final part in proxyServer.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      entries[part.substring(0, index).trim().toLowerCase()] = part
          .substring(index + 1)
          .trim();
    }

    final scheme = uri.scheme.toLowerCase();
    final proxy =
        entries[scheme] ??
        entries['http'] ??
        entries['https'] ??
        entries['socks'];
    if (proxy == null || proxy.isEmpty) {
      return null;
    }
    return entries['socks'] == proxy
        ? buildCustomProxyRule('socks://$proxy')
        : buildCustomProxyRule(proxy);
  }

  static Future<UpdateDownloadProxySettings>
  loadPersistedDownloadProxySettings() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('settings');
    if (raw == null || raw.trim().isEmpty) {
      return UpdateDownloadProxySettings.fromSettings(
        Settings.defaultSettings(),
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return UpdateDownloadProxySettings.fromSettings(
          Settings.fromJson(decoded),
        );
      }
      if (decoded is Map) {
        return UpdateDownloadProxySettings.fromSettings(
          Settings.fromJson(Map<String, dynamic>.from(decoded)),
        );
      }
    } catch (_) {
      // ignore and fall back to defaults
    }
    return UpdateDownloadProxySettings.fromSettings(Settings.defaultSettings());
  }
}

class UpdateDownloadProxySettings {
  final String mode;
  final String customAddress;

  const UpdateDownloadProxySettings({
    required this.mode,
    required this.customAddress,
  });

  factory UpdateDownloadProxySettings.fromSettings(Settings settings) {
    return UpdateDownloadProxySettings(
      mode: settings.updateDownloadProxyMode,
      customAddress: settings.updateDownloadProxyAddress,
    );
  }
}

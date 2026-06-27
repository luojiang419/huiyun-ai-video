import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_update_job.dart';
import '../models/settings.dart';
import '../models/update_info.dart';

typedef UpdateProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
      bool runInShell,
    });

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
  final UpdateProcessStarter _processStarter;
  final void Function(int exitCode) _exitHandler;
  final int Function() _pidProvider;
  final String Function() _resolvedExecutableProvider;
  final bool Function() _isWindowsProvider;

  UpdateService({
    Dio? dio,
    this.updateJsonUrl = latestUpdateJsonUrl,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<UpdateDownloadProxySettings> Function()?
    downloadProxySettingsProvider,
    String? appDirectory,
    UpdateProcessStarter? processStarter,
    void Function(int exitCode)? exitHandler,
    int Function()? pidProvider,
    String Function()? resolvedExecutableProvider,
    bool Function()? isWindowsProvider,
  }) : _providedDio = dio,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _downloadProxySettingsProvider =
           downloadProxySettingsProvider ?? loadPersistedDownloadProxySettings,
       _appDirectory = appDirectory,
       _processStarter =
           processStarter ??
           ((
             executable,
             arguments, {
             mode = ProcessStartMode.normal,
             runInShell = false,
           }) {
             return Process.start(
               executable,
               arguments,
               mode: mode,
               runInShell: runInShell,
             );
           }),
       _exitHandler = exitHandler ?? exit,
       _pidProvider = pidProvider ?? (() => pid),
       _resolvedExecutableProvider =
           resolvedExecutableProvider ?? (() => Platform.resolvedExecutable),
       _isWindowsProvider = isWindowsProvider ?? (() => Platform.isWindows);

  String get currentExecutablePath => _resolvedExecutableProvider();

  String get appDirectory {
    if (_appDirectory != null) {
      return _appDirectory;
    }
    return File(currentExecutablePath).parent.path;
  }

  String get updatesRootDirectoryPath =>
      path.join(appDirectory, 'data', '.system_update');

  String get downloadsDirectoryPath =>
      path.join(updatesRootDirectoryPath, 'downloads');

  String get runnerDirectoryPath =>
      path.join(updatesRootDirectoryPath, 'runner');

  String get pendingUpdateFilePath =>
      path.join(updatesRootDirectoryPath, 'pending_update.json');

  String get updateRunnerScriptPath =>
      path.join(runnerDirectoryPath, 'update_runner.ps1');

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
    final downloadsDir = Directory(downloadsDirectoryPath);
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

  Future<PendingUpdateJob?> loadPendingUpdate() async {
    final file = File(pendingUpdateFilePath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return PendingUpdateJob.fromJson(decoded);
      }
      if (decoded is Map) {
        return PendingUpdateJob.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      await clearPendingUpdate();
    }
    return null;
  }

  Future<void> savePendingUpdate(PendingUpdateJob job) async {
    await Directory(updatesRootDirectoryPath).create(recursive: true);
    await File(
      pendingUpdateFilePath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(job.toJson()));
  }

  Future<void> clearPendingUpdate() async {
    final file = File(pendingUpdateFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<PendingUpdateJob?> reconcilePendingUpdate({
    required String currentVersion,
  }) async {
    final pending = await loadPendingUpdate();
    if (pending == null) {
      return null;
    }

    final installerFile = File(pending.installerPath);
    if (!await installerFile.exists()) {
      await clearPendingUpdate();
      return null;
    }

    if (!await verifySha256(pending.installerPath, pending.sha256)) {
      await clearPendingUpdate();
      return null;
    }

    if (!isNewerAppVersion(pending.targetVersion, currentVersion)) {
      await clearPendingUpdate();
      return null;
    }

    if (pending.status == PendingUpdateStatus.installing) {
      final failed = pending.copyWith(
        status: PendingUpdateStatus.failed,
        installOnNextLaunch: false,
        promptOnNextLaunch: true,
        lastFailureReason: pending.lastFailureReason.isEmpty
            ? '上次自动安装未完成，请重新尝试更新。'
            : pending.lastFailureReason,
      );
      await savePendingUpdate(failed);
      return failed;
    }

    return pending;
  }

  Future<PendingUpdateJob?> downloadLatestUpdateIfNeeded({
    required String currentVersion,
    bool includeSkipped = false,
    bool promptOnNextLaunch = false,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final info = await checkForUpdate(
      currentVersion: currentVersion,
      includeSkipped: includeSkipped,
    );
    if (info == null) {
      return null;
    }

    final pending = await loadPendingUpdate();
    if (pending != null &&
        pending.targetVersion == info.version &&
        await File(pending.installerPath).exists() &&
        await verifySha256(pending.installerPath, pending.sha256)) {
      final updated = pending.copyWith(
        info: info,
        promptOnNextLaunch: promptOnNextLaunch || pending.promptOnNextLaunch,
      );
      await savePendingUpdate(updated);
      return updated;
    }

    final installerPath = await downloadInstaller(
      info,
      onReceiveProgress: onReceiveProgress,
    );
    final job = PendingUpdateJob(
      info: info,
      installerPath: installerPath,
      sha256: info.sha256,
      downloadedAt: DateTime.now().toIso8601String(),
      status: PendingUpdateStatus.downloaded,
      promptOnNextLaunch: promptOnNextLaunch,
    );
    await savePendingUpdate(job);
    return job;
  }

  Future<PendingUpdateJob> scheduleInstallOnNextLaunch() async {
    final pending = await loadPendingUpdate();
    if (pending == null) {
      throw const UpdateException('未找到已下载的更新包');
    }
    final scheduled = pending.copyWith(
      status: PendingUpdateStatus.scheduled,
      installOnNextLaunch: true,
      promptOnNextLaunch: true,
      lastFailureReason: '',
    );
    await savePendingUpdate(scheduled);
    return scheduled;
  }

  Future<bool> tryApplyScheduledUpdateOnStartup({
    required String currentVersion,
  }) async {
    if (!_isWindowsProvider()) {
      return false;
    }

    final pending = await reconcilePendingUpdate(
      currentVersion: currentVersion,
    );
    if (pending == null || !pending.installOnNextLaunch) {
      return false;
    }

    await launchSilentUpdateAndExit(job: pending);
    return true;
  }

  Future<void> launchInstallerAndExit(String installerPath) async {
    final file = File(installerPath);
    if (!await file.exists()) {
      throw UpdateException('安装包不存在: $installerPath');
    }

    final fallbackInfo = UpdateInfo(
      version: _guessVersionFromInstallerPath(installerPath),
      installerName: path.basename(installerPath),
      installerUrl: 'local://pending',
      sha256: await calculateSha256(installerPath),
      size: await file.length(),
      publishedAt: DateTime.now().toIso8601String(),
      releaseNotes: '',
      mandatory: false,
    );
    final pending = PendingUpdateJob(
      info: fallbackInfo,
      installerPath: installerPath,
      sha256: fallbackInfo.sha256,
      downloadedAt: DateTime.now().toIso8601String(),
    );
    await savePendingUpdate(pending);
    await launchSilentUpdateAndExit(job: pending);
  }

  Future<void> launchSilentUpdateAndExit({PendingUpdateJob? job}) async {
    if (!_isWindowsProvider()) {
      throw const UpdateException('当前仅支持 Windows 自更新');
    }

    final pending = job ?? await loadPendingUpdate();
    if (pending == null) {
      throw const UpdateException('未找到待安装的更新包');
    }

    final installerFile = File(pending.installerPath);
    if (!await installerFile.exists()) {
      throw UpdateException('安装包不存在: ${pending.installerPath}');
    }

    await _ensureUpdateDirectories();
    final normalizedPending = pending.copyWith(
      status: PendingUpdateStatus.installing,
      installOnNextLaunch: false,
      promptOnNextLaunch: false,
      lastFailureReason: '',
    );
    await savePendingUpdate(normalizedPending);

    final logPath = path.join(
      runnerDirectoryPath,
      'update_runner_${DateTime.now().millisecondsSinceEpoch}.log',
    );
    await _writeRunnerScript();

    final args = [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      updateRunnerScriptPath,
      '-InstallerPath',
      normalizedPending.installerPath,
      '-InstallDir',
      appDirectory,
      '-ExecutablePath',
      path.join(appDirectory, path.basename(currentExecutablePath)),
      '-ParentPid',
      _pidProvider().toString(),
      '-PendingFilePath',
      pendingUpdateFilePath,
      '-LogPath',
      logPath,
    ];

    try {
      await _processStarter(
        'powershell',
        args,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _exitHandler(0);
    } catch (error) {
      final failed = normalizedPending.copyWith(
        status: PendingUpdateStatus.failed,
        promptOnNextLaunch: true,
        lastFailureReason: '启动静默更新失败: $error',
      );
      await savePendingUpdate(failed);
      throw UpdateException('启动静默更新失败: $error', error);
    }
  }

  Future<bool> verifySha256(String filePath, String expectedHash) async {
    final actualHash = await calculateSha256(filePath);
    return actualHash.toUpperCase() == expectedHash.toUpperCase();
  }

  static Future<String> calculateSha256(String filePath) async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString().toUpperCase();
  }

  Map<String, dynamic> _decodeUpdateJson(dynamic data) {
    final decoded = data is String
        ? jsonDecode(data.replaceFirst('\uFEFF', ''))
        : data;
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('update.json 根节点必须是对象');
  }

  Future<void> _ensureUpdateDirectories() async {
    await Directory(downloadsDirectoryPath).create(recursive: true);
    await Directory(runnerDirectoryPath).create(recursive: true);
  }

  Future<void> _writeRunnerScript() async {
    final script = r'''
param(
  [Parameter(Mandatory = $true)][string]$InstallerPath,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$ExecutablePath,
  [Parameter(Mandatory = $true)][int]$ParentPid,
  [Parameter(Mandatory = $true)][string]$PendingFilePath,
  [Parameter(Mandatory = $true)][string]$LogPath
)

$ErrorActionPreference = "Stop"

function Write-Log {
  param([string]$Message)
  $dir = Split-Path -Parent $LogPath
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "[$timestamp] $Message"
}

function Update-PendingStatus {
  param(
    [string]$Status,
    [string]$Reason
  )

  if (-not (Test-Path -LiteralPath $PendingFilePath)) {
    return
  }

  try {
    $pending = Get-Content -LiteralPath $PendingFilePath -Raw | ConvertFrom-Json
    $pending.status = $Status
    $pending.installOnNextLaunch = $false
    $pending.promptOnNextLaunch = $true
    $pending.lastFailureReason = $Reason
    $pending | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $PendingFilePath -Encoding UTF8
  } catch {
    Write-Log "更新 pending_update.json 失败：$($_.Exception.Message)"
  }
}

try {
  Write-Log "静默更新助手启动"
  if ($ParentPid -gt 0) {
    Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path -LiteralPath $InstallerPath)) {
    throw "安装包不存在：$InstallerPath"
  }

  $arguments = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NOCANCEL",
    "/CLOSEAPPLICATIONS",
    "/FORCECLOSEAPPLICATIONS",
    "/DIR=$InstallDir"
  )

  Write-Log "开始运行安装器：$InstallerPath"
  $installer = Start-Process -FilePath $InstallerPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
  if ($installer.ExitCode -ne 0) {
    throw "安装器退出码：$($installer.ExitCode)"
  }

  Start-Sleep -Seconds 2
  if (-not (Test-Path -LiteralPath $ExecutablePath)) {
    throw "安装完成后未找到主程序：$ExecutablePath"
  }

  Write-Log "安装完成，准备重启主程序"
  Start-Process -FilePath $ExecutablePath -WorkingDirectory (Split-Path -Parent $ExecutablePath) -WindowStyle Hidden | Out-Null
  Write-Log "主程序已重新启动"
} catch {
  $message = $_.Exception.Message
  Write-Log "静默更新失败：$message"
  Update-PendingStatus -Status "failed" -Reason $message
  exit 1
}
''';

    await File(updateRunnerScriptPath).writeAsString(script, flush: true);
  }

  String _guessVersionFromInstallerPath(String installerPath) {
    final name = path.basename(installerPath);
    final match = RegExp(
      r'(V\d+(?:\.\d+){0,2})',
      caseSensitive: false,
    ).firstMatch(name);
    return match?.group(1) ?? 'V0.0.0';
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

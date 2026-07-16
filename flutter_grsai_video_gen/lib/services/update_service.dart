import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/update_config.dart';
import '../models/pending_update_job.dart';
import '../models/settings.dart';
import '../models/update_install_session.dart';
import '../models/update_info.dart';

typedef UpdateProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      ProcessStartMode mode,
      bool runInShell,
    });

typedef UpdateInstallProgressCallback =
    void Function(UpdateInstallSession session, String message);

class UpdateException implements Exception {
  final String message;
  final Object? cause;

  const UpdateException(this.message, [this.cause]);

  @override
  String toString() => message;
}

class UpdateService {
  static const releaseRepo = UpdateConfig.releaseRepo;
  static const latestUpdateJsonUrl = UpdateConfig.latestManifestUrl;
  static const skippedVersionKey = 'skipped_update_version';

  final Dio? _providedDio;
  final String updateJsonUrl;
  final Future<SharedPreferences> Function() _preferencesProvider;
  final Future<UpdateDownloadProxySettings> Function()
  _downloadProxySettingsProvider;
  final Future<List<String>> Function() _installedAppDirsLoader;
  final String? _appDirectory;
  final UpdateProcessStarter _processStarter;
  final void Function(int exitCode) _exitHandler;
  final String Function() _resolvedExecutableProvider;
  final bool Function() _isWindowsProvider;

  UpdateService({
    Dio? dio,
    this.updateJsonUrl = latestUpdateJsonUrl,
    Future<SharedPreferences> Function()? preferencesProvider,
    Future<UpdateDownloadProxySettings> Function()?
    downloadProxySettingsProvider,
    Future<List<String>> Function()? installedAppDirsLoader,
    String? appDirectory,
    UpdateProcessStarter? processStarter,
    void Function(int exitCode)? exitHandler,
    String Function()? resolvedExecutableProvider,
    bool Function()? isWindowsProvider,
  }) : _providedDio = dio,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _downloadProxySettingsProvider =
           downloadProxySettingsProvider ?? loadPersistedDownloadProxySettings,
       _installedAppDirsLoader =
           installedAppDirsLoader ?? _discoverInstalledAppDirs,
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

  String get pendingUpdateFilePath =>
      path.join(updatesRootDirectoryPath, 'pending_update.json');

  String get jobsDirectoryPath => path.join(updatesRootDirectoryPath, 'jobs');

  String get stagingDirectoryPath =>
      path.join(updatesRootDirectoryPath, 'staging');

  String get resultsDirectoryPath =>
      path.join(updatesRootDirectoryPath, 'results');

  String get acksDirectoryPath => path.join(updatesRootDirectoryPath, 'acks');

  String get logsDirectoryPath => path.join(updatesRootDirectoryPath, 'logs');

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
      if (updateJsonUrl == latestUpdateJsonUrl) {
        UpdateConfig.validateProductionManifest(info);
      }
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
      if (await targetFile.length() == info.size &&
          await verifySha256(targetPath, info.sha256)) {
        return targetPath;
      }
      await targetFile.delete();
    }

    final tempPath = '$targetPath.part';
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
      if (await tempFile.length() != info.size) {
        await tempFile.delete();
        throw const UpdateException('安装包大小校验失败，文件可能不完整');
      }
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

    if (path.basename(pending.installerPath) != pending.info.installerName ||
        await installerFile.length() != pending.info.size) {
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
        await File(pending.installerPath).length() == info.size &&
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
    final settings = await loadPersistedUpdateSettings();
    if (settings.updatePolicy == Settings.updatePolicyDisabled) {
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

  Future<void> acknowledgeCompletedUpdateOnStartup({
    required String currentVersion,
  }) async {
    if (!_isWindowsProvider()) {
      return;
    }

    await _ensureUpdateDirectories();
    await _clearInstalledPendingUpdate(currentVersion);

    final sessions = await _loadInstallSessions();
    for (final session in sessions) {
      if (session.status != UpdateInstallSessionStatus.completed) {
        continue;
      }
      if (isNewerAppVersion(session.targetVersion, currentVersion)) {
        continue;
      }

      await _writeSessionAck(session, currentVersion);
      await _markSessionResultAcknowledged(session, currentVersion);
      await _writeSessionLog(session.logFilePath, '检测到新版本启动确认，开始回收本次更新会话');
      await _clearPendingUpdateFile(session.sourcePendingUpdateFilePath);
      await _clearPendingUpdateFile(session.pendingUpdateFilePath);
      await _cleanupInstallSessionArtifacts(session);
      await _clearInstalledPendingUpdate(currentVersion);
    }
  }

  Future<UpdateInstallSession?> loadInstallSession({
    required String sessionFilePath,
  }) async {
    final file = File(sessionFilePath);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return UpdateInstallSession.fromJson(decoded);
    }
    if (decoded is Map) {
      return UpdateInstallSession.fromJson(Map<String, dynamic>.from(decoded));
    }
    throw const UpdateException('更新会话文件格式错误');
  }

  Future<void> saveInstallSession(
    UpdateInstallSession session, {
    String? sessionFilePath,
  }) async {
    final filePath =
        sessionFilePath ??
        _installSessionFilePathFor(session.installDir, session.sessionId);
    await Directory(path.dirname(filePath)).create(recursive: true);
    await File(filePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(session.toJson()),
      flush: true,
    );
  }

  Future<void> runDetachedInstallSession({
    required String sessionFilePath,
    String? expectedSessionId,
    UpdateInstallProgressCallback? onProgress,
  }) async {
    if (!_isWindowsProvider()) {
      throw const UpdateException('当前仅支持 Windows 自更新');
    }

    var session = await loadInstallSession(sessionFilePath: sessionFilePath);
    if (session == null) {
      throw UpdateException('未找到更新会话文件: $sessionFilePath');
    }
    if (expectedSessionId != null &&
        expectedSessionId.isNotEmpty &&
        session.sessionId != expectedSessionId) {
      throw UpdateException('更新会话编号不匹配: ${session.sessionId}');
    }

    try {
      session = session.copyWith(
        status: UpdateInstallSessionStatus.installing,
        lastError: '',
      );
      await saveInstallSession(session, sessionFilePath: sessionFilePath);
      await _writeSessionLog(session.logFilePath, '独立更新安装器已接管更新流程');
      _emitInstallProgress(onProgress, session, '独立更新程序已接管任务');

      _emitInstallProgress(onProgress, session, '正在等待主程序退出');
      await _waitForParentProcessExit(session.parentPid);
      await _writeSessionLog(session.logFilePath, '主程序进程已退出，开始校验安装包');
      _emitInstallProgress(onProgress, session, '主程序已退出，正在校验安装包');

      final installerFile = File(session.installerPath);
      if (!await installerFile.exists()) {
        throw UpdateException('安装包不存在: ${session.installerPath}');
      }
      if (!await verifySha256(session.installerPath, session.installerSha256)) {
        throw const UpdateException('安装包校验失败，文件可能已损坏');
      }
      await _writeSessionLog(session.logFilePath, '安装包校验完成，准备执行静默安装');
      _emitInstallProgress(onProgress, session, '安装包校验完成，正在执行静默安装');

      final installerProcess = await _processStarter(
        session.installerPath,
        _buildSilentInstallerArguments(session.installDir),
      );
      final exitCode = await installerProcess.exitCode;
      if (exitCode != 0) {
        throw UpdateException('安装器退出码: $exitCode');
      }

      await Future<void>.delayed(const Duration(seconds: 2));
      final targetExecutable = File(session.targetExecutablePath);
      if (!await targetExecutable.exists()) {
        throw UpdateException('安装完成后未找到主程序: ${session.targetExecutablePath}');
      }

      session = session.copyWith(status: UpdateInstallSessionStatus.completed);
      await saveInstallSession(session, sessionFilePath: sessionFilePath);
      await _writeSessionResult(
        session,
        status: 'completed',
        message: '安装包已执行完成，等待新版本启动确认。',
      );
      await _writeSessionLog(session.logFilePath, '安装完成，准备重启新版本');
      _emitInstallProgress(onProgress, session, '安装完成，正在启动新版本');

      await _processStarter(
        session.targetExecutablePath,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      await _writeSessionLog(session.logFilePath, '已拉起新版本主程序');
      _emitInstallProgress(onProgress, session, '新版本已启动，更新程序即将退出');
    } catch (error) {
      final message = error.toString();
      final failedSession = session!.copyWith(
        status: UpdateInstallSessionStatus.failed,
        lastError: message,
      );
      await saveInstallSession(failedSession, sessionFilePath: sessionFilePath);
      await _markPendingUpdateFailed(
        failedSession.pendingUpdateFilePath,
        message,
      );
      await _markPendingUpdateFailed(
        failedSession.sourcePendingUpdateFilePath,
        message,
      );
      await _writeSessionResult(
        failedSession,
        status: 'failed',
        message: message,
      );
      await _writeSessionLog(failedSession.logFilePath, '更新失败: $message');
      _emitInstallProgress(onProgress, failedSession, '更新失败：$message');
      rethrow;
    }
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
      throw const UpdateException('当前仅支持 Windows 安装包更新');
    }

    final pending = job ?? await loadPendingUpdate();
    if (pending == null) {
      throw const UpdateException('未找到待安装的更新包');
    }

    final installerFile = File(pending.installerPath);
    if (!await installerFile.exists()) {
      throw UpdateException('安装包不存在: ${pending.installerPath}');
    }

    final targetInstallDir = await _resolvePreferredInstallDirectory(
      executableName: path.basename(currentExecutablePath),
    );
    final normalizedPending = pending.copyWith(
      status: PendingUpdateStatus.installing,
      installOnNextLaunch: false,
      promptOnNextLaunch: false,
      lastFailureReason: '',
    );
    await savePendingUpdate(normalizedPending);
    await _savePendingUpdateToFile(
      normalizedPending,
      pendingFilePath: _pendingUpdateFilePathFor(targetInstallDir),
    );

    try {
      if (!await verifySha256(
        normalizedPending.installerPath,
        normalizedPending.sha256,
      )) {
        throw const UpdateException('安装包校验失败，文件可能已损坏');
      }

      await _startInstallerPackage(
        installerPath: normalizedPending.installerPath,
        installDir: targetInstallDir,
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _exitHandler(0);
    } catch (error) {
      final reason = error is UpdateException
          ? error.message
          : '启动安装包失败: $error';
      final failed = normalizedPending.copyWith(
        status: PendingUpdateStatus.failed,
        promptOnNextLaunch: true,
        lastFailureReason: reason,
      );
      await savePendingUpdate(failed);
      await _markPendingUpdateFailed(
        _pendingUpdateFilePathFor(targetInstallDir),
        failed.lastFailureReason,
      );
      throw UpdateException(reason, error);
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
    await _ensureUpdateDirectoriesFor(appDirectory);
  }

  List<String> _buildSilentInstallerArguments(String installDir) {
    return [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NOCANCEL',
      '/CLOSEAPPLICATIONS',
      '/FORCECLOSEAPPLICATIONS',
      '/DIR=$installDir',
    ];
  }

  Future<void> _startInstallerPackage({
    required String installerPath,
    required String installDir,
  }) async {
    final logDir = _logsDirectoryPathFor(installDir);
    final scriptPath = path.join(logDir, 'launch-installer.ps1');
    final launcherLogPath = path.join(logDir, 'installer-launch.log');
    final installerLogPath = path.join(logDir, 'installer-package.log');
    await Directory(logDir).create(recursive: true);

    final scriptLines = <String>[
      r"$ErrorActionPreference = 'Stop'",
      '\$pidToWait = $pid',
      '\$installerPath = ${_toPowerShellSingleQuotedLiteral(installerPath)}',
      '\$installDir = ${_toPowerShellSingleQuotedLiteral(installDir)}',
      '\$logPath = ${_toPowerShellSingleQuotedLiteral(launcherLogPath)}',
      '\$installerUiLogPath = ${_toPowerShellSingleQuotedLiteral(installerLogPath)}',
      r'function Write-UpdateLog([string]$message) {',
      r"  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'",
      r"  Add-Content -LiteralPath $logPath -Value ($timestamp + ' ' + $message) -Encoding UTF8",
      r'}',
      r'Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue',
      r'try {',
      r"  Write-UpdateLog 'update launcher started'",
      r"  Write-UpdateLog ('waiting old process, pid=' + $pidToWait)",
      r'  while (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }',
      r'  Start-Sleep -Milliseconds 800',
      r"  if (-not (Test-Path -LiteralPath $installerPath)) { throw ('installer not found: ' + $installerPath) }",
      r"  Write-UpdateLog ('starting installer: ' + $installerPath)",
      "  \$installerDirArg = '/DIR=\"' + \$installDir + '\"'",
      "  \$installerLogArg = '/LOG=\"' + \$installerUiLogPath + '\"'",
      r'  $installerArgs = @($installerDirArg, $installerLogArg)',
      r'  $process = Start-Process -FilePath $installerPath -ArgumentList $installerArgs -Verb RunAs -Wait -PassThru',
      r"  Write-UpdateLog ('installer finished, exitCode=' + $process.ExitCode)",
      "  if (\$process.ExitCode -ne 0) { throw ('installer exit code: ' + \$process.ExitCode) }",
      r"  Write-UpdateLog 'installer completed'",
      r'} catch {',
      r"  Write-UpdateLog ('update launcher failed: ' + $_.Exception.Message)",
      r'}',
      r'Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue',
    ];
    await File(scriptPath).writeAsBytes(
      utf8.encode('\uFEFF${scriptLines.join('\r\n')}'),
      flush: true,
    );

    await _processStarter(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        scriptPath,
      ],
      // On Windows, Dart's detached mode can start powershell.exe and still
      // have it exit before running the script. A normal child keeps running
      // after this app exits and reliably executes the launcher script.
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
  }

  String _toPowerShellSingleQuotedLiteral(String value) {
    return "'${_escapePowerShellSingleQuotedString(value)}'";
  }

  String _escapePowerShellSingleQuotedString(String value) {
    return value.replaceAll("'", "''");
  }

  String _updatesRootDirectoryPathFor(String installDir) {
    return path.join(installDir, 'data', '.system_update');
  }

  String _pendingUpdateFilePathFor(String installDir) {
    return path.join(
      _updatesRootDirectoryPathFor(installDir),
      'pending_update.json',
    );
  }

  String _jobsDirectoryPathFor(String installDir) {
    return path.join(_updatesRootDirectoryPathFor(installDir), 'jobs');
  }

  String _stagingDirectoryPathFor(String installDir) {
    return path.join(_updatesRootDirectoryPathFor(installDir), 'staging');
  }

  String _resultsDirectoryPathFor(String installDir) {
    return path.join(_updatesRootDirectoryPathFor(installDir), 'results');
  }

  String _acksDirectoryPathFor(String installDir) {
    return path.join(_updatesRootDirectoryPathFor(installDir), 'acks');
  }

  String _logsDirectoryPathFor(String installDir) {
    return path.join(_updatesRootDirectoryPathFor(installDir), 'logs');
  }

  String _installSessionFilePathFor(String installDir, String sessionId) {
    return path.join(_jobsDirectoryPathFor(installDir), '$sessionId.json');
  }

  Future<void> _ensureUpdateDirectoriesFor(String installDir) async {
    await Directory(downloadsDirectoryPath).create(recursive: true);
    await Directory(_jobsDirectoryPathFor(installDir)).create(recursive: true);
    await Directory(
      _stagingDirectoryPathFor(installDir),
    ).create(recursive: true);
    await Directory(
      _resultsDirectoryPathFor(installDir),
    ).create(recursive: true);
    await Directory(_acksDirectoryPathFor(installDir)).create(recursive: true);
    await Directory(_logsDirectoryPathFor(installDir)).create(recursive: true);
  }

  Future<void> _savePendingUpdateToFile(
    PendingUpdateJob job, {
    required String pendingFilePath,
  }) async {
    await Directory(path.dirname(pendingFilePath)).create(recursive: true);
    await File(pendingFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(job.toJson()),
      flush: true,
    );
  }

  Future<String> _resolvePreferredInstallDirectory({
    required String executableName,
  }) async {
    final candidates = <String>[];
    final seen = <String>{};
    void addCandidate(String dir) {
      final trimmed = dir.trim();
      if (trimmed.isEmpty) {
        return;
      }
      final normalized = _normalizePath(trimmed);
      if (seen.add(normalized)) {
        candidates.add(trimmed);
      }
    }

    addCandidate(appDirectory);
    for (final dir in await _installedAppDirsLoader()) {
      addCandidate(dir);
    }

    var bestDir = appDirectory;
    var bestScore = -0x7fffffff;
    for (final dir in candidates) {
      final score = await _scoreInstallDirectoryCandidate(
        dir,
        executableName: executableName,
      );
      if (score > bestScore) {
        bestScore = score;
        bestDir = dir;
      }
    }
    return bestDir;
  }

  Future<int> _scoreInstallDirectoryCandidate(
    String dir, {
    required String executableName,
  }) async {
    var score = 0;
    final normalizedDir = _normalizePath(dir);
    final normalizedCurrent = _normalizePath(appDirectory);
    if (normalizedDir == normalizedCurrent) {
      score += 120;
    }

    final directory = Directory(dir);
    if (await directory.exists()) {
      score += 300;
    }

    final executable = File(path.join(dir, executableName));
    if (await executable.exists()) {
      score += 700;
    }

    if (_looksLikeStandardInstallDirectory(dir)) {
      score += 900;
    }

    if (_looksLikeWorkspaceArtifactDirectory(dir)) {
      score -= 1600;
    }

    return score;
  }

  bool _looksLikeStandardInstallDirectory(String dir) {
    final normalized = _normalizePath(dir);
    return normalized.endsWith('/videogen') &&
        (normalized.contains('/program files/') ||
            normalized.contains('/program files (x86)/') ||
            normalized.contains('/huiyunai/videogen'));
  }

  bool _looksLikeWorkspaceArtifactDirectory(String dir) {
    final normalized = _normalizePath(dir);
    return normalized.contains('/dist/') ||
        normalized.contains('/backup/') ||
        normalized.contains('/实测输出/') ||
        normalized.contains('/进度快照/') ||
        normalized.contains('/snapshots/');
  }

  String _normalizePath(String value) {
    final normalized = value.replaceAll('\\', '/').trim();
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static Future<List<String>> _discoverInstalledAppDirs() async {
    final dirs = <String>{};
    void addIfNotBlank(String? value) {
      if (value != null && value.trim().isNotEmpty) {
        dirs.add(value.trim());
      }
    }

    addIfNotBlank(
      Platform.environment['LOCALAPPDATA'] == null
          ? null
          : path.join(
              Platform.environment['LOCALAPPDATA']!,
              'HuiYunAI',
              'VideoGen',
            ),
    );
    addIfNotBlank(
      Platform.environment['ProgramFiles'] == null
          ? null
          : path.join(Platform.environment['ProgramFiles']!, 'VideoGen'),
    );
    addIfNotBlank(
      Platform.environment['ProgramFiles(x86)'] == null
          ? null
          : path.join(Platform.environment['ProgramFiles(x86)']!, 'VideoGen'),
    );
    if (Platform.isWindows && await Directory('D:\\').exists()) {
      addIfNotBlank(r'D:\Program Files\VideoGen');
    }
    dirs.addAll(await _readInstalledDirsFromRegistry());
    return dirs.toList();
  }

  static Future<List<String>> _readInstalledDirsFromRegistry() async {
    const script = r'''
$roots = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
)

$result = New-Object System.Collections.Generic.List[string]

function Add-InstallDirFromItem {
  param($Item)
  if ($null -eq $Item) {
    return
  }
  foreach ($name in @('Inno Setup: App Path', 'InstallLocation')) {
    $property = $Item.PSObject.Properties[$name]
    if ($null -ne $property -and $property.Value) {
      $value = $property.Value.ToString().Trim()
      if (-not [string]::IsNullOrWhiteSpace($value)) {
        [void]$result.Add($value)
      }
    }
  }
}

foreach ($root in $roots) {
  if (-not (Test-Path $root)) {
    continue
  }

  $exactKey = Join-Path $root 'HuiYunAI.Video_is1'
  if (Test-Path $exactKey) {
    Add-InstallDirFromItem (Get-ItemProperty $exactKey -ErrorAction SilentlyContinue)
  }

  Get-ChildItem $root -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -like 'HuiYunAI.Video.*_is1' } |
    Sort-Object PSChildName -Descending |
    ForEach-Object {
      Add-InstallDirFromItem (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue)
    }
}

$result |
  Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
  Select-Object -Unique |
  ConvertTo-Json -Compress
''';

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ]);
      if (result.exitCode != 0) {
        return const [];
      }

      final output = result.stdout.toString().trim();
      if (output.isEmpty) {
        return const [];
      }

      final decoded = jsonDecode(output);
      if (decoded is String) {
        return [decoded];
      }
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // ignore
    }
    return const [];
  }

  Future<void> _waitForParentProcessExit(int parentPid) async {
    if (parentPid <= 0) {
      return;
    }
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Wait-Process -Id $parentPid -ErrorAction SilentlyContinue',
    ]);
  }

  Future<void> _writeSessionLog(String logFilePath, String message) async {
    final file = File(logFilePath);
    await file.parent.create(recursive: true);
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString(
      '[$timestamp] $message${Platform.lineTerminator}',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> _writeSessionResult(
    UpdateInstallSession session, {
    required String status,
    required String message,
  }) async {
    final file = File(session.resultFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'sessionId': session.sessionId,
        'status': status,
        'targetVersion': session.targetVersion,
        'installedExePath': session.targetExecutablePath,
        'message': message,
        'logFilePath': session.logFilePath,
        'ackFilePath': session.ackFilePath,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<List<UpdateInstallSession>> _loadInstallSessions() async {
    final dir = Directory(jobsDirectoryPath);
    if (!await dir.exists()) {
      return const [];
    }

    final sessions = <UpdateInstallSession>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final session = await loadInstallSession(sessionFilePath: entity.path);
        if (session != null) {
          sessions.add(session);
        }
      } catch (_) {
        // ignore malformed session file
      }
    }

    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  Future<void> _writeSessionAck(
    UpdateInstallSession session,
    String currentVersion,
  ) async {
    final file = File(session.ackFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'sessionId': session.sessionId,
        'status': 'acknowledged',
        'targetVersion': session.targetVersion,
        'currentVersion': currentVersion,
        'executablePath': currentExecutablePath,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _markSessionResultAcknowledged(
    UpdateInstallSession session,
    String currentVersion,
  ) async {
    final file = File(session.resultFilePath);
    Map<String, dynamic> data = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        data = <String, dynamic>{};
      }
    }

    data['sessionId'] = session.sessionId;
    data['status'] = 'acknowledged';
    data['targetVersion'] = session.targetVersion;
    data['installedExePath'] = session.targetExecutablePath;
    data['ackFilePath'] = session.ackFilePath;
    data['logFilePath'] = session.logFilePath;
    data['message'] = '新版本已确认启动并完成会话回收。';
    data['acknowledgedVersion'] = currentVersion;
    data['acknowledgedExecutablePath'] = currentExecutablePath;
    data['acknowledgedAt'] = DateTime.now().toIso8601String();

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  void _emitInstallProgress(
    UpdateInstallProgressCallback? onProgress,
    UpdateInstallSession session,
    String message,
  ) {
    if (onProgress == null) {
      return;
    }
    onProgress(session, message);
  }

  Future<void> _clearInstalledPendingUpdate(String currentVersion) async {
    final pending = await loadPendingUpdate();
    if (pending == null) {
      return;
    }
    if (isNewerAppVersion(pending.targetVersion, currentVersion)) {
      return;
    }
    await clearPendingUpdate();
  }

  Future<void> _cleanupInstallSessionArtifacts(
    UpdateInstallSession session,
  ) async {
    final stagingSessionDir = Directory(path.dirname(session.stagedRuntimeDir));
    if (await stagingSessionDir.exists()) {
      await stagingSessionDir.delete(recursive: true);
    }

    final sessionFile = File(
      _installSessionFilePathFor(session.installDir, session.sessionId),
    );
    if (await sessionFile.exists()) {
      await sessionFile.delete();
    }
  }

  Future<void> _markPendingUpdateFailed(
    String pendingFilePath,
    String reason,
  ) async {
    final file = File(pendingFilePath);
    if (!await file.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final data = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
      if (data == null) {
        return;
      }
      data['status'] = PendingUpdateStatus.failed.value;
      data['installOnNextLaunch'] = false;
      data['promptOnNextLaunch'] = true;
      data['lastFailureReason'] = reason;
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
    } catch (_) {
      // ignore pending status write failures
    }
  }

  Future<void> _clearPendingUpdateFile(String pendingFilePath) async {
    final file = File(pendingFilePath);
    if (await file.exists()) {
      await file.delete();
    }
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
    var proxySettings = await _downloadProxySettingsProvider();
    if (proxySettings.mode == Settings.updateNetworkManualProxy &&
        buildCustomProxyRule(proxySettings.customAddress) == 'DIRECT') {
      throw const UpdateException('手动代理地址无效，请填写主机和端口，例如 http://127.0.0.1:7890');
    }
    if (proxySettings.mode == Settings.updateNetworkAutomaticProxy) {
      proxySettings = proxySettings.copyWith(
        automaticProxyRule: await detectAutomaticProxyRule(),
      );
    }
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
        if (settings.mode == Settings.updateNetworkDirect) {
          return 'DIRECT';
        }
        if (settings.mode == Settings.updateNetworkManualProxy) {
          return buildCustomProxyRule(settings.customAddress);
        }
        final systemRule = findSystemProxyRule(uri);
        return systemRule == 'DIRECT'
            ? settings.automaticProxyRule ?? 'DIRECT'
            : systemRule;
      };
      return client;
    };
  }

  static Future<String?> detectAutomaticProxyRule({
    List<int> ports = const [7890, 7897, 1080],
    Duration timeout = const Duration(milliseconds: 180),
  }) async {
    final hosts = <String>['127.0.0.1'];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!hosts.contains(address.address)) {
            hosts.add(address.address);
          }
        }
      }
    } catch (_) {
      // Network interface discovery is best effort.
    }

    for (final host in hosts) {
      for (final port in ports) {
        Socket? socket;
        try {
          socket = await Socket.connect(host, port, timeout: timeout);
          return port == 1080 ? 'SOCKS $host:$port' : 'PROXY $host:$port';
        } catch (_) {
          // Try the next common local proxy endpoint.
        } finally {
          socket?.destroy();
        }
      }
    }
    return null;
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
    if (uri == null || uri.host.isEmpty || !uri.hasPort || uri.port <= 0) {
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
    return UpdateDownloadProxySettings.fromSettings(
      await loadPersistedUpdateSettings(),
    );
  }

  static Future<Settings> loadPersistedUpdateSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString('settings');
      if (raw == null || raw.trim().isEmpty) {
        return Settings.defaultSettings();
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Settings.fromJson(decoded);
      }
      if (decoded is Map) {
        return Settings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // ignore and fall back to defaults
    }
    return Settings.defaultSettings();
  }
}

class UpdateDownloadProxySettings {
  final String mode;
  final String customAddress;
  final String? automaticProxyRule;

  const UpdateDownloadProxySettings({
    required this.mode,
    required this.customAddress,
    this.automaticProxyRule,
  });

  factory UpdateDownloadProxySettings.fromSettings(Settings settings) {
    return UpdateDownloadProxySettings(
      mode: settings.updateNetworkMode,
      customAddress: settings.updateManualProxyUrl,
    );
  }

  UpdateDownloadProxySettings copyWith({String? automaticProxyRule}) {
    return UpdateDownloadProxySettings(
      mode: mode,
      customAddress: customAddress,
      automaticProxyRule: automaticProxyRule ?? this.automaticProxyRule,
    );
  }
}

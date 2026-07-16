import 'dart:convert';

enum UpdateInstallSessionStatus {
  prepared,
  launching,
  installing,
  completed,
  failed,
}

enum UpdateInstallProgressStage {
  preparing,
  waitingForAppExit,
  verifyingPackage,
  requestingElevation,
  installingFiles,
  finalizing,
  launchingApplication,
  completed,
  failed,
}

extension UpdateInstallProgressStageValue on UpdateInstallProgressStage {
  String get value => switch (this) {
    UpdateInstallProgressStage.preparing => 'preparing',
    UpdateInstallProgressStage.waitingForAppExit => 'waiting_for_app_exit',
    UpdateInstallProgressStage.verifyingPackage => 'verifying_package',
    UpdateInstallProgressStage.requestingElevation => 'requesting_elevation',
    UpdateInstallProgressStage.installingFiles => 'installing_files',
    UpdateInstallProgressStage.finalizing => 'finalizing',
    UpdateInstallProgressStage.launchingApplication => 'launching_application',
    UpdateInstallProgressStage.completed => 'completed',
    UpdateInstallProgressStage.failed => 'failed',
  };

  String get label => switch (this) {
    UpdateInstallProgressStage.preparing => '准备更新环境',
    UpdateInstallProgressStage.waitingForAppExit => '等待旧版退出',
    UpdateInstallProgressStage.verifyingPackage => '校验安装包',
    UpdateInstallProgressStage.requestingElevation => '等待系统授权',
    UpdateInstallProgressStage.installingFiles => '写入程序文件',
    UpdateInstallProgressStage.finalizing => '完成安装收尾',
    UpdateInstallProgressStage.launchingApplication => '启动新版本',
    UpdateInstallProgressStage.completed => '更新完成',
    UpdateInstallProgressStage.failed => '更新失败',
  };
}

class UpdateInstallProgress {
  static const int installerOverallStart = 20;
  static const int installerOverallEnd = 90;

  final int percentage;
  final UpdateInstallProgressStage stage;
  final String message;
  final int? installerPercentage;

  const UpdateInstallProgress({
    required this.percentage,
    required this.stage,
    required this.message,
    this.installerPercentage,
  });

  factory UpdateInstallProgress.stage({
    required int percentage,
    required UpdateInstallProgressStage stage,
    required String message,
  }) {
    return UpdateInstallProgress(
      percentage: percentage.clamp(0, 100).toInt(),
      stage: stage,
      message: message,
    );
  }

  static UpdateInstallProgress? tryParseInstallerPayload(String raw) {
    try {
      final decoded = jsonDecode(raw.replaceFirst('\uFEFF', ''));
      if (decoded is! Map) {
        return null;
      }
      final value = int.tryParse((decoded['percentage'] ?? '').toString());
      if (value == null) {
        return null;
      }
      final installerPercentage = value.clamp(0, 100).toInt();
      final overall =
          installerOverallStart +
          ((installerOverallEnd - installerOverallStart) *
                  installerPercentage /
                  100)
              .round();
      return UpdateInstallProgress(
        percentage: overall,
        stage: UpdateInstallProgressStage.installingFiles,
        message: '正在静默安装程序文件（安装器进度 $installerPercentage%）',
        installerPercentage: installerPercentage,
      );
    } catch (_) {
      return null;
    }
  }
}

extension UpdateInstallSessionStatusValue on UpdateInstallSessionStatus {
  String get value {
    switch (this) {
      case UpdateInstallSessionStatus.prepared:
        return 'prepared';
      case UpdateInstallSessionStatus.launching:
        return 'launching';
      case UpdateInstallSessionStatus.installing:
        return 'installing';
      case UpdateInstallSessionStatus.completed:
        return 'completed';
      case UpdateInstallSessionStatus.failed:
        return 'failed';
    }
  }
}

UpdateInstallSessionStatus updateInstallSessionStatusFromValue(String value) {
  switch (value.trim().toLowerCase()) {
    case 'launching':
      return UpdateInstallSessionStatus.launching;
    case 'installing':
      return UpdateInstallSessionStatus.installing;
    case 'completed':
      return UpdateInstallSessionStatus.completed;
    case 'failed':
      return UpdateInstallSessionStatus.failed;
    case 'prepared':
    default:
      return UpdateInstallSessionStatus.prepared;
  }
}

class UpdateInstallSession {
  final String sessionId;
  final String targetVersion;
  final String installerPath;
  final String installerSha256;
  final String installDir;
  final String executableName;
  final String targetExecutablePath;
  final String stagedRuntimeDir;
  final String stagedExecutablePath;
  final String pendingUpdateFilePath;
  final String sourcePendingUpdateFilePath;
  final String resultFilePath;
  final String ackFilePath;
  final String logFilePath;
  final String progressFilePath;
  final String createdAt;
  final int parentPid;
  final UpdateInstallSessionStatus status;
  final String lastError;

  const UpdateInstallSession({
    required this.sessionId,
    required this.targetVersion,
    required this.installerPath,
    required this.installerSha256,
    required this.installDir,
    required this.executableName,
    required this.targetExecutablePath,
    required this.stagedRuntimeDir,
    required this.stagedExecutablePath,
    required this.pendingUpdateFilePath,
    required this.sourcePendingUpdateFilePath,
    required this.resultFilePath,
    required this.ackFilePath,
    required this.logFilePath,
    this.progressFilePath = '',
    required this.createdAt,
    required this.parentPid,
    this.status = UpdateInstallSessionStatus.prepared,
    this.lastError = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'targetVersion': targetVersion,
      'installerPath': installerPath,
      'installerSha256': installerSha256,
      'installDir': installDir,
      'executableName': executableName,
      'targetExecutablePath': targetExecutablePath,
      'stagedRuntimeDir': stagedRuntimeDir,
      'stagedExecutablePath': stagedExecutablePath,
      'pendingUpdateFilePath': pendingUpdateFilePath,
      'sourcePendingUpdateFilePath': sourcePendingUpdateFilePath,
      'resultFilePath': resultFilePath,
      'ackFilePath': ackFilePath,
      'logFilePath': logFilePath,
      'progressFilePath': progressFilePath,
      'createdAt': createdAt,
      'parentPid': parentPid,
      'status': status.value,
      'lastError': lastError,
    };
  }

  factory UpdateInstallSession.fromJson(Map<String, dynamic> json) {
    return UpdateInstallSession(
      sessionId: (json['sessionId'] ?? '').toString(),
      targetVersion: (json['targetVersion'] ?? '').toString(),
      installerPath: (json['installerPath'] ?? '').toString(),
      installerSha256: (json['installerSha256'] ?? '').toString(),
      installDir: (json['installDir'] ?? '').toString(),
      executableName: (json['executableName'] ?? '').toString(),
      targetExecutablePath: (json['targetExecutablePath'] ?? '').toString(),
      stagedRuntimeDir: (json['stagedRuntimeDir'] ?? '').toString(),
      stagedExecutablePath: (json['stagedExecutablePath'] ?? '').toString(),
      pendingUpdateFilePath: (json['pendingUpdateFilePath'] ?? '').toString(),
      sourcePendingUpdateFilePath:
          (json['sourcePendingUpdateFilePath'] ??
                  json['pendingUpdateFilePath'] ??
                  '')
              .toString(),
      resultFilePath: (json['resultFilePath'] ?? '').toString(),
      ackFilePath: (json['ackFilePath'] ?? '').toString(),
      logFilePath: (json['logFilePath'] ?? '').toString(),
      progressFilePath: (json['progressFilePath'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      parentPid: int.tryParse((json['parentPid'] ?? '0').toString()) ?? 0,
      status: updateInstallSessionStatusFromValue(
        (json['status'] ?? '').toString(),
      ),
      lastError: (json['lastError'] ?? '').toString(),
    );
  }

  UpdateInstallSession copyWith({
    String? sessionId,
    String? targetVersion,
    String? installerPath,
    String? installerSha256,
    String? installDir,
    String? executableName,
    String? targetExecutablePath,
    String? stagedRuntimeDir,
    String? stagedExecutablePath,
    String? pendingUpdateFilePath,
    String? sourcePendingUpdateFilePath,
    String? resultFilePath,
    String? ackFilePath,
    String? logFilePath,
    String? progressFilePath,
    String? createdAt,
    int? parentPid,
    UpdateInstallSessionStatus? status,
    String? lastError,
  }) {
    return UpdateInstallSession(
      sessionId: sessionId ?? this.sessionId,
      targetVersion: targetVersion ?? this.targetVersion,
      installerPath: installerPath ?? this.installerPath,
      installerSha256: installerSha256 ?? this.installerSha256,
      installDir: installDir ?? this.installDir,
      executableName: executableName ?? this.executableName,
      targetExecutablePath: targetExecutablePath ?? this.targetExecutablePath,
      stagedRuntimeDir: stagedRuntimeDir ?? this.stagedRuntimeDir,
      stagedExecutablePath: stagedExecutablePath ?? this.stagedExecutablePath,
      pendingUpdateFilePath:
          pendingUpdateFilePath ?? this.pendingUpdateFilePath,
      sourcePendingUpdateFilePath:
          sourcePendingUpdateFilePath ?? this.sourcePendingUpdateFilePath,
      resultFilePath: resultFilePath ?? this.resultFilePath,
      ackFilePath: ackFilePath ?? this.ackFilePath,
      logFilePath: logFilePath ?? this.logFilePath,
      progressFilePath: progressFilePath ?? this.progressFilePath,
      createdAt: createdAt ?? this.createdAt,
      parentPid: parentPid ?? this.parentPid,
      status: status ?? this.status,
      lastError: lastError ?? this.lastError,
    );
  }
}

class UpdateInstallSessionLaunchArgs {
  static const sessionIdPrefix = '--run-update-session=';
  static const sessionFilePathPrefix = '--update-session-file=';

  final String sessionId;
  final String sessionFilePath;

  const UpdateInstallSessionLaunchArgs({
    required this.sessionId,
    required this.sessionFilePath,
  });

  static UpdateInstallSessionLaunchArgs? tryParse(List<String> args) {
    String? sessionId;
    String? sessionFilePath;
    for (final raw in args) {
      if (raw.startsWith(sessionIdPrefix)) {
        sessionId = raw.substring(sessionIdPrefix.length).trim();
      } else if (raw.startsWith(sessionFilePathPrefix)) {
        sessionFilePath = raw.substring(sessionFilePathPrefix.length).trim();
      }
    }
    if (sessionId == null ||
        sessionId.isEmpty ||
        sessionFilePath == null ||
        sessionFilePath.isEmpty) {
      return null;
    }
    return UpdateInstallSessionLaunchArgs(
      sessionId: sessionId,
      sessionFilePath: sessionFilePath,
    );
  }
}

UpdateInstallSessionLaunchArgs? resolveUpdateInstallSessionLaunchArgs(
  List<String> mainArguments, {
  List<String> fallbackExecutableArguments = const [],
}) {
  return UpdateInstallSessionLaunchArgs.tryParse(mainArguments) ??
      UpdateInstallSessionLaunchArgs.tryParse(fallbackExecutableArguments);
}

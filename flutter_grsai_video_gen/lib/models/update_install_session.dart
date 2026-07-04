enum UpdateInstallSessionStatus {
  prepared,
  launching,
  installing,
  completed,
  failed,
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

import 'package:path/path.dart' as path;

import 'update_info.dart';

enum PendingUpdateStatus { downloaded, scheduled, installing, failed }

extension PendingUpdateStatusValue on PendingUpdateStatus {
  String get value {
    switch (this) {
      case PendingUpdateStatus.downloaded:
        return 'downloaded';
      case PendingUpdateStatus.scheduled:
        return 'scheduled';
      case PendingUpdateStatus.installing:
        return 'installing';
      case PendingUpdateStatus.failed:
        return 'failed';
    }
  }
}

PendingUpdateStatus pendingUpdateStatusFromValue(String value) {
  switch (value.trim().toLowerCase()) {
    case 'scheduled':
      return PendingUpdateStatus.scheduled;
    case 'installing':
      return PendingUpdateStatus.installing;
    case 'failed':
      return PendingUpdateStatus.failed;
    case 'downloaded':
    default:
      return PendingUpdateStatus.downloaded;
  }
}

class PendingUpdateJob {
  final UpdateInfo info;
  final String installerPath;
  final String sha256;
  final String downloadedAt;
  final PendingUpdateStatus status;
  final bool installOnNextLaunch;
  final bool promptOnNextLaunch;
  final String lastFailureReason;

  const PendingUpdateJob({
    required this.info,
    required this.installerPath,
    required this.sha256,
    required this.downloadedAt,
    this.status = PendingUpdateStatus.downloaded,
    this.installOnNextLaunch = false,
    this.promptOnNextLaunch = false,
    this.lastFailureReason = '',
  });

  String get targetVersion => info.version;

  String get installerName => path.basename(installerPath);

  Map<String, dynamic> toJson() {
    return {
      'info': info.toJson(),
      'targetVersion': targetVersion,
      'installerPath': installerPath,
      'sha256': sha256,
      'downloadedAt': downloadedAt,
      'status': status.value,
      'installOnNextLaunch': installOnNextLaunch,
      'promptOnNextLaunch': promptOnNextLaunch,
      'lastFailureReason': lastFailureReason,
    };
  }

  factory PendingUpdateJob.fromJson(Map<String, dynamic> json) {
    final installerPath = (json['installerPath'] ?? '').toString().trim();
    final downloadedAt = (json['downloadedAt'] ?? '').toString().trim();
    final infoJson = json['info'];

    final info = infoJson is Map<String, dynamic>
        ? UpdateInfo.fromJson(infoJson)
        : infoJson is Map
        ? UpdateInfo.fromJson(Map<String, dynamic>.from(infoJson))
        : UpdateInfo(
            version: (json['targetVersion'] ?? json['version'] ?? 'V0.0.0')
                .toString(),
            installerName:
                (json['installerName'] ?? path.basename(installerPath))
                    .toString(),
            installerUrl: (json['installerUrl'] ?? 'local://pending')
                .toString(),
            sha256: (json['sha256'] ?? '').toString(),
            size: int.tryParse((json['size'] ?? '0').toString()) ?? 0,
            publishedAt: (json['publishedAt'] ?? downloadedAt).toString(),
            releaseNotes: (json['releaseNotes'] ?? '').toString(),
            mandatory: json['mandatory'] == true,
          );

    return PendingUpdateJob(
      info: info,
      installerPath: installerPath,
      sha256: (json['sha256'] ?? '').toString().trim(),
      downloadedAt: downloadedAt,
      status: pendingUpdateStatusFromValue((json['status'] ?? '').toString()),
      installOnNextLaunch: json['installOnNextLaunch'] == true,
      promptOnNextLaunch: json['promptOnNextLaunch'] == true,
      lastFailureReason: (json['lastFailureReason'] ?? '').toString(),
    );
  }

  PendingUpdateJob copyWith({
    UpdateInfo? info,
    String? installerPath,
    String? sha256,
    String? downloadedAt,
    PendingUpdateStatus? status,
    bool? installOnNextLaunch,
    bool? promptOnNextLaunch,
    String? lastFailureReason,
  }) {
    return PendingUpdateJob(
      info: info ?? this.info,
      installerPath: installerPath ?? this.installerPath,
      sha256: sha256 ?? this.sha256,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      status: status ?? this.status,
      installOnNextLaunch: installOnNextLaunch ?? this.installOnNextLaunch,
      promptOnNextLaunch: promptOnNextLaunch ?? this.promptOnNextLaunch,
      lastFailureReason: lastFailureReason ?? this.lastFailureReason,
    );
  }
}

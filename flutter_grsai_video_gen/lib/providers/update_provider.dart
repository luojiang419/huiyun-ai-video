import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_version.dart';
import '../models/update_info.dart';
import '../services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  latest,
  available,
  downloading,
  installing,
  failed,
}

class UpdateState {
  final UpdateStatus status;
  final UpdateInfo? info;
  final double progress;
  final String? message;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.info,
    this.progress = 0,
    this.message,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    UpdateInfo? info,
    double? progress,
    String? message,
  }) {
    return UpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      progress: progress ?? this.progress,
      message: message,
    );
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

final updateProvider = StateNotifierProvider<UpdateNotifier, UpdateState>((
  ref,
) {
  return UpdateNotifier(ref.read(updateServiceProvider));
});

class UpdateNotifier extends StateNotifier<UpdateState> {
  final UpdateService _service;
  bool _autoChecked = false;

  UpdateNotifier(this._service) : super(const UpdateState());

  Future<UpdateInfo?> checkForUpdate({
    bool includeSkipped = false,
    bool quiet = false,
    bool auto = false,
  }) async {
    if (auto && _autoChecked) {
      return null;
    }
    if (auto) {
      _autoChecked = true;
    }

    state = const UpdateState(status: UpdateStatus.checking, message: '正在检查更新');
    try {
      final info = await _service.checkForUpdate(
        currentVersion: appReleaseVersion,
        includeSkipped: includeSkipped,
      );
      state = info == null
          ? const UpdateState(status: UpdateStatus.latest, message: '当前已是最新版')
          : UpdateState(
              status: UpdateStatus.available,
              info: info,
              message: '发现新版本 ${info.version}',
            );
      return info;
    } catch (error) {
      state = UpdateState(
        status: UpdateStatus.failed,
        message: error.toString(),
      );
      if (quiet) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> skipVersion(String version) async {
    await _service.skipVersion(version);
    state = UpdateState(status: UpdateStatus.latest, message: '已跳过 $version');
  }

  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    state = UpdateState(
      status: UpdateStatus.downloading,
      info: info,
      message: '正在下载 ${info.version}',
    );
    try {
      final installerPath = await _service.downloadInstaller(
        info,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          onProgress?.call(progress);
          state = UpdateState(
            status: UpdateStatus.downloading,
            info: info,
            progress: progress,
            message: '正在下载 ${info.version}',
          );
        },
      );
      state = UpdateState(
        status: UpdateStatus.installing,
        info: info,
        progress: 1,
        message: '正在启动安装器',
      );
      await _service.launchInstallerAndExit(installerPath);
    } catch (error) {
      state = UpdateState(
        status: UpdateStatus.failed,
        info: info,
        message: error.toString(),
      );
      rethrow;
    }
  }
}

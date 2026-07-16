import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_version.dart';
import '../models/settings.dart';
import '../models/pending_update_job.dart';
import '../services/update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  downloading,
  ready,
  installing,
  latest,
  failed,
}

class UpdateState {
  final UpdateStatus status;
  final PendingUpdateJob? pendingJob;
  final double progress;
  final String? message;
  final String? errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.pendingJob,
    this.progress = 0,
    this.message,
    this.errorMessage,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    PendingUpdateJob? pendingJob,
    bool clearPendingJob = false,
    double? progress,
    String? message,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      pendingJob: clearPendingJob ? null : (pendingJob ?? this.pendingJob),
      progress: progress ?? this.progress,
      message: message,
      errorMessage: errorMessage,
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
  bool _startupHandled = false;
  bool _operationInProgress = false;

  UpdateNotifier(this._service) : super(const UpdateState());

  Future<PendingUpdateJob?> prepareStartupUpdate() async {
    if (_startupHandled) {
      return state.pendingJob;
    }
    _startupHandled = true;
    final settings = await UpdateService.loadPersistedUpdateSettings();
    if (settings.updatePolicy == Settings.updatePolicyDisabled) {
      state = const UpdateState(status: UpdateStatus.idle, message: '更新已禁止');
      return null;
    }
    if (settings.updatePolicy == Settings.updatePolicyManual) {
      final recovered = await _service.reconcilePendingUpdate(
        currentVersion: appReleaseVersion,
      );
      if (recovered == null) return null;
      state = UpdateState(
        status: recovered.status == PendingUpdateStatus.failed
            ? UpdateStatus.failed
            : UpdateStatus.ready,
        pendingJob: recovered,
        progress: 1,
        message: '已检测到待安装更新 ${recovered.targetVersion}',
        errorMessage: recovered.lastFailureReason.isEmpty
            ? null
            : recovered.lastFailureReason,
      );
      return recovered;
    }
    try {
      return await checkAndDownloadUpdate(auto: true, includeSkipped: false);
    } catch (_) {
      // Automatic update failures must never block normal application startup.
      return null;
    }
  }

  Future<PendingUpdateJob?> checkAndDownloadUpdate({
    bool includeSkipped = false,
    bool auto = false,
  }) async {
    if (_operationInProgress) {
      return state.pendingJob;
    }
    final settings = await UpdateService.loadPersistedUpdateSettings();
    if (settings.updatePolicy == Settings.updatePolicyDisabled) {
      throw const UpdateException('更新已禁止，请先修改更新策略');
    }
    _operationInProgress = true;
    try {
      state = UpdateState(
        status: UpdateStatus.checking,
        pendingJob: state.pendingJob,
        message: auto ? '正在自动检查更新' : '正在检查更新',
      );

      final recovered = await _service.reconcilePendingUpdate(
        currentVersion: appReleaseVersion,
      );
      if (recovered != null) {
        state = UpdateState(
          status: recovered.status == PendingUpdateStatus.failed
              ? UpdateStatus.failed
              : UpdateStatus.ready,
          pendingJob: recovered,
          progress: 1,
          message: recovered.status == PendingUpdateStatus.failed
              ? '检测到上次未完成的更新包，请重新安装'
              : '已检测到待安装更新 ${recovered.targetVersion}',
          errorMessage: recovered.lastFailureReason.isEmpty
              ? null
              : recovered.lastFailureReason,
        );
        return recovered;
      }

      final job = await _service.downloadLatestUpdateIfNeeded(
        currentVersion: appReleaseVersion,
        includeSkipped: includeSkipped,
        promptOnNextLaunch: true,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          state = UpdateState(
            status: UpdateStatus.downloading,
            progress: progress,
            message: '正在下载更新包',
          );
        },
      );

      if (job == null) {
        state = const UpdateState(
          status: UpdateStatus.latest,
          message: '当前已是最新版',
        );
        return null;
      }

      state = UpdateState(
        status: UpdateStatus.ready,
        pendingJob: job,
        progress: 1,
        message: '更新包已下载完成：${job.targetVersion}',
      );
      return job;
    } catch (error) {
      state = UpdateState(
        status: UpdateStatus.failed,
        pendingJob: state.pendingJob,
        message: auto ? '自动更新检查失败' : '检查更新失败',
        errorMessage: error.toString(),
      );
      rethrow;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<PendingUpdateJob> scheduleInstallOnNextLaunch({
    PendingUpdateJob? job,
  }) async {
    if (job != null) {
      await _service.savePendingUpdate(job);
    }
    final scheduled = await _service.scheduleInstallOnNextLaunch();
    state = UpdateState(
      status: UpdateStatus.ready,
      pendingJob: scheduled,
      progress: 1,
      message: '已设置为下次启动时自动更新',
    );
    return scheduled;
  }

  Future<void> installPendingUpdate({PendingUpdateJob? job}) async {
    final pending =
        job ?? state.pendingJob ?? await _service.loadPendingUpdate();
    if (pending == null) {
      throw const UpdateException('未找到待安装的更新包');
    }

    state = UpdateState(
      status: UpdateStatus.installing,
      pendingJob: pending,
      progress: 1,
      message: '正在打开独立更新器 ${pending.targetVersion}',
    );
    try {
      await _service.launchSilentUpdateAndExit(job: pending);
    } catch (error) {
      state = UpdateState(
        status: UpdateStatus.failed,
        pendingJob: pending,
        progress: 1,
        message: '安装更新失败',
        errorMessage: error.toString(),
      );
      rethrow;
    }
  }
}

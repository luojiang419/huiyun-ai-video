import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

class _SettingsUpdateService extends UpdateService {
  _SettingsUpdateService({required String appDirectory})
    : super(updateJsonUrl: 'http://127.0.0.1', appDirectory: appDirectory);

  int downloadCheckCount = 0;
  int installCount = 0;

  @override
  Future<PendingUpdateJob?> downloadLatestUpdateIfNeeded({
    required String currentVersion,
    bool includeSkipped = false,
    bool promptOnNextLaunch = false,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    downloadCheckCount++;
    return PendingUpdateJob(
      info: const UpdateInfo(
        version: 'V8.9',
        installerName: '影视版-安装包-V8.9.exe',
        installerUrl: 'https://example.com/installer.exe',
        sha256: 'ABC123',
        size: 1024,
        publishedAt: '2026-06-27T00:00:00Z',
        releaseNotes: '测试更新',
        mandatory: false,
      ),
      installerPath: '$appDirectory${Platform.pathSeparator}影视版-安装包-V8.9.exe',
      sha256: 'ABC123',
      downloadedAt: '2026-06-27T00:00:00Z',
    );
  }

  @override
  Future<void> launchSilentUpdateAndExit({PendingUpdateJob? job}) async {
    installCount++;
  }
}

void main() {
  test(
    'settings update flow checks, downloads and installs immediately',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'settings-update-provider-test-',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final service = _SettingsUpdateService(appDirectory: tempDir.path);
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(updateProvider.notifier);
      final job = await notifier.checkAndDownloadUpdate(includeSkipped: true);
      await notifier.installPendingUpdate(job: job);

      expect(job, isNotNull);
      expect(job!.targetVersion, 'V8.9');
      expect(service.downloadCheckCount, 1);
      expect(service.installCount, 1);
    },
  );
}

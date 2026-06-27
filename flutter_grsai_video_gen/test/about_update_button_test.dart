import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';

class _NoopUpdateService extends UpdateService {
  _NoopUpdateService({required String appDirectory})
    : super(updateJsonUrl: 'http://127.0.0.1', appDirectory: appDirectory);

  int checkCount = 0;

  @override
  Future<PendingUpdateJob?> downloadLatestUpdateIfNeeded({
    required String currentVersion,
    bool includeSkipped = false,
    bool promptOnNextLaunch = false,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    checkCount++;
    return null;
  }
}

void main() {
  test('about screen manual check uses shared update flow', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'about-update-button-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final service = _NoopUpdateService(appDirectory: tempDir.path);
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final job = await container
        .read(updateProvider.notifier)
        .checkAndDownloadUpdate(includeSkipped: true);

    expect(job, isNull);
    expect(service.checkCount, 1);
  });
}

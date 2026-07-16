import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';
import 'package:flutter_grsai_video_gen/models/settings.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PolicyUpdateService extends UpdateService {
  _PolicyUpdateService({required String appDirectory})
    : super(updateJsonUrl: 'http://127.0.0.1', appDirectory: appDirectory);

  int reconcileCount = 0;
  int downloadCheckCount = 0;

  @override
  Future<PendingUpdateJob?> reconcilePendingUpdate({
    required String currentVersion,
  }) async {
    reconcileCount++;
    return null;
  }

  @override
  Future<PendingUpdateJob?> downloadLatestUpdateIfNeeded({
    required String currentVersion,
    bool includeSkipped = false,
    bool promptOnNextLaunch = false,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    downloadCheckCount++;
    return null;
  }
}

void main() {
  Future<(_PolicyUpdateService, ProviderContainer)> createContainer(
    String policy,
  ) async {
    final settings = Settings.defaultSettings().copyWith(updatePolicy: policy);
    SharedPreferences.setMockInitialValues({
      'settings': jsonEncode(settings.toJson()),
    });
    final tempDir = await Directory.systemTemp.createTemp(
      'update-policy-test-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final service = _PolicyUpdateService(appDirectory: tempDir.path);
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    return (service, container);
  }

  test('automatic policy checks the network once on startup', () async {
    final (service, container) = await createContainer(
      Settings.updatePolicyAutomatic,
    );

    await container.read(updateProvider.notifier).prepareStartupUpdate();

    expect(service.reconcileCount, 1);
    expect(service.downloadCheckCount, 1);
  });

  test(
    'manual policy only reconciles local pending state on startup',
    () async {
      final (service, container) = await createContainer(
        Settings.updatePolicyManual,
      );

      await container.read(updateProvider.notifier).prepareStartupUpdate();

      expect(service.reconcileCount, 1);
      expect(service.downloadCheckCount, 0);
    },
  );

  test('disabled policy performs no startup update work', () async {
    final (service, container) = await createContainer(
      Settings.updatePolicyDisabled,
    );

    await container.read(updateProvider.notifier).prepareStartupUpdate();

    expect(service.reconcileCount, 0);
    expect(service.downloadCheckCount, 0);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/update_install_session.dart';
import 'package:flutter_grsai_video_gen/providers/update_provider.dart';
import 'package:flutter_grsai_video_gen/screens/update_installer_screen.dart';
import 'package:flutter_grsai_video_gen/services/update_service.dart';

class _FakeUpdateInstallerService extends UpdateService {
  final UpdateInstallSession session;
  final bool shouldFail;

  _FakeUpdateInstallerService({required this.session, this.shouldFail = false})
    : super(
        updateJsonUrl: 'http://127.0.0.1',
        appDirectory: Directory.systemTemp.path,
      );

  int loadCount = 0;
  int runCount = 0;

  @override
  Future<UpdateInstallSession?> loadInstallSession({
    required String sessionFilePath,
  }) async {
    loadCount++;
    return session;
  }

  @override
  Future<void> runDetachedInstallSession({
    required String sessionFilePath,
    String? expectedSessionId,
    UpdateInstallProgressCallback? onProgress,
  }) async {
    runCount++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    onProgress?.call(
      session.copyWith(status: UpdateInstallSessionStatus.installing),
      const UpdateInstallProgress(
        percentage: 55,
        stage: UpdateInstallProgressStage.installingFiles,
        message: '正在静默安装程序文件（安装器进度 50%）',
        installerPercentage: 50,
      ),
    );

    await Future<void>.delayed(const Duration(seconds: 1));
    if (shouldFail) {
      final failedSession = session.copyWith(
        status: UpdateInstallSessionStatus.failed,
        lastError: '安装器退出码: 1',
      );
      onProgress?.call(
        failedSession,
        const UpdateInstallProgress(
          percentage: 55,
          stage: UpdateInstallProgressStage.failed,
          message: '更新失败：安装器退出码: 1',
          installerPercentage: 50,
        ),
      );
      throw const UpdateException('安装器退出码: 1');
    }

    onProgress?.call(
      session.copyWith(status: UpdateInstallSessionStatus.completed),
      const UpdateInstallProgress(
        percentage: 100,
        stage: UpdateInstallProgressStage.completed,
        message: '新版本已启动，更新程序即将退出',
      ),
    );
  }
}

UpdateInstallSession _buildSession() {
  return const UpdateInstallSession(
    sessionId: 'session-1',
    targetVersion: 'V9.0',
    installerPath: r'C:\Temp\installer.exe',
    installerSha256: 'ABC123',
    installDir: r'D:\Program Files\HuiYun',
    executableName: 'flutter_grsai_image_gen.exe',
    targetExecutablePath:
        r'D:\Program Files\HuiYun\flutter_grsai_image_gen.exe',
    stagedRuntimeDir:
        r'D:\Program Files\HuiYun\data\.system_update\staging\session-1\runtime',
    stagedExecutablePath:
        r'D:\Program Files\HuiYun\data\.system_update\staging\session-1\runtime\flutter_grsai_image_gen.exe',
    pendingUpdateFilePath:
        r'D:\Program Files\HuiYun\data\.system_update\pending_update.json',
    sourcePendingUpdateFilePath:
        r'D:\Program Files\HuiYun\data\.system_update\pending_update.json',
    resultFilePath:
        r'D:\Program Files\HuiYun\data\.system_update\results\session-1.json',
    ackFilePath:
        r'D:\Program Files\HuiYun\data\.system_update\acks\session-1.ack',
    logFilePath:
        r'D:\Program Files\HuiYun\data\.system_update\logs\session-1.log',
    createdAt: '2026-06-29T00:00:00Z',
    parentPid: 1234,
    status: UpdateInstallSessionStatus.launching,
  );
}

int _visibleProgressPercent(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.byKey(const Key('update-progress-percent')),
  );
  return int.parse(text.data!.replaceFirst('%', ''));
}

double _visibleProgressBarValue(WidgetTester tester) {
  return tester
      .widget<LinearProgressIndicator>(
        find.byKey(const Key('update-progress-bar')),
      )
      .value!;
}

void main() {
  const launchArgs = UpdateInstallSessionLaunchArgs(
    sessionId: 'session-1',
    sessionFilePath: r'C:\Temp\session-1.json',
  );

  testWidgets(
    'update installer screen renders progress and closes on success',
    (tester) async {
      int? exitCode;
      final service = _FakeUpdateInstallerService(session: _buildSession());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateServiceProvider.overrideWithValue(service)],
          child: UpdateInstallerApp(
            launchArgs: launchArgs,
            exitHandler: (code) => exitCode = code,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 25));
      expect(find.text('写入程序文件'), findsWidgets);
      expect(find.text('正在静默安装程序文件（安装器进度 50%）'), findsOneWidget);
      expect(find.textContaining('安装器内部进度：50%'), findsOneWidget);

      final animationStart = _visibleProgressPercent(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final animationMiddle = _visibleProgressPercent(tester);
      expect(animationMiddle, greaterThan(animationStart));
      expect(animationMiddle, lessThan(55));
      expect(
        _visibleProgressBarValue(tester),
        closeTo(animationMiddle / 100, 0.02),
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(_visibleProgressPercent(tester), 55);
      expect(_visibleProgressBarValue(tester), 0.55);

      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('更新完成'), findsOneWidget);
      expect(find.text('新版本正在启动，本窗口即将自动关闭。'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      final completionAnimation = _visibleProgressPercent(tester);
      expect(completionAnimation, greaterThan(55));
      expect(completionAnimation, lessThan(100));

      await tester.pump(const Duration(milliseconds: 600));
      expect(_visibleProgressPercent(tester), 100);
      expect(_visibleProgressBarValue(tester), 1);

      await tester.pump(const Duration(milliseconds: 200));
      expect(exitCode, 0);
      expect(service.loadCount, greaterThanOrEqualTo(1));
      expect(service.runCount, 1);
    },
  );

  testWidgets(
    'update installer screen shows failure details when install fails',
    (tester) async {
      final service = _FakeUpdateInstallerService(
        session: _buildSession(),
        shouldFail: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [updateServiceProvider.overrideWithValue(service)],
          child: const UpdateInstallerApp(launchArgs: launchArgs),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));

      expect(find.text('更新失败'), findsOneWidget);
      expect(find.text('安装更新失败，请稍后重试。'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
      expect(_visibleProgressPercent(tester), 55);
      expect(find.textContaining('安装器退出码: 1'), findsWidgets);
      expect(find.textContaining(r'session-1.log'), findsOneWidget);
    },
  );
}

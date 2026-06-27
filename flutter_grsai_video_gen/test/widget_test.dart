import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/pending_update_job.dart';
import 'package:flutter_grsai_video_gen/models/update_info.dart';
import 'package:flutter_grsai_video_gen/widgets/update_prompt_dialog.dart';

PendingUpdateJob _buildJob({required bool mandatory}) {
  return PendingUpdateJob(
    info: UpdateInfo(
      version: 'V8.9',
      installerName: '影视版-安装包-V8.9.exe',
      installerUrl: 'https://example.com/installer.exe',
      sha256: 'ABC123',
      size: 1024,
      publishedAt: '2026-06-27T00:00:00Z',
      releaseNotes: '测试更新说明',
      mandatory: mandatory,
    ),
    installerPath: r'C:\Temp\影视版-安装包-V8.9.exe',
    sha256: 'ABC123',
    downloadedAt: '2026-06-27T00:00:00Z',
  );
}

void main() {
  testWidgets('optional update dialog shows install now and next launch', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UpdatePromptDialog(job: _buildJob(mandatory: false)),
          ),
        ),
      ),
    );

    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('下次启动时更新'), findsOneWidget);
  });

  testWidgets('mandatory update dialog only shows install now', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UpdatePromptDialog(job: _buildJob(mandatory: true)),
          ),
        ),
      ),
    );

    expect(find.text('立即更新'), findsOneWidget);
    expect(find.text('下次启动时更新'), findsNothing);
  });
}

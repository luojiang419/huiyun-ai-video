import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/services/generate_logic_service.dart';

void main() {
  test('queued progress text includes elapsed wait time', () {
    final text = GenerateLogicService.buildQueuedProgressText(
      progressLabel: 'AI图片生成中',
      completed: 2,
      total: 6,
      failed: 1,
      elapsedSeconds: 18,
    );

    expect(text, 'AI图片生成中 (2/6，失败1个)，已等待 18s');
  });

  test('queued terminal text includes elapsed total time', () {
    expect(
      GenerateLogicService.buildQueuedTerminalText(
        total: 4,
        failed: 0,
        elapsedSeconds: 31,
      ),
      'AI任务生成完成 (4/4)，用时 31s',
    );
    expect(
      GenerateLogicService.buildQueuedTerminalText(
        total: 4,
        failed: 2,
        elapsedSeconds: 31,
      ),
      'AI任务生成完成 (4/4)，失败2个，用时 31s',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/ai_assistant_message.dart';

void main() {
  test('AiExecutionPlan parses image tasks from JSON', () {
    final plan = AiExecutionPlan.fromJson({
      'mode': 'multi_angle',
      'prompt': 'generate multiple views',
      'delayMs': '800',
      'maxConcurrency': 3,
      'autoExecute': true,
      'imageTasks': [
        {
          'operation': 'image_edit',
          'prompt': 'front view',
          'referenceImageIds': ['ref-1'],
          'angleLabel': 'front',
          'batchCount': '2',
        },
      ],
    });

    expect(plan.mode, 'multi_angle');
    expect(plan.delayMs, 800);
    expect(plan.maxConcurrency, 3);
    expect(plan.autoExecute, isTrue);
    expect(plan.imageTasks, hasLength(1));
    expect(plan.imageTasks.first.operation, 'image_edit');
    expect(plan.imageTasks.first.referenceImageIds, ['ref-1']);
    expect(plan.imageTasks.first.batchCount, 2);
  });

  test('GenerationPlan copyWith keeps legacy compatibility', () {
    final plan = GenerationPlan(
      prompt: 'city night',
      model: 'gemini-3-pro-image-preview',
      aspectRatio: '16:9',
      imageSize: '2K',
    );

    final updated = plan.copyWith(batchCount: 4, imageSize: '4K');

    expect(updated.prompt, 'city night');
    expect(updated.model, 'gemini-3-pro-image-preview');
    expect(updated.batchCount, 4);
    expect(updated.imageSize, '4K');
  });
}

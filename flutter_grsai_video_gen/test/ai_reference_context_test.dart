import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/models/ai_assistant_message.dart';

void main() {
  test('AiReferenceContext round trips through JSON', () {
    final context = AiReferenceContext(
      id: 'ref-man',
      name: 'man.png',
      path: r'G:\tmp\man.png',
      description: 'a man wearing a dark coat',
      tags: const ['person', 'coat'],
    );

    final restored = AiReferenceContext.fromJson(context.toJson());

    expect(restored.id, context.id);
    expect(restored.name, context.name);
    expect(restored.path, context.path);
    expect(restored.description, context.description);
    expect(restored.tags, context.tags);
  });

  test('AiAssistantMessage preserves execution plan payload', () {
    final plan = AiExecutionPlan(
      mode: 'image_generate',
      prompt: 'city',
      imageTasks: [AiImageTaskPlan(prompt: 'city')],
    );
    final message = AiAssistantMessage(
      type: AssistantMessageType.text,
      text: 'running',
      executionPlan: plan.toJson(),
    );

    final restored = AiAssistantMessage.fromJson(message.toJson());

    expect(restored.executionPlan, isNotNull);
    expect(restored.executionPlan!['mode'], 'image_generate');
    expect(restored.executionPlan!['imageTasks'], isA<List>());
  });
}

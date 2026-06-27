import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_grsai_video_gen/services/generate_logic_service.dart';

void main() {
  test('GenerateImageTaskRequest carries current-page generation params', () {
    const request = GenerateImageTaskRequest(
      prompt: 'front view',
      model: 'gemini-3-pro-image-preview',
      aspectRatio: '16:9',
      imageSize: '2K',
      imageQuality: 'auto',
      sampleSteps: null,
      referenceImages: ['base64'],
      referenceImagePaths: [r'G:\tmp\ref.png'],
    );

    expect(request.prompt, 'front view');
    expect(request.model, 'gemini-3-pro-image-preview');
    expect(request.aspectRatio, '16:9');
    expect(request.imageSize, '2K');
    expect(request.referenceImages, ['base64']);
    expect(request.referenceImagePaths, [r'G:\tmp\ref.png']);
  });

  test('buildReferenceInputs keeps path-only film workshop references', () {
    final inputs = GenerateLogicService.buildReferenceInputs(const [], const [
      r'G:\tmp\hero.png',
      r'G:\tmp\prop.png',
    ]);

    expect(inputs, [r'G:\tmp\hero.png', r'G:\tmp\prop.png']);
  });

  test('buildReferenceInputs prefers paths and falls back to inline data', () {
    final inputs = GenerateLogicService.buildReferenceInputs(
      const ['base64-a', 'data:image/jpeg;base64,base64-b', ''],
      const [r'G:\tmp\hero.png', '', r'G:\tmp\prop.png'],
    );

    expect(inputs, [
      r'G:\tmp\hero.png',
      'data:image/jpeg;base64,base64-b',
      r'G:\tmp\prop.png',
    ]);
  });
}

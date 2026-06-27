import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/utils/gpt_image_generation_preset.dart';

void main() {
  String legacyResolver(String aspectRatio, String imageSize) {
    if (aspectRatio == '16:9' && imageSize == '4K') {
      return '3840x2160';
    }
    if (aspectRatio == '16:9' && imageSize == '2K') {
      return '2048x1152';
    }
    if (aspectRatio == '9:16' && imageSize == '4K') {
      return '2160x3840';
    }
    if (aspectRatio == '9:16' && imageSize == '2K') {
      return '1152x2048';
    }
    return '1024x1024';
  }

  test('maps legacy size tier to vip resolution options', () {
    final result = GptImageGenerationPreset.normalizeImageSize(
      model: GptImageGenerationPreset.vipModel,
      aspectRatio: '16:9',
      value: '4K',
    );
    expect(result, '3840x2160');
  });

  test('vip draw request prefers exact selected resolution', () {
    final result = GptImageGenerationPreset.resolveDrawAspectRatio(
      model: GptImageGenerationPreset.vipModel,
      aspectRatio: '16:9',
      imageSize: '3840x2160',
      legacyResolver: legacyResolver,
    );
    expect(result, '3840x2160');
  });

  test('vip openai request falls back to preferred ratio resolution', () {
    final result = GptImageGenerationPreset.resolveOpenAiSize(
      model: GptImageGenerationPreset.vipModel,
      aspectRatio: '9:16',
      imageSize: 'auto',
      legacyResolver: legacyResolver,
    );
    expect(result, '1152x2048');
  });

  test('standard gpt-image draw request uses legacy ratio+size mapping', () {
    final result = GptImageGenerationPreset.resolveDrawAspectRatio(
      model: GptImageGenerationPreset.standardModel,
      aspectRatio: '16:9',
      imageSize: '4K',
      legacyResolver: legacyResolver,
    );
    expect(result, '3840x2160');
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/utils/z_image_base_generation_preset.dart';

void main() {
  test('normalizes unsupported z-image base params to stable defaults', () {
    expect(ZImageBaseGenerationPreset.normalizeAspectRatio('auto'), '1:1');
    expect(ZImageBaseGenerationPreset.normalizeImageSize('weird'), '1K');
    expect(
      ZImageBaseGenerationPreset.parseSampleSteps('abc', imageSize: '2K'),
      35,
    );
    expect(
      ZImageBaseGenerationPreset.parseSampleSteps('52', imageSize: '2K'),
      52,
    );
  });

  test('maps z-image base UI choices to bridge resolution and step count', () {
    expect(
      ZImageBaseGenerationPreset.resolveResolution('16:9', '2K'),
      '1536x864',
    );
    expect(
      ZImageBaseGenerationPreset.resolveResolution('1:1', '4K'),
      '2048x2048',
    );
    expect(ZImageBaseGenerationPreset.resolveSampleSteps('1K'), 30);
    expect(ZImageBaseGenerationPreset.resolveSampleSteps('4K'), 40);
  });
}

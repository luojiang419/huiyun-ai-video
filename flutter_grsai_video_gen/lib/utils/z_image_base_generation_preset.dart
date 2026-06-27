class ZImageBaseGenerationPreset {
  static const String modelId = 'z_image_base';
  static const List<String> aspectRatios = [
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];
  static const List<String> imageSizes = ['1K', '2K', '4K'];
  static const Map<String, String> imageSizeLabels = {
    '1K': '1K / 1024',
    '2K': '2K / 1536',
    '4K': '4K / 2048',
  };
  static const double guidanceScale = 4.0;
  static const double flowShift = 6.0;
  static const int minSampleSteps = 1;

  static bool isModel(String model) {
    return model.trim() == modelId;
  }

  static String normalizeAspectRatio(String aspectRatio) {
    return aspectRatios.contains(aspectRatio) ? aspectRatio : '1:1';
  }

  static String normalizeImageSize(String imageSize) {
    final normalized = imageSize.trim().toUpperCase();
    return imageSizes.contains(normalized) ? normalized : '1K';
  }

  static String resolveResolution(String aspectRatio, String imageSize) {
    final ratio = normalizeAspectRatio(aspectRatio);
    final size = normalizeImageSize(imageSize);

    if (ratio == '16:9') {
      return size == '4K'
          ? '2048x1152'
          : size == '2K'
          ? '1536x864'
          : '1280x720';
    }
    if (ratio == '9:16') {
      return size == '4K'
          ? '1152x2048'
          : size == '2K'
          ? '864x1536'
          : '720x1280';
    }
    if (ratio == '4:3') {
      return size == '4K'
          ? '1792x1344'
          : size == '2K'
          ? '1536x1152'
          : '1152x864';
    }
    if (ratio == '3:4') {
      return size == '4K'
          ? '1344x1792'
          : size == '2K'
          ? '1152x1536'
          : '864x1152';
    }
    if (ratio == '3:2') {
      return size == '4K'
          ? '1920x1280'
          : size == '2K'
          ? '1536x1024'
          : '1216x832';
    }
    if (ratio == '2:3') {
      return size == '4K'
          ? '1280x1920'
          : size == '2K'
          ? '1024x1536'
          : '832x1216';
    }
    return size == '4K'
        ? '2048x2048'
        : size == '2K'
        ? '1536x1536'
        : '1024x1024';
  }

  static int resolveSampleSteps(String imageSize) {
    final size = normalizeImageSize(imageSize);
    if (size == '4K') return 40;
    if (size == '2K') return 35;
    return 30;
  }

  static int normalizeSampleSteps(
    int? sampleSteps, {
    required String imageSize,
  }) {
    if (sampleSteps == null || sampleSteps < minSampleSteps) {
      return resolveSampleSteps(imageSize);
    }
    return sampleSteps;
  }

  static int parseSampleSteps(String raw, {required String imageSize}) {
    return normalizeSampleSteps(int.tryParse(raw.trim()), imageSize: imageSize);
  }
}

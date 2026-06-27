class GptImageGenerationPreset {
  static const String standardModel = 'gpt-image-2';
  static const String vipModel = 'gpt-image-2-vip';

  static const List<String> aspectRatios = [
    'auto',
    '1:1',
    '3:2',
    '2:3',
    '16:9',
    '9:16',
    '5:4',
    '4:5',
    '4:3',
    '3:4',
    '21:9',
    '9:21',
    '1:3',
    '3:1',
    '2:1',
    '1:2',
  ];

  static const List<String> legacyImageSizes = ['1K', '2K', '4K'];

  static const List<String> qualityOptions = ['auto', 'low', 'medium', 'high'];

  static const Map<String, String> qualityLabels = {
    'auto': '自动',
    'low': '低',
    'medium': '中',
    'high': '高',
  };

  static const Map<String, List<String>> _vipResolutionsByAspectRatio = {
    'auto': [
      'auto',
      '1024x1024',
      '1536x1024',
      '1024x1536',
      '2048x2048',
      '2048x1152',
      '1152x2048',
      '3840x2160',
      '2160x3840',
      '1536x1152',
      '1152x1536',
      '2688x1152',
      '1152x2688',
      '2496x832',
      '832x2496',
      '2048x1024',
      '1024x2048',
      '1280x1024',
      '1024x1280',
    ],
    '1:1': ['auto', '1024x1024', '2048x2048', '2880x2880'],
    '3:2': ['auto', '1536x1024', '3072x2048'],
    '2:3': ['auto', '1024x1536', '2048x3072'],
    '16:9': ['auto', '2048x1152', '3840x2160'],
    '9:16': ['auto', '1152x2048', '2160x3840'],
    '5:4': ['auto', '1280x1024', '2560x2048'],
    '4:5': ['auto', '1024x1280', '2048x2560'],
    '4:3': ['auto', '1536x1152', '3072x2304'],
    '3:4': ['auto', '1152x1536', '2304x3072'],
    '21:9': ['auto', '2688x1152', '3360x1440'],
    '9:21': ['auto', '1152x2688', '1440x3360'],
    '1:3': ['auto', '832x2496', '1248x3744'],
    '3:1': ['auto', '2496x832', '3744x1248'],
    '2:1': ['auto', '2048x1024', '3072x1536'],
    '1:2': ['auto', '1024x2048', '1536x3072'],
  };

  static bool isModel(String model) {
    final trimmed = model.trim();
    return trimmed == standardModel || trimmed == vipModel;
  }

  static bool isVipModel(String model) {
    return model.trim() == vipModel;
  }

  static bool supportsQuality(String model) {
    return isModel(model);
  }

  static bool usesResolutionDropdown(String model) {
    return isVipModel(model);
  }

  static List<String> getAspectRatioOptions(String model) {
    return isModel(model) ? aspectRatios : const [];
  }

  static List<String> getImageSizeOptions(String model, String aspectRatio) {
    if (!isVipModel(model)) {
      return legacyImageSizes;
    }

    final normalizedRatio = normalizeAspectRatio(aspectRatio);
    return _vipResolutionsByAspectRatio[normalizedRatio] ??
        _vipResolutionsByAspectRatio['auto']!;
  }

  static Map<String, String> getResolutionLabels(
    String model,
    String aspectRatio,
  ) {
    final items = getImageSizeOptions(model, aspectRatio);
    return {for (final item in items) item: resolutionLabel(item)};
  }

  static String resolutionLabel(String value) {
    if (value == 'auto') {
      return '自动';
    }

    final size = _parseResolution(value);
    if (size == null) {
      return value;
    }

    final width = size.$1;
    final height = size.$2;
    return '${width}x$height';
  }

  static String normalizeAspectRatio(String value) {
    final trimmed = value.trim();
    return aspectRatios.contains(trimmed) ? trimmed : 'auto';
  }

  static String normalizeImageSize({
    required String model,
    required String aspectRatio,
    required String value,
  }) {
    final trimmed = value.trim();

    if (isVipModel(model)) {
      final options = getImageSizeOptions(model, aspectRatio);
      if (options.contains(trimmed)) {
        return trimmed;
      }

      final legacySize = trimmed.toUpperCase();
      if (legacyImageSizes.contains(legacySize)) {
        return _mapLegacySizeToVipResolution(aspectRatio, legacySize);
      }

      final detectedTier = _detectResolutionTier(trimmed);
      if (detectedTier != null) {
        return _mapLegacySizeToVipResolution(aspectRatio, detectedTier);
      }

      return options.first;
    }

    final normalized = trimmed.toUpperCase();
    if (legacyImageSizes.contains(normalized)) {
      return normalized;
    }

    return _detectResolutionTier(trimmed) ?? legacyImageSizes.first;
  }

  static String normalizeQuality(String value) {
    final normalized = value.trim().toLowerCase();
    return qualityOptions.contains(normalized) ? normalized : 'auto';
  }

  static String resolveDrawAspectRatio({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String Function(String aspectRatio, String imageSize)
    legacyResolver,
  }) {
    final normalizedAspectRatio = normalizeAspectRatio(aspectRatio);
    final normalizedImageSize = normalizeImageSize(
      model: model,
      aspectRatio: normalizedAspectRatio,
      value: imageSize,
    );

    if (isVipModel(model)) {
      return normalizedImageSize == 'auto'
          ? normalizedAspectRatio
          : normalizedImageSize;
    }

    if (normalizedAspectRatio == 'auto') {
      return 'auto';
    }

    return legacyResolver(normalizedAspectRatio, normalizedImageSize);
  }

  static String resolveOpenAiSize({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String Function(String aspectRatio, String imageSize)
    legacyResolver,
  }) {
    final normalizedAspectRatio = normalizeAspectRatio(aspectRatio);
    final normalizedImageSize = normalizeImageSize(
      model: model,
      aspectRatio: normalizedAspectRatio,
      value: imageSize,
    );

    if (isVipModel(model)) {
      if (normalizedImageSize != 'auto') {
        return normalizedImageSize;
      }
      if (normalizedAspectRatio == 'auto') {
        return 'auto';
      }
      return _preferredVipResolution(normalizedAspectRatio) ?? 'auto';
    }

    if (normalizedAspectRatio == 'auto') {
      return 'auto';
    }

    return legacyResolver(normalizedAspectRatio, normalizedImageSize);
  }

  static String _mapLegacySizeToVipResolution(
    String aspectRatio,
    String legacySize,
  ) {
    final options = getImageSizeOptions(
      vipModel,
      aspectRatio,
    ).where((item) => item != 'auto').toList();
    if (options.isEmpty) {
      return 'auto';
    }

    if (legacySize == '4K') {
      return options.last;
    }
    if (legacySize == '2K') {
      return options.length >= 2 ? options[1] : options.last;
    }
    return options.first;
  }

  static String? _detectResolutionTier(String value) {
    final size = _parseResolution(value);
    if (size == null) {
      return null;
    }

    final longEdge = size.$1 > size.$2 ? size.$1 : size.$2;
    if (longEdge >= 3000) {
      return '4K';
    }
    if (longEdge >= 2000) {
      return '2K';
    }
    return '1K';
  }

  static String? _preferredVipResolution(String aspectRatio) {
    final items = _vipResolutionsByAspectRatio[aspectRatio];
    if (items == null) {
      return null;
    }
    for (final item in items) {
      if (item != 'auto') {
        return item;
      }
    }
    return null;
  }

  static (int, int)? _parseResolution(String value) {
    final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }

    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }
}

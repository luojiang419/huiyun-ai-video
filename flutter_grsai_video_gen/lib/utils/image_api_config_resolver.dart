import '../models/api_config.dart';
import 'gpt_image_generation_preset.dart';

class ImageApiConfigResolver {
  static const Set<String> _localWan2gpImageModels = {
    'z_image',
    'z_image_base',
    'z_image_control',
    'z_image_control2',
    'z_image_control2_1',
  };

  static bool isLocalWan2gpImageModel(String model) {
    return _localWan2gpImageModels.contains(model.trim());
  }

  static bool isGeminiImageModel(String model) {
    return model.trim().startsWith('gemini-');
  }

  static bool isGptImageModel(String model) {
    return GptImageGenerationPreset.isModel(model);
  }

  static bool isNanoBananaModel(String model) {
    return model.trim().startsWith('nano-banana');
  }

  static bool _isCustomUnifiedImageConfig(ApiConfig config) {
    final lowerUrl = config.url.toLowerCase();
    return config.id != 'builtin-grsai-image' &&
        (lowerUrl.contains('/v1/api/generate') ||
            lowerUrl.contains('grsaiapi.com'));
  }

  static bool _isCustomNanoBananaEndpoint(ApiConfig config) {
    final lowerUrl = config.url.toLowerCase();
    return config.id != 'builtin-grsai-image' &&
        lowerUrl.contains('/v1/draw/nano-banana');
  }

  static ApiConfig? resolveImageConfigForModel(
    List<ApiConfig> configs,
    String model,
  ) {
    final candidates = resolveImageConfigCandidatesForModel(configs, model);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  static List<ApiConfig> resolveImageConfigCandidatesForModel(
    List<ApiConfig> configs,
    String model,
  ) {
    final imageConfigs = configs.where((c) => c.type == 'image').toList();
    if (imageConfigs.isEmpty) {
      return const [];
    }

    final trimmedModel = model.trim();
    final exactModelMatch = _firstWhereOrNull(
      imageConfigs,
      (config) => config.model.trim() == trimmedModel,
    );
    final currentDefault = _firstWhereOrNull(
      imageConfigs,
      (config) => config.isDefault,
    );
    final firstUserCloud = _firstWhereOrNull(
      imageConfigs,
      _isUserCloudImageConfig,
    );
    final firstNonLocal = _firstWhereOrNull(
      imageConfigs,
      (config) => !_isLocalImageConfig(config),
    );
    final candidates = <ApiConfig>[];

    void addCandidate(ApiConfig? config) {
      if (config == null) {
        return;
      }
      if (candidates.any((item) => item.id == config.id)) {
        return;
      }
      candidates.add(config);
    }

    if (isLocalWan2gpImageModel(trimmedModel)) {
      addCandidate(exactModelMatch);
      addCandidate(
        _firstWhereOrNull(
          imageConfigs,
          (config) =>
              config.id == 'builtin-local-image' || _isLocalImageConfig(config),
        ),
      );
      addCandidate(currentDefault);
      addCandidate(imageConfigs.first);
      return candidates;
    }

    if (isGeminiImageModel(trimmedModel)) {
      addCandidate(exactModelMatch);
      addCandidate(_firstWhereOrNull(imageConfigs, _isBuiltinGrsaiImageConfig));
      addCandidate(
        _firstWhereOrNull(
          imageConfigs,
          (config) => config.model.trim().startsWith('gemini-'),
        ),
      );
      addCandidate(currentDefault);
      addCandidate(firstNonLocal);
      addCandidate(imageConfigs.first);
      return candidates;
    }

    if (isGptImageModel(trimmedModel)) {
      addCandidate(exactModelMatch);
      addCandidate(
        _firstWhereOrNull(imageConfigs, _isCustomUnifiedImageConfig),
      );
      addCandidate(_firstWhereOrNull(imageConfigs, _isBuiltinGrsaiImageConfig));
      addCandidate(
        _firstWhereOrNull(
          imageConfigs,
          (config) =>
              _isCustomUnifiedImageConfig(config) ||
              _isBuiltinGrsaiImageConfig(config) ||
              config.url.toLowerCase().contains('/v1/draw/completions'),
        ),
      );
      addCandidate(firstUserCloud);
      addCandidate(firstNonLocal);
      addCandidate(currentDefault);
      addCandidate(imageConfigs.first);
      return candidates;
    }

    if (isNanoBananaModel(trimmedModel)) {
      addCandidate(exactModelMatch);
      addCandidate(
        _firstWhereOrNull(imageConfigs, _isCustomNanoBananaEndpoint),
      );
      addCandidate(
        _firstWhereOrNull(imageConfigs, _isCustomUnifiedImageConfig),
      );
      addCandidate(
        _firstWhereOrNull(
          imageConfigs,
          (config) =>
              _isCustomNanoBananaEndpoint(config) ||
              _isCustomUnifiedImageConfig(config) ||
              _isBuiltinGrsaiImageConfig(config),
        ),
      );
      addCandidate(_firstWhereOrNull(imageConfigs, _isBuiltinGrsaiImageConfig));
      addCandidate(
        _firstWhereOrNull(
          imageConfigs,
          (config) => config.model.trim().startsWith('nano-banana'),
        ),
      );
      addCandidate(firstUserCloud);
      addCandidate(firstNonLocal);
      addCandidate(currentDefault);
      addCandidate(imageConfigs.first);
      return candidates;
    }

    addCandidate(exactModelMatch);
    addCandidate(currentDefault);
    addCandidate(firstNonLocal);
    addCandidate(imageConfigs.first);
    return candidates;
  }

  static bool _isBuiltinGrsaiImageConfig(ApiConfig config) {
    final lowerUrl = config.url.toLowerCase();
    return config.id == 'builtin-grsai-image' ||
        lowerUrl.contains('grsai.dakka.com.cn') ||
        lowerUrl.contains('grsaiapi.com') ||
        lowerUrl.contains('/v1/api/generate');
  }

  static bool _isLocalImageConfig(ApiConfig config) {
    final lowerUrl = config.url.toLowerCase();
    return config.id == 'builtin-local-image' ||
        lowerUrl.contains('127.0.0.1:') ||
        lowerUrl.contains('localhost:');
  }

  static bool _isUserCloudImageConfig(ApiConfig config) {
    return config.type == 'image' &&
        !_isLocalImageConfig(config) &&
        !_isBuiltinGrsaiImageConfig(config);
  }

  static T? _firstWhereOrNull<T>(
    Iterable<T> items,
    bool Function(T item) test,
  ) {
    for (final item in items) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}

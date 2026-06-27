import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_config.dart';
import '../services/config_file_service.dart';
import '../utils/image_api_config_resolver.dart';
import 'core_services_provider.dart';

final apiConfigsProvider =
    StateNotifierProvider<ApiConfigsNotifier, List<ApiConfig>>((ref) {
      return ApiConfigsNotifier(ref.read(configFileServiceProvider));
    });

class ApiConfigsNotifier extends StateNotifier<List<ApiConfig>> {
  final ConfigFileService _configService;
  Future<void>? _loadingFuture;
  static const _removedBuiltinIds = {
    'builtin-claude',
    'builtin-ollama',
    'builtin-shiying-image',
  };

  ApiConfigsNotifier(this._configService) : super([]) {
    _loadingFuture = _loadConfigs();
  }

  ApiConfig? _findLoadedConfig(List<ApiConfig> configs, String id) {
    return configs.where((config) => config.id == id).firstOrNull;
  }

  String _preferSavedValue(String? saved, String fallback) {
    final trimmed = saved?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  Future<void> ensureLoaded() async {
    if (state.isNotEmpty) {
      return;
    }
    await (_loadingFuture ??= _loadConfigs());
  }

  Future<void> _loadConfigs() async {
    try {
      final loadedConfigs = await _configService.loadApiConfigs();
      final cleanedLoadedConfigs = loadedConfigs
          .where((config) => !_removedBuiltinIds.contains(config.id))
          .toList();
      final videoSettings = await _configService.loadVideoSettingsConfig();
      final localVideoUrl = 'http://127.0.0.1:${videoSettings.wan2gp.port}';
      final localImageUrl = 'http://127.0.0.1:${videoSettings.wan2gp.port}';
      final loadedGrsai = _findLoadedConfig(
        cleanedLoadedConfigs,
        'builtin-grsai-image',
      );
      final loadedLocalImage = _findLoadedConfig(
        cleanedLoadedConfigs,
        'builtin-local-image',
      );
      final loadedLocalVideo = _findLoadedConfig(
        cleanedLoadedConfigs,
        'builtin-local-video',
      );
      final loadedLocalVision = _findLoadedConfig(
        cleanedLoadedConfigs,
        'builtin-local-vision',
      );

      final bool isGrsaiDefaultFromFile = cleanedLoadedConfigs.any(
        (c) => c.id == 'builtin-grsai-image' && c.isDefault,
      );

      // 内置 Grsai 图片生成 API
      final builtinGrsai = ApiConfig(
        id: 'builtin-grsai-image',
        name: _preferSavedValue(loadedGrsai?.name, 'Grsai图片生成'),
        type: 'image',
        url: _preferSavedValue(loadedGrsai?.url, 'https://grsai.dakka.com.cn'),
        key: loadedGrsai?.key ?? '',
        model: _preferSavedValue(
          loadedGrsai?.model,
          'gemini-3-pro-image-preview',
        ),
        isDefault: isGrsaiDefaultFromFile,
      );

      final bool isBuiltinImageDefaultFromFile = cleanedLoadedConfigs.any(
        (c) => c.id == 'builtin-local-image' && c.isDefault,
      );
      final builtinLocalImage = ApiConfig(
        id: 'builtin-local-image',
        name: _preferSavedValue(loadedLocalImage?.name, '本地Wan2GP图片模型'),
        type: 'image',
        url: _preferSavedValue(loadedLocalImage?.url, localImageUrl),
        key: loadedLocalImage?.key ?? '',
        model: _preferSavedValue(loadedLocalImage?.model, 'z_image_base'),
        isDefault: isBuiltinImageDefaultFromFile,
      );

      final bool isBuiltinVideoDefaultFromFile = cleanedLoadedConfigs.any(
        (c) => c.id == 'builtin-local-video' && c.isDefault,
      );
      final bool hasOtherDefaultVideo = cleanedLoadedConfigs.any(
        (c) =>
            c.type == 'video' && c.isDefault && c.id != 'builtin-local-video',
      );

      final builtinLocalVideo = ApiConfig(
        id: 'builtin-local-video',
        name: _preferSavedValue(loadedLocalVideo?.name, '本地Wan2GP视频模型'),
        type: 'video',
        url: _preferSavedValue(loadedLocalVideo?.url, localVideoUrl),
        key: loadedLocalVideo?.key ?? '',
        model: _preferSavedValue(
          loadedLocalVideo?.model,
          videoSettings.defaults.modelName,
        ),
        isDefault: isBuiltinVideoDefaultFromFile || !hasOtherDefaultVideo,
      );

      final bool isBuiltinVisionDefaultFromFile = cleanedLoadedConfigs.any(
        (c) => c.id == 'builtin-local-vision' && c.isDefault,
      );
      final bool hasOtherDefaultVision = cleanedLoadedConfigs.any(
        (c) =>
            c.type == 'vision' && c.isDefault && c.id != 'builtin-local-vision',
      );
      final builtinLocalVision = ApiConfig(
        id: 'builtin-local-vision',
        name: _preferSavedValue(loadedLocalVision?.name, '本地Qwen视觉模型'),
        type: 'vision',
        url: _preferSavedValue(
          loadedLocalVision?.url,
          'http://115.231.35.105:12345',
        ),
        key: loadedLocalVision?.key ?? '',
        model: _preferSavedValue(loadedLocalVision?.model, 'qwen3.5-9b-vlm'),
        isDefault: isBuiltinVisionDefaultFromFile || !hasOtherDefaultVision,
      );

      // 过滤掉内置配置（以 ID 为准），确保始终使用最新的内置定义
      final List<ApiConfig> otherConfigs = cleanedLoadedConfigs
          .where(
            (c) =>
                c.id != builtinGrsai.id &&
                c.id != builtinLocalImage.id &&
                c.id != builtinLocalVideo.id &&
                c.id != builtinLocalVision.id,
          )
          .toList();

      state = [
        builtinGrsai,
        builtinLocalImage,
        builtinLocalVideo,
        builtinLocalVision,
        ...otherConfigs,
      ];

      if (cleanedLoadedConfigs.length != loadedConfigs.length) {
        await _configService.saveApiConfigs(state);
      }
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> addConfig(ApiConfig config) async {
    state = [...state, config];
    await _configService.saveApiConfigs(state);
  }

  Future<void> updateConfig(ApiConfig config) async {
    state = state.map((c) => c.id == config.id ? config : c).toList();
    await _configService.saveApiConfigs(state);
  }

  Future<void> deleteConfig(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _configService.saveApiConfigs(state);
  }

  Future<void> setDefault(String id, String type) async {
    state = state
        .map(
          (c) => ApiConfig(
            id: c.id,
            name: c.name,
            type: c.type,
            url: c.url,
            key: c.key,
            model: c.model,
            isDefault: c.type == type ? c.id == id : c.isDefault,
          ),
        )
        .toList();
    await _configService.saveApiConfigs(state);
  }

  ApiConfig? resolveImageConfigForModel(String model) {
    return ImageApiConfigResolver.resolveImageConfigForModel(state, model);
  }

  Future<void> autoSwitchImageConfigForModel(String model) async {
    final targetConfig = resolveImageConfigForModel(model);
    if (targetConfig == null || targetConfig.isDefault) {
      return;
    }
    await setDefault(targetConfig.id, 'image');
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_config.dart';
import '../models/video_generate_params.dart';
import '../services/config_file_service.dart';
import '../services/wan2gp_bridge_service.dart';
import 'core_services_provider.dart';

final videoSettingsProvider =
    StateNotifierProvider<VideoSettingsNotifier, VideoSettingsConfig>((ref) {
      return VideoSettingsNotifier(ref.read(configFileServiceProvider));
    });

final wan2gpBridgeServiceProvider = Provider<Wan2gpBridgeService>((ref) {
  final service = Wan2gpBridgeService();
  ref.onDispose(service.dispose);
  return service;
});

class VideoSettingsNotifier extends StateNotifier<VideoSettingsConfig> {
  final ConfigFileService _configService;

  VideoSettingsNotifier(this._configService)
    : super(const VideoSettingsConfig()) {
    _load();
  }

  Future<void> _load() async {
    state = await _configService.loadVideoSettingsConfig();
  }

  Future<void> reload() async => _load();

  Future<void> updateAll(VideoSettingsConfig config) async {
    state = config;
    await _configService.saveVideoSettingsConfig(config);
  }

  Future<void> updateVlmConfig({
    String? apiUrl,
    String? apiKey,
    String? model,
  }) async {
    await updateAll(
      state.copyWith(
        vlm: state.vlm.copyWith(apiUrl: apiUrl, apiKey: apiKey, model: model),
      ),
    );
  }

  Future<void> updateBridgeConfig({
    String? pythonPath,
    String? scriptPath,
    int? port,
    bool? autoLaunch,
  }) async {
    await updateAll(
      state.copyWith(
        wan2gp: state.wan2gp.copyWith(
          pythonPath: pythonPath,
          scriptPath: scriptPath,
          port: port,
          autoLaunch: autoLaunch,
        ),
      ),
    );
  }

  Future<void> updateDefaults(VideoGenerateParams params) async {
    await updateAll(state.copyWith(defaults: params));
  }

  Future<void> updateHiddenModelIds(List<String> hiddenModelIds) async {
    await updateAll(state.copyWith(hiddenModelIds: hiddenModelIds));
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_grsai_video_gen/models/api_config.dart';
import 'package:flutter_grsai_video_gen/models/settings.dart';
import 'package:flutter_grsai_video_gen/models/video_config.dart';
import 'package:flutter_grsai_video_gen/providers/core_services_provider.dart';
import 'package:flutter_grsai_video_gen/providers/generate_provider.dart';
import 'package:flutter_grsai_video_gen/services/api_service.dart';
import 'package:flutter_grsai_video_gen/services/config_file_service.dart';
import 'package:flutter_grsai_video_gen/services/generate_logic_service.dart';

class _FakeConfigFileService extends ConfigFileService {
  _FakeConfigFileService(this.configs);

  final List<ApiConfig> configs;

  @override
  Future<List<ApiConfig>> loadApiConfigs() async => configs;

  @override
  Future<VideoSettingsConfig> loadVideoSettingsConfig() async =>
      const VideoSettingsConfig();
}

class _FakeApiService extends ApiService {
  _FakeApiService(this._responsesByUrl);

  final Map<String, List<GenerateProgress>> _responsesByUrl;
  final List<String> attemptedUrls = [];

  @override
  Stream<GenerateProgress> generateImage({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    String imageQuality = 'auto',
    int? sampleSteps,
    List<String> urls = const [],
    String uploadMethod = Settings.uploadMethodRelayUrl,
    String? outputFolder,
  }) async* {
    attemptedUrls.add(apiUrl);
    final responses =
        _responsesByUrl[apiUrl] ??
        [GenerateProgress(status: 'failed', error: 'missing response')];
    for (final progress in responses) {
      yield progress;
    }
  }
}

void main() {
  test('runImageTask falls back to the next matching image config', () async {
    SharedPreferences.setMockInitialValues({});

    final fakeApiService = _FakeApiService({
      'https://broken.example': [
        GenerateProgress(status: 'failed', error: 'broken'),
      ],
      'https://stable.example': [
        GenerateProgress(
          status: 'succeeded',
          progress: 100,
          results: ['data/output/generated_ok.png'],
        ),
      ],
    });

    final container = ProviderContainer(
      overrides: [
        apiServiceProvider.overrideWithValue(fakeApiService),
        configFileServiceProvider.overrideWithValue(
          _FakeConfigFileService([
            ApiConfig(
              id: 'builtin-grsai-image',
              name: 'Broken Grsai',
              type: 'image',
              url: 'https://broken.example',
              key: 'broken-key',
              model: 'nano-banana-fast',
              isDefault: false,
            ),
            ApiConfig(
              id: 'default-image',
              name: 'Stable',
              type: 'image',
              url: 'https://stable.example',
              key: 'stable-key',
              model: 'nano-banana-fast',
              isDefault: true,
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final results = await container
        .read(generateLogicServiceProvider)
        .runImageTask(
          const GenerateImageTaskRequest(
            prompt: '测试提示词',
            model: 'nano-banana-fast',
            aspectRatio: '16:9',
            imageSize: '2K',
          ),
        );

    expect(results, ['data/output/generated_ok.png']);
    expect(fakeApiService.attemptedUrls, [
      'https://broken.example',
      'https://stable.example',
    ]);
  });
}

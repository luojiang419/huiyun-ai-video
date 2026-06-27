import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_grsai_video_gen/models/api_config.dart';
import 'package:flutter_grsai_video_gen/utils/image_api_config_resolver.dart';

void main() {
  final configs = [
    ApiConfig(
      id: 'builtin-grsai-image',
      name: 'Grsai图片生成',
      type: 'image',
      url: 'https://grsai.dakka.com.cn',
      key: '',
      model: 'gemini-3-pro-image-preview',
      isDefault: false,
    ),
    ApiConfig(
      id: 'builtin-local-image',
      name: '本地Wan2GP图片模型',
      type: 'image',
      url: 'http://127.0.0.1:7861',
      key: '',
      model: 'z_image_base',
      isDefault: false,
    ),
    ApiConfig(
      id: 'default-image',
      name: '默认图片生成',
      type: 'image',
      url: 'https://www.shiying-api.com',
      key: '',
      model: 'gemini-3-pro-image-preview',
      isDefault: true,
    ),
  ];

  test('routes z-image models to local wan2gp image config', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel(
      configs,
      'z_image_base',
    );
    expect(config?.id, 'builtin-local-image');
  });

  test('routes gemini models to builtin grsai image config first', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel(
      configs,
      'gemini-3-pro-image-preview',
    );
    expect(config?.id, 'builtin-grsai-image');
  });

  test('returns fallback candidates for gemini models in stable order', () {
    final candidates =
        ImageApiConfigResolver.resolveImageConfigCandidatesForModel(
          configs,
          'gemini-3-pro-image-preview',
        );

    expect(candidates.map((config) => config.id).toList(), [
      'builtin-grsai-image',
      'default-image',
    ]);
  });

  test('routes nano banana models to builtin grsai image config first', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel(
      configs,
      'nano-banana-fast',
    );
    expect(config?.id, 'builtin-grsai-image');
  });

  test('prefers explicit nano banana endpoint config over builtin grsai', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel([
      ...configs,
      ApiConfig(
        id: 'custom-nano-endpoint',
        name: '自定义Nano Banana',
        type: 'image',
        url: 'https://example.com/v1/draw/nano-banana',
        key: '',
        model: '',
        isDefault: false,
      ),
    ], 'nano-banana-fast');
    expect(config?.id, 'custom-nano-endpoint');
  });

  test('prefers explicit grsai unified nano config over builtin grsai', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel([
      ...configs,
      ApiConfig(
        id: 'custom-unified-nano',
        name: '自定义Grsai统一接口',
        type: 'image',
        url: 'https://example.com/v1/api/generate',
        key: '',
        model: '',
        isDefault: false,
      ),
    ], 'nano-banana-pro');
    expect(config?.id, 'custom-unified-nano');
  });

  test('routes gpt-image-2 to builtin grsai image config first', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel(
      configs,
      'gpt-image-2',
    );
    expect(config?.id, 'builtin-grsai-image');
  });

  test('routes gpt-image-2-vip to builtin grsai image config first', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel(
      configs,
      'gpt-image-2-vip',
    );
    expect(config?.id, 'builtin-grsai-image');
  });

  test('prefers exact gpt-image-2 config over builtin grsai fallback', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel([
      ...configs,
      ApiConfig(
        id: 'openai-image',
        name: 'OpenAI图片生成',
        type: 'image',
        url: 'https://api.openai.com',
        key: '',
        model: 'gpt-image-2',
        isDefault: false,
      ),
    ], 'gpt-image-2');
    expect(config?.id, 'openai-image');
  });

  test('prefers explicit grsai unified gpt config over builtin grsai', () {
    final config = ImageApiConfigResolver.resolveImageConfigForModel([
      ...configs,
      ApiConfig(
        id: 'custom-unified-gpt',
        name: '自定义Grsai统一接口',
        type: 'image',
        url: 'https://example.com/v1/api/generate',
        key: '',
        model: '',
        isDefault: false,
      ),
    ], 'gpt-image-2-vip');
    expect(config?.id, 'custom-unified-gpt');
  });
}

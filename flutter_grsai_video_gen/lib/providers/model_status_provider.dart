import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'api_config_provider.dart';
import '../utils/image_api_config_resolver.dart';

final modelStatusProvider =
    StateNotifierProvider<ModelStatusNotifier, Map<String, bool>>((ref) {
      return ModelStatusNotifier(ref);
    });

class ModelStatusNotifier extends StateNotifier<Map<String, bool>> {
  final Ref ref;
  static const Set<String> _localWan2gpImageModels = {
    'z_image',
    'z_image_base',
    'z_image_control',
    'z_image_control2',
    'z_image_control2_1',
  };

  ModelStatusNotifier(this.ref) : super({});

  Future<void> checkModelStatus(String modelName) async {
    final configs = ref.read(apiConfigsProvider);
    final defaultConfig =
        ImageApiConfigResolver.resolveImageConfigForModel(configs, modelName) ??
        (_localWan2gpImageModels.contains(modelName)
            ? configs
                      .where(
                        (c) =>
                            c.type == 'image' && c.id == 'builtin-local-image',
                      )
                      .firstOrNull ??
                  configs
                      .where(
                        (c) =>
                            c.type == 'image' &&
                            (c.url.contains('127.0.0.1:7861') ||
                                c.url.contains('localhost:7861')),
                      )
                      .firstOrNull ??
                  configs
                      .where((c) => c.type == 'image' && c.isDefault)
                      .firstOrNull
            : configs
                  .where((c) => c.type == 'image' && c.isDefault)
                  .firstOrNull);
    if (defaultConfig == null) return;

    final apiService = ApiService();
    final status = await apiService.checkModelStatus(
      defaultConfig.url,
      modelName,
    );
    state = {...state, modelName: status};
  }

  Future<void> checkAllModels(List<String> models) async {
    for (final model in models) {
      await checkModelStatus(model);
    }
  }
}

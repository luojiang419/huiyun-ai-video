import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import 'api_config_provider.dart';

final creditsProvider = StateNotifierProvider<CreditsNotifier, int?>((ref) {
  return CreditsNotifier(ref);
});

class CreditsNotifier extends StateNotifier<int?> {
  final Ref ref;

  CreditsNotifier(this.ref) : super(null);

  Future<void> fetchCredits() async {
    final configs = ref.read(apiConfigsProvider);
    final defaultConfig = configs.where((c) => c.type == 'image' && c.isDefault).firstOrNull;
    if (defaultConfig == null) return;

    final apiService = ApiService();
    final credits = await apiService.getApiCredits(defaultConfig.url, defaultConfig.key);
    state = credits;
  }
}

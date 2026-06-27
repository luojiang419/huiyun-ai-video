import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/settings.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider((ref) => StorageService());

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>((ref) {
  return SettingsNotifier(ref.read(storageServiceProvider));
});

class SettingsNotifier extends StateNotifier<Settings> {
  final StorageService _storage;

  SettingsNotifier(this._storage) : super(Settings.defaultSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    state = await _storage.loadSettings();
  }

  Future<void> updateSettings(Settings settings) async {
    state = settings;
    await _storage.saveSettings(settings);
  }

  Future<void> updateApiUrl(String url) async {
    final newSettings = state.copyWith(apiUrl: url);
    await updateSettings(newSettings);
  }

  Future<void> updateApiKey(String key) async {
    final newSettings = state.copyWith(apiKey: key);
    await updateSettings(newSettings);
  }
}

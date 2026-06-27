import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';
import '../models/api_config.dart';
import '../models/favorite_image.dart';
import '../models/uploaded_image.dart';
import 'file_service.dart';

class StorageService {
  String _getAppDirectory() {
    final exePath = Platform.resolvedExecutable;
    return File(exePath).parent.path;
  }

  Future<Settings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('settings');
    if (json == null) return Settings.defaultSettings();
    return Settings.fromJson(jsonDecode(json));
  }

  Future<void> saveSettings(Settings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  Future<List<ApiConfig>> loadApiConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('apiConfigs');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => ApiConfig.fromJson(e)).toList();
  }

  Future<void> saveApiConfigs(List<ApiConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(configs.map((e) => e.toJson()).toList());
    await prefs.setString('apiConfigs', json);
  }

  Future<List<FavoriteImage>> loadFavorites() async {
    final appDir = _getAppDirectory();
    final favDir = Directory('$appDir/data/output/收藏');
    if (!await favDir.exists()) return [];

    final files = await favDir
        .list()
        .where((f) => f.path.endsWith('.png'))
        .toList();
    final favorites = <FavoriteImage>[];

    for (final file in files) {
      final stat = await file.stat();
      final prompt = await FileService().readImagePromptMetadata(file.path);
      favorites.add(
        FavoriteImage(
          url: file.path,
          prompt: prompt,
          timestamp: stat.modified.millisecondsSinceEpoch,
        ),
      );
    }

    favorites.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return favorites;
  }

  Future<void> saveFavorites(List<FavoriteImage> favorites) async {
    // 不需要保存到 SharedPreferences，文件系统即是存储
  }

  Future<String?> loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastSession');
  }

  Future<void> saveLastSession(String sessionName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSession', sessionName);
  }

  Future<void> saveUploadedImages(List<UploadedImage> images) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(images.map((img) => img.toJson()).toList());
    await prefs.setString('uploadedImages', json);
  }

  Future<List<UploadedImage>> loadUploadedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('uploadedImages');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => UploadedImage.fromJson(e)).toList();
  }

  Future<void> saveSelectedImages(List<UploadedImage> images) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(images.map((img) => img.toJson()).toList());
    await prefs.setString('selectedImages', json);
  }

  Future<List<UploadedImage>> loadSelectedImages() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('selectedImages');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list.map((e) => UploadedImage.fromJson(e)).toList();
  }

  Future<void> saveAssetCategoryOrder(List<String> categories) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('assetCategoryOrder', categories);
  }

  Future<List<String>?> loadAssetCategoryOrder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('assetCategoryOrder');
  }
}

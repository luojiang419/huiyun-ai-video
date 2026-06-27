import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/favorite_image.dart';
import '../services/file_service.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<FavoriteImage>>((ref) {
      return FavoritesNotifier(ref.read(storageServiceProvider));
    });

class FavoritesNotifier extends StateNotifier<List<FavoriteImage>> {
  final StorageService _storage;

  FavoritesNotifier(this._storage) : super([]) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    state = await _storage.loadFavorites();
  }

  Future<void> addFavorite(FavoriteImage favorite) async {
    final sourceFileName = favorite.url.split(Platform.pathSeparator).last;
    final appDir = _getAppDirectory();
    final favDir = Directory('$appDir/data/output/收藏');
    await favDir.create(recursive: true);

    final targetPath = '${favDir.path}/$sourceFileName';

    // 检查文件是否已存在
    if (await File(targetPath).exists()) {
      return;
    }

    final sourceFile = File(favorite.url);
    if (await sourceFile.exists()) {
      await sourceFile.copy(targetPath);
      final sourceMeta = File(FileService().buildImageMetaPath(favorite.url));
      final targetMeta = File(FileService().buildImageMetaPath(targetPath));
      if (await sourceMeta.exists()) {
        await sourceMeta.copy(targetMeta.path);
      } else if (favorite.prompt.trim().isNotEmpty) {
        await FileService().saveImagePromptMetadata(
          targetPath,
          favorite.prompt,
        );
      }

      state = [
        ...state,
        FavoriteImage(
          url: targetPath,
          prompt: favorite.prompt,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      ];
    }
  }

  bool isFavorited(String url) {
    return state.any(
      (fav) => fav.url.contains(url.split(Platform.pathSeparator).last),
    );
  }

  Future<void> removeFavorite(String url) async {
    final file = File(url);
    if (await file.exists()) {
      await file.delete();
    }
    final metaFile = File(FileService().buildImageMetaPath(url));
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
    state = state.where((fav) => fav.url != url).toList();
  }

  String _getAppDirectory() {
    final exePath = Platform.resolvedExecutable;
    return File(exePath).parent.path;
  }
}

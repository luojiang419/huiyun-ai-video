import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_item.dart';
import '../services/config_file_service.dart';
import '../services/file_service.dart';
import 'core_services_provider.dart';

final videoGalleryProvider =
    StateNotifierProvider<VideoGalleryNotifier, List<VideoItem>>((ref) {
      return VideoGalleryNotifier(
        ref.read(configFileServiceProvider),
        ref.read(fileServiceProvider),
      );
    });

class VideoGalleryNotifier extends StateNotifier<List<VideoItem>> {
  final ConfigFileService _configService;
  final FileService _fileService;

  VideoGalleryNotifier(this._configService, this._fileService) : super([]) {
    _load();
  }

  int _missingCount = 0;
  int get missingCount => _missingCount;

  Future<void> _load() async {
    state = await _configService.loadVideoGallery();
    await _repairThumbnails();
    _updateMissingCount();
  }

  Future<void> refresh() async => _load();

  Future<void> addVideo(VideoItem item) async {
    final next = await _ensureThumbnail(item);
    state = [next, ...state];
    _updateMissingCount();
    await _configService.saveVideoGallery(state);
  }

  Future<void> deleteVideo(String id) async {
    final video = state.where((item) => item.id == id).firstOrNull;
    if (video != null) {
      await _deleteFiles(video);
    }
    state = state.where((item) => item.id != id).toList();
    _updateMissingCount();
    await _configService.saveVideoGallery(state);
  }

  Future<int> deleteVideos(List<String> ids) async {
    final targets = state.where((item) => ids.contains(item.id)).toList();
    for (final item in targets) {
      await _deleteFiles(item);
    }
    state = state.where((item) => !ids.contains(item.id)).toList();
    _updateMissingCount();
    await _configService.saveVideoGallery(state);
    return targets.length;
  }

  Future<int> cleanMissingVideos() async {
    final missingIds = state
        .where((item) => !_fileExists(item.localPath))
        .map((item) => item.id)
        .toList();
    if (missingIds.isEmpty) {
      return 0;
    }
    state = state.where((item) => !missingIds.contains(item.id)).toList();
    _updateMissingCount();
    await _configService.saveVideoGallery(state);
    return missingIds.length;
  }

  Future<bool> toggleFavorite(String id) async {
    bool current = false;
    state = [
      for (final item in state)
        if (item.id == id)
          item.copyWith(
            isFavorite: !item.isFavorite,
            favoritedAt: !item.isFavorite ? DateTime.now() : null,
          )
        else
          item,
    ];
    for (final item in state) {
      if (item.id == id) {
        current = item.isFavorite;
        break;
      }
    }
    await _configService.saveVideoGallery(state);
    return current;
  }

  Future<void> _repairThumbnails() async {
    var changed = false;
    final repaired = <VideoItem>[];
    for (final item in state) {
      final next = await _ensureThumbnail(item);
      repaired.add(next);
      if (next.thumbnailPath != item.thumbnailPath) {
        changed = true;
      }
    }
    if (changed) {
      state = repaired;
      await _configService.saveVideoGallery(state);
    }
  }

  Future<VideoItem> _ensureThumbnail(VideoItem item) async {
    if (!_fileExists(item.localPath)) {
      if (item.thumbnailPath != null && !_fileExists(item.thumbnailPath!)) {
        return item.copyWith(thumbnailPath: null);
      }
      return item;
    }
    if (item.thumbnailPath != null && _fileExists(item.thumbnailPath!)) {
      return item;
    }
    final generated = await _fileService.generateVideoThumbnail(item.localPath);
    if (generated == null || generated.isEmpty) {
      return item.copyWith(thumbnailPath: null);
    }
    return item.copyWith(thumbnailPath: generated);
  }

  Future<void> _deleteFiles(VideoItem item) async {
    if (_fileExists(item.localPath)) {
      await File(item.localPath).delete();
    }
    if (item.thumbnailPath != null && _fileExists(item.thumbnailPath!)) {
      await File(item.thumbnailPath!).delete();
    }
  }

  bool _fileExists(String path) => File(path).existsSync();

  void _updateMissingCount() {
    _missingCount = state.where((item) => !_fileExists(item.localPath)).length;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gallery_image.dart';
import '../services/file_service.dart';
import 'core_services_provider.dart';

final galleryImagesProvider =
    StateNotifierProvider<GalleryImagesNotifier, List<GalleryImage>>((ref) {
      return GalleryImagesNotifier(ref.read(fileServiceProvider));
    });

class GalleryImagesNotifier extends StateNotifier<List<GalleryImage>> {
  final FileService _service;

  GalleryImagesNotifier(this._service) : super([]) {
    loadImages();
  }

  Future<void> loadImages() async {
    state = await _service.getAllGeneratedImages();
  }

  Future<void> deleteImage(String filename) async {
    await _service.deleteGeneratedImage(filename);
    state = state.where((img) => img.filename != filename).toList();
  }

  void sortByTime(bool ascending) {
    state = [...state]
      ..sort(
        (a, b) => ascending
            ? a.timestamp.compareTo(b.timestamp)
            : b.timestamp.compareTo(a.timestamp),
      );
  }
}

import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../models/uploaded_image.dart';
import '../services/storage_service.dart';
import '../utils/reference_image_file_name.dart';

final storageServiceProvider = Provider((ref) => StorageService());

final uploadedImagesProvider =
    StateNotifierProvider<UploadedImagesNotifier, List<UploadedImage>>((ref) {
      return UploadedImagesNotifier(ref.read(storageServiceProvider));
    });

final selectedImagesProvider =
    StateNotifierProvider<SelectedImagesNotifier, List<UploadedImage>>((ref) {
      return SelectedImagesNotifier(ref.read(storageServiceProvider));
    });

class UploadedImagesNotifier extends StateNotifier<List<UploadedImage>> {
  final StorageService _storage;
  final String Function() _appDirectoryProvider;

  UploadedImagesNotifier(
    this._storage, {
    String Function()? appDirectoryProvider,
  }) : _appDirectoryProvider =
           appDirectoryProvider ??
           (() => File(Platform.resolvedExecutable).parent.path),
       super([]) {
    _loadImages();
  }

  Future<void> _loadImages() async {
    final images = await _storage.loadUploadedImages();
    final validImages = <UploadedImage>[];
    for (final img in images) {
      final file = File(img.path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        validImages.add(
          UploadedImage(
            id: img.id,
            name: img.name,
            path: img.path,
            base64: img.base64,
            bytes: bytes,
          ),
        );
      }
    }
    state = validImages;
  }

  void addImage(UploadedImage image) {
    if (!state.any((img) => img.name == image.name)) {
      state = [...state, image];
      _storage.saveUploadedImages(state);
    }
  }

  void removeImage(String id) {
    final img = state.firstWhere((img) => img.id == id);
    // 只删除 data/input 目录下的副本，不删除其他位置的原始文件
    final file = File(img.path);
    if (file.existsSync() && _isManagedInputPath(img.path)) {
      file.deleteSync();
    }
    state = state.where((img) => img.id != id).toList();
    _storage.saveUploadedImages(state);
  }

  void clearImages() {
    for (var img in state) {
      // 只删除 data/input 目录下的副本
      final file = File(img.path);
      if (file.existsSync() && _isManagedInputPath(img.path)) {
        file.deleteSync();
      }
    }
    state = [];
    _storage.saveUploadedImages(state);
  }

  Future<List<UploadedImage>> uploadImages() async {
    final addedImages = <UploadedImage>[];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );

    if (result != null) {
      final appDir = _appDirectoryProvider();
      final inputDir = Directory('$appDir/data/input');
      await inputDir.create(recursive: true);

      for (var file in result.files) {
        if (file.path != null) {
          final fileBytes = await File(file.path!).readAsBytes();
          final originalFileName = displayFileNameFromPath(file.path!);
          final targetFileName = buildReferenceCopyFileName(
            originalFileName,
            DateTime.now().millisecondsSinceEpoch,
          );
          final targetPath = path.join(inputDir.path, targetFileName);
          await File(targetPath).writeAsBytes(fileBytes);

          final image = UploadedImage(
            id: const Uuid().v4(),
            name: targetFileName,
            path: targetPath,
            base64: base64Encode(fileBytes),
            bytes: fileBytes,
          );
          addImage(image);
          addedImages.add(image);
        }
      }
    }
    return addedImages;
  }

  bool _isManagedInputPath(String imagePath) {
    final normalized = path.normalize(imagePath).toLowerCase();
    final marker =
        '${path.separator}data${path.separator}input${path.separator}';
    return normalized.contains(marker);
  }
}

class SelectedImagesNotifier extends StateNotifier<List<UploadedImage>> {
  final StorageService _storage;

  SelectedImagesNotifier(this._storage) : super([]) {
    _loadImages();
  }

  Future<void> _loadImages() async {
    final images = await _storage.loadSelectedImages();
    final validImages = <UploadedImage>[];
    for (final img in images) {
      final file = File(img.path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        validImages.add(
          UploadedImage(
            id: img.id,
            name: img.name,
            path: img.path,
            base64: img.base64,
            bytes: bytes,
          ),
        );
      }
    }
    state = validImages;
  }

  void addImage(UploadedImage image) {
    if (!state.any((img) => img.name == image.name)) {
      state = [...state, image];
      _storage.saveSelectedImages(state);
    }
  }

  void removeImage(String name) {
    state = state.where((img) => img.name != name).toList();
    _storage.saveSelectedImages(state);
  }

  void clear() {
    state = [];
    _storage.saveSelectedImages(state);
  }
}

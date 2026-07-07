import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:flutter_grsai_video_gen/models/uploaded_image.dart';
import 'package:flutter_grsai_video_gen/providers/image_provider.dart';
import 'package:flutter_grsai_video_gen/services/storage_service.dart';

void main() {
  tearDown(() {
    FilePicker.platform = _FakeFilePicker(null);
  });

  test(
    'uploaded reference image is copied as a selectable managed input',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'reference_upload_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sourceBytes = Uint8List.fromList(base64Decode(_tinyPngBase64));
      final sourceFile = File(path.join(tempDir.path, 'reference.png'));
      await sourceFile.writeAsBytes(sourceBytes);

      FilePicker.platform = _FakeFilePicker(
        FilePickerResult([
          PlatformFile(
            name: 'reference.png',
            path: sourceFile.path,
            size: sourceBytes.length,
          ),
        ]),
      );

      final storage = _MemoryStorageService();
      final notifier = UploadedImagesNotifier(
        storage,
        appDirectoryProvider: () => tempDir.path,
      );
      await Future<void>.delayed(Duration.zero);

      final uploaded = await notifier.uploadImages();

      expect(uploaded, hasLength(1));
      expect(uploaded.single.name, startsWith('ref_'));
      expect(uploaded.single.name, endsWith('_reference.png'));
      expect(uploaded.single.base64, base64Encode(sourceBytes));
      expect(await File(uploaded.single.path).exists(), isTrue);
      expect(
        path.normalize(uploaded.single.path),
        contains(path.normalize('data/input')),
      );
      expect(storage.uploadedImages, hasLength(1));
    },
  );
}

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);

  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    return result;
  }
}

class _MemoryStorageService extends StorageService {
  List<UploadedImage> uploadedImages = [];

  @override
  Future<List<UploadedImage>> loadUploadedImages() async {
    return uploadedImages;
  }

  @override
  Future<void> saveUploadedImages(List<UploadedImage> images) async {
    uploadedImages = List<UploadedImage>.from(images);
  }
}

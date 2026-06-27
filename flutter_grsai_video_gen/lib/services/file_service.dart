import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logger/logger.dart';

import '../models/gallery_image.dart';

class FileService {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  String getAppDirectory() {
    final exePath = Platform.resolvedExecutable;
    return File(exePath).parent.path;
  }

  Future<void> initDirectories() async {
    final appDir = getAppDirectory();
    final dirs = [
      '$appDir/data/input',
      '$appDir/data/output',
      '$appDir/data/output/videos',
      '$appDir/data/output/video_thumbs',
      '$appDir/data/references/video',
      '$appDir/data/Collection',
      '$appDir/data/Session',
      '$appDir/data/Settings',
      '$appDir/data/Skills',
      '$appDir/data/Skills/builtin',
      '$appDir/data/Skills/user',
    ];
    for (final dir in dirs) {
      await Directory(dir).create(recursive: true);
    }
  }

  String getVideoOutputDirectory() => '${getAppDirectory()}/data/output/videos';

  String getVideoThumbnailsDirectory() =>
      '${getAppDirectory()}/data/output/video_thumbs';

  String getVideoReferenceDirectory() =>
      '${getAppDirectory()}/data/references/video';

  String buildImageMetaPath(String imagePath) => '$imagePath.json';

  Future<void> saveImagePromptMetadata(
    String imagePath,
    String prompt, {
    int? timestamp,
  }) async {
    final metaFile = File(buildImageMetaPath(imagePath));
    await metaFile.writeAsString(
      jsonEncode({
        'prompt': prompt,
        'timestamp': timestamp ?? DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  Future<String> readImagePromptMetadata(String imagePath) async {
    final metaFile = File(buildImageMetaPath(imagePath));
    if (!await metaFile.exists()) {
      return '';
    }
    try {
      final raw = await metaFile.readAsString();
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) {
        return data['prompt']?.toString() ?? '';
      }
      if (data is Map) {
        return data['prompt']?.toString() ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<String> saveUploadedImage(String name, String base64Data) async {
    final inputDir = Directory('${getAppDirectory()}/data/input');
    await inputDir.create(recursive: true);

    final filePath = '${inputDir.path}/$name.png';
    final imageData = base64Data.contains(',')
        ? base64Data.split(',')[1]
        : base64Data;
    final bytes = base64Decode(imageData);

    await File(filePath).writeAsBytes(bytes);
    return filePath;
  }

  Future<String> saveVideoReferenceImage(File source) async {
    final dir = Directory(getVideoReferenceDirectory());
    await dir.create(recursive: true);
    final ext = source.path.split('.').last;
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${source.path.hashCode.abs()}.$ext';
    final targetPath = '${dir.path}/$fileName';
    await source.copy(targetPath);
    return targetPath;
  }

  Future<String> saveVideoFile(File source, {String? fileName}) async {
    final outputDir = Directory(getVideoOutputDirectory());
    await outputDir.create(recursive: true);
    final safeName =
        fileName ??
        'video_${DateTime.now().millisecondsSinceEpoch}.${_guessVideoExtension(source.path)}';
    final targetPath = '${outputDir.path}/$safeName';
    await source.copy(targetPath);
    return targetPath;
  }

  Future<String?> downloadVideo(String url, {String? fileName}) async {
    final outputDir = Directory(getVideoOutputDirectory());
    await outputDir.create(recursive: true);
    final lowerUrl = url.toLowerCase();
    final ext = lowerUrl.endsWith('.mov')
        ? 'mov'
        : lowerUrl.endsWith('.webm')
        ? 'webm'
        : lowerUrl.endsWith('.mkv')
        ? 'mkv'
        : 'mp4';
    final finalName =
        fileName ?? 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final targetPath = '${outputDir.path}/$finalName';
    await Dio().download(url, targetPath);
    return targetPath;
  }

  Future<List<File>> getAllGeneratedVideos() async {
    final outputDir = Directory(getVideoOutputDirectory());
    if (!await outputDir.exists()) {
      return [];
    }

    final files = <File>[];
    await for (final entity in outputDir.list(recursive: true)) {
      if (entity is File) {
        final lower = entity.path.toLowerCase();
        if (lower.endsWith('.mp4') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.webm') ||
            lower.endsWith('.mkv')) {
          files.add(entity);
        }
      }
    }

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> deleteGeneratedVideo(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<String?> generateVideoThumbnail(
    String videoPath, {
    bool force = false,
  }) async {
    final videoFile = File(videoPath);
    if (!await videoFile.exists()) {
      return null;
    }

    final thumbsDir = Directory(getVideoThumbnailsDirectory());
    await thumbsDir.create(recursive: true);

    final fileName = videoFile.uri.pathSegments.isNotEmpty
        ? videoFile.uri.pathSegments.last
        : videoFile.path.split(Platform.pathSeparator).last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final safeBaseName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final outputPath =
        '${thumbsDir.path}/${safeBaseName}_${videoFile.lastModifiedSync().millisecondsSinceEpoch}.jpg';
    final outputFile = File(outputPath);
    if (!force && await outputFile.exists()) {
      return outputPath;
    }

    final ffmpeg = _resolveFfmpegExecutable();
    if (ffmpeg == null) {
      _logger.w('未找到 ffmpeg，跳过视频缩略图生成');
      return null;
    }

    try {
      final result = await Process.run(ffmpeg, [
        '-y',
        '-loglevel',
        'error',
        '-ss',
        '00:00:00.500',
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=320:-1',
        outputPath,
      ]);
      if (result.exitCode != 0 || !await outputFile.exists()) {
        _logger.w('视频缩略图生成失败: ${result.stderr}');
        return null;
      }
      return outputPath;
    } catch (e) {
      _logger.w('视频缩略图生成异常: $e');
      return null;
    }
  }

  Future<String> downloadAndSaveImage(
    String url, {
    String? outputFolder,
  }) async {
    final appDir = getAppDirectory();
    final Directory outputDir;

    if (outputFolder != null && outputFolder.isNotEmpty) {
      if (outputFolder.startsWith('/') || outputFolder.contains(':')) {
        outputDir = Directory(outputFolder);
      } else {
        outputDir = Directory('$appDir/$outputFolder');
      }
    } else {
      outputDir = Directory('$appDir/data/output');
    }
    await outputDir.create(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'generated_$timestamp.png';
    final filePath = '${outputDir.path}/$filename';

    await Dio().download(url, filePath);

    if (outputFolder != null &&
        outputFolder.isNotEmpty &&
        outputFolder != 'data/output') {
      final defaultDir = Directory('$appDir/data/output');
      await defaultDir.create(recursive: true);
      await File(filePath).copy('${defaultDir.path}/$filename');
    }

    return 'data/output/$filename';
  }

  Future<void> saveToCollection(String url, String prompt) async {
    final collectionDir = Directory('${getAppDirectory()}/data/Collection');
    await collectionDir.create(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'collection_$timestamp.png';
    final filePath = '${collectionDir.path}/$filename';

    await Dio().download(url, filePath);

    final metaFile = File('${collectionDir.path}/$filename.json');
    await metaFile.writeAsString(
      jsonEncode({'prompt': prompt, 'timestamp': timestamp}),
    );
  }

  Future<List<GalleryImage>> getAllGeneratedImages() async {
    final outputDir = Directory('${getAppDirectory()}/data/output');
    if (!await outputDir.exists()) {
      return [];
    }

    final files = await outputDir.list().where((f) {
      final ext = f.path.toLowerCase();
      return ext.endsWith('.png') ||
          ext.endsWith('.jpg') ||
          ext.endsWith('.jpeg') ||
          ext.endsWith('.webp');
    }).toList();
    final images = <GalleryImage>[];

    for (final file in files) {
      final stat = await file.stat();
      final filename = file.path.split(Platform.pathSeparator).last;
      final prompt = await readImagePromptMetadata(file.path);
      images.add(
        GalleryImage(
          filename: filename,
          path: file.path,
          url: file.path,
          timestamp: stat.modified.millisecondsSinceEpoch,
          prompt: prompt,
        ),
      );
    }

    images.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return images;
  }

  Future<void> deleteGeneratedImage(String filename) async {
    final file = File('${getAppDirectory()}/data/output/$filename');
    if (await file.exists()) {
      await file.delete();
    }
    final metaFile = File(buildImageMetaPath(file.path));
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
  }

  Future<String?> saveImageDialog(String url, String defaultFilename) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存图片',
      fileName: '$defaultFilename.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );

    if (result != null) {
      await Dio().download(url, result);
      return result;
    }
    return null;
  }

  Future<String?> saveImageWithDialog(String sourcePath) async {
    final filename = sourcePath.split(Platform.pathSeparator).last;
    final result = await FilePicker.platform.saveFile(
      dialogTitle: '保存图片',
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );

    if (result != null) {
      await File(sourcePath).copy(result);
      return result;
    }
    return null;
  }

  Future<String?> saveGeneratedFileWithDialog(
    String sourcePath, {
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) async {
    final filename = sourcePath.split(Platform.pathSeparator).last;
    final defaultExtensions = filename.contains('.')
        ? [filename.split('.').last.toLowerCase()]
        : <String>[];
    final result = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: filename,
      type: FileType.custom,
      allowedExtensions: allowedExtensions ?? defaultExtensions,
    );

    if (result != null) {
      await File(sourcePath).copy(result);
      return result;
    }
    return null;
  }

  Future<String?> downloadAllImages(
    List<String> urls,
    String filenameRule,
    String customFilename,
  ) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存文件夹',
    );

    if (result != null) {
      final dio = Dio();
      for (var i = 0; i < urls.length; i++) {
        late String filename;
        if (filenameRule == 'sequence') {
          var seq = i + 1;
          while (true) {
            filename = '$customFilename-$seq.png';
            if (!await File('$result/$filename').exists()) {
              break;
            }
            seq++;
          }
        } else {
          if (i > 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          final now = DateTime.now();
          filename =
              '$customFilename-${now.year}-${now.month}-${now.day}-${now.hour}${now.minute}${now.second}.png';
        }
        await dio.download(urls[i], '$result/$filename');
      }
      return result;
    }
    return null;
  }

  String _guessVideoExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mov')) return 'mov';
    if (lower.endsWith('.webm')) return 'webm';
    if (lower.endsWith('.mkv')) return 'mkv';
    return 'mp4';
  }

  String? _resolveFfmpegExecutable() {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    final candidates = [
      '$executableDir/ffmpeg/bin/ffmpeg.exe',
      '$currentDir/ffmpeg/bin/ffmpeg.exe',
      r'G:\data\app\LTX2.3\ffmpeg\bin\ffmpeg.exe',
      r'G:\data\ffmpeg\bin\ffmpeg.exe',
      r'D:\app\ffmpeg-8.0\bin\ffmpeg.exe',
      r'D:\app\ffmpeg-8.0\ffmpeg.exe',
      'ffmpeg',
    ];

    for (final candidate in candidates) {
      if (candidate == 'ffmpeg' || File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }
}

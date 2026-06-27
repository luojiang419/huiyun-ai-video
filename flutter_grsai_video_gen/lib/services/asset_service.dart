import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/asset.dart';

class AssetService {
  String getAssetsDir() {
    final exePath = Platform.resolvedExecutable;
    final exeDir = File(exePath).parent.path;
    return path.join(exeDir, 'data', 'assets');
  }

  String _getExeDir() {
    return File(Platform.resolvedExecutable).parent.path;
  }

  Future<File> _getAssetsFile() async {
    final assetsDir = getAssetsDir();
    final file = File(path.join(assetsDir, 'assets.json'));
    if (!await file.exists()) {
      await file.create(recursive: true);
      await file.writeAsString('[]');
    }
    return file;
  }

  Future<String> copyImageToAssets(String sourcePath, String category) async {
    final assetsDir = getAssetsDir();
    final categoryDir = Directory(path.join(assetsDir, category));
    if (!await categoryDir.exists()) {
      await categoryDir.create(recursive: true);
    }
    final extension = path.extension(sourcePath);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final targetPath = path.join(categoryDir.path, fileName);
    await File(sourcePath).copy(targetPath);
    return path.join('data', 'assets', category, fileName);
  }

  /// 将相对路径转为绝对路径
  String _toAbsolutePath(String imagePath) {
    if (path.isAbsolute(imagePath)) return imagePath;
    return path.join(_getExeDir(), imagePath);
  }

  /// 将绝对路径转为相对路径
  String _toRelativePath(String imagePath) {
    final exeDir = _getExeDir();
    if (path.isAbsolute(imagePath) && imagePath.startsWith(exeDir)) {
      return path.relative(imagePath, from: exeDir);
    }
    return imagePath;
  }

  Future<List<Asset>> loadAssets() async {
    try {
      final file = await _getAssetsFile();
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((json) {
        final asset = Asset.fromJson(json);
        // 主图路径转绝对
        final absoluteMainPath = _toAbsolutePath(asset.imagePath);
        // 附加图路径转绝对
        final absoluteImages = asset.images.map((img) {
          return img.copyWith(path: _toAbsolutePath(img.path));
        }).toList();
        return asset.copyWith(
          imagePath: absoluteMainPath,
          images: absoluteImages,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error loading assets: $e');
      return [];
    }
  }

  Future<void> saveAssets(List<Asset> assets) async {
    try {
      final file = await _getAssetsFile();

      final jsonList = assets.map((asset) {
        // 主图路径转相对
        final relativePath = _toRelativePath(asset.imagePath);
        // 附加图路径转相对
        final relativeImages = asset.images.map((img) {
          return img.copyWith(path: _toRelativePath(img.path));
        }).toList();
        return asset.copyWith(
          imagePath: relativePath,
          images: relativeImages,
        ).toJson();
      }).toList();

      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving assets: $e');
      rethrow;
    }
  }

  Future<void> addAsset(Asset asset) async {
    final assets = await loadAssets();
    assets.add(asset);
    await saveAssets(assets);
  }

  Future<void> updateAsset(Asset asset) async {
    final assets = await loadAssets();
    final index = assets.indexWhere((a) => a.id == asset.id);
    if (index != -1) {
      assets[index] = asset;
      await saveAssets(assets);
    }
  }

  Future<void> deleteAsset(String id) async {
    final assets = await loadAssets();
    assets.removeWhere((a) => a.id == id);
    await saveAssets(assets);
  }
}

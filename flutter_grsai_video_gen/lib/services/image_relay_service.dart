import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

class ImageRelayService {
  static const String relayBaseUrl = 'http://115.231.35.105:3444';

  final Dio _dio;
  final Map<String, String> _uploadCache = {};

  ImageRelayService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: relayBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 120),
            ),
          );

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get(
        '/health',
        options: Options(responseType: ResponseType.plain),
      );
      return response.statusCode == 200 &&
          response.data.toString().trim().toLowerCase() == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> uploadImageInputs(List<String> inputs) async {
    final uploadedUrls = <String>[];
    for (final input in inputs) {
      final normalized = input.trim();
      if (normalized.isEmpty) {
        continue;
      }
      uploadedUrls.add(await uploadImageInput(normalized));
    }
    return uploadedUrls;
  }

  Future<String> uploadImageInput(String input, {String? suggestedName}) async {
    if (_isRemoteUrl(input)) {
      return input;
    }

    final cacheKey = _buildCacheKey(input);
    final cachedUrl = _uploadCache[cacheKey];
    if (cachedUrl != null && cachedUrl.isNotEmpty) {
      return cachedUrl;
    }

    final filename = suggestedName ?? _buildFilename(input);
    late final Uint8List bytes;
    late final String mimeType;

    if (input.startsWith('data:')) {
      final commaIndex = input.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('参考图 data URI 格式不正确');
      }
      final header = input.substring(5, commaIndex);
      final semiIndex = header.indexOf(';');
      mimeType = semiIndex > 0 ? header.substring(0, semiIndex) : header;
      bytes = Uint8List.fromList(base64Decode(input.substring(commaIndex + 1)));
    } else {
      final file = File(input);
      if (!await file.exists()) {
        throw Exception('参考图不存在，无法上传到中继服务器: $input');
      }
      bytes = await file.readAsBytes();
      mimeType =
          lookupMimeType(file.path, headerBytes: bytes.take(16).toList()) ??
          'image/png';
    }

    final response = await _dio.post(
      '/upload',
      data: {
        'filename': filename,
        'data': 'data:$mimeType;base64,${base64Encode(bytes)}',
      },
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.json,
      ),
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('中继服务器返回格式不正确');
    }

    final uploadedUrl = data['url']?.toString() ?? '';
    if (uploadedUrl.isEmpty) {
      throw Exception(data['error']?.toString() ?? '中继服务器未返回图片地址');
    }

    _uploadCache[cacheKey] = uploadedUrl;
    return uploadedUrl;
  }

  String _buildCacheKey(String input) {
    if (_isRemoteUrl(input)) {
      return 'remote:$input';
    }
    if (input.startsWith('data:')) {
      return 'data:${input.length}:${input.hashCode}';
    }

    final file = File(input);
    if (file.existsSync()) {
      final stat = file.statSync();
      return 'file:${file.path}:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    }
    return 'raw:$input';
  }

  String _buildFilename(String input) {
    final ext = _resolveExtension(input);
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}${now.millisecond.toString().padLeft(3, '0')}';
    return 'img-$timestamp.$ext';
  }

  String _resolveExtension(String input) {
    final guessedMime = lookupMimeType(input) ?? _mimeTypeFromDataUri(input);
    final ext = guessedMime != null ? extensionFromMime(guessedMime) : null;
    if (ext != null && ext.isNotEmpty) {
      return ext;
    }

    final rawExt = path.extension(input).replaceFirst('.', '').trim();
    if (rawExt.isNotEmpty) {
      return rawExt;
    }
    return 'png';
  }

  String? _mimeTypeFromDataUri(String input) {
    if (!input.startsWith('data:')) {
      return null;
    }
    final commaIndex = input.indexOf(',');
    if (commaIndex <= 5) {
      return null;
    }
    final header = input.substring(5, commaIndex);
    final semiIndex = header.indexOf(';');
    return semiIndex > 0 ? header.substring(0, semiIndex) : header;
  }

  bool _isRemoteUrl(String input) {
    return input.startsWith('http://') || input.startsWith('https://');
  }
}

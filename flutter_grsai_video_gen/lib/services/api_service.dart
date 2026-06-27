import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/io.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import '../models/settings.dart';
import 'image_relay_service.dart';
import '../utils/gpt_image_generation_preset.dart';
import '../utils/z_image_base_generation_preset.dart';

class GenerateProgress {
  final String status;
  final int? progress;
  final List<String>? results;
  final String? error;

  GenerateProgress({
    required this.status,
    this.progress,
    this.results,
    this.error,
  });

  factory GenerateProgress.fromJson(Map<String, dynamic> json) {
    final rawError = json['error']?.toString().trim() ?? '';
    final rawFailureReason = json['failure_reason']?.toString().trim() ?? '';
    final error = rawError.isNotEmpty ? rawError : rawFailureReason;
    return GenerateProgress(
      status: json['status'] ?? 'running',
      progress: json['progress'],
      results: json['results'] != null && json['status'] == 'succeeded'
          ? (json['results'] as List).map((r) => r['url'] as String).toList()
          : null,
      error: error.isEmpty ? null : error,
    );
  }
}

class ApiService {
  late final Dio _dio;
  late final ImageRelayService _imageRelayService;
  static const Set<String> _wan2gpImageModels = {
    'z_image',
    'z_image_base',
    'z_image_control',
    'z_image_control2',
    'z_image_control2_1',
  };

  ApiService() {
    _dio = Dio(
      BaseOptions(
        // 移除连接超时限制，或设置为非常大的值（如 1 小时）
        // 因为生成图片可能需要较长时间排队，特别是高负载时
        connectTimeout: null,
        receiveTimeout: null,
        sendTimeout: null,
      ),
    );

    // 本地软件，忽略 HTTPS 证书校验错误
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );

    _imageRelayService = ImageRelayService();
  }

  Future<String> _downloadAndSaveImage(
    String url, {
    String? outputFolder,
  }) async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final defaultOutputDir = Directory(
        path.join(appDir.path, 'data', 'output'),
      );
      if (!await defaultOutputDir.exists()) {
        await defaultOutputDir.create(recursive: true);
      }

      final timestamp = DateTime.now();
      final filename =
          'generated_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}_${timestamp.millisecond.toString().padLeft(3, '0')}.png';

      // 下载图片字节
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      // 始终保存一份到默认 data/output（供图库查看）
      final defaultFilePath = path.join(defaultOutputDir.path, filename);
      await File(defaultFilePath).writeAsBytes(response.data);

      // 如果设置了自定义输出目录，额外保存一份到该目录
      if (outputFolder != null &&
          outputFolder.isNotEmpty &&
          outputFolder != 'data/output') {
        final Directory customDir;
        if (outputFolder.startsWith('/') || outputFolder.contains(':')) {
          customDir = Directory(outputFolder);
        } else {
          customDir = Directory(path.join(appDir.path, outputFolder));
        }
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        await File(
          path.join(customDir.path, filename),
        ).writeAsBytes(response.data);
      }

      return path.join('data', 'output', filename);
    } on DioException catch (e) {
      throw Exception('网络下载失败: ${e.message}');
    } on FileSystemException catch (e) {
      throw Exception('文件保存失败: ${e.message}');
    } catch (e) {
      throw Exception('未知错误: $e');
    }
  }

  Future<String> _saveBase64Image(
    String base64Data,
    String mimeType, {
    String? outputFolder,
  }) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final defaultOutputDir = Directory(
      path.join(appDir.path, 'data', 'output'),
    );
    if (!await defaultOutputDir.exists()) {
      await defaultOutputDir.create(recursive: true);
    }

    final timestamp = DateTime.now();
    final ext = mimeType.contains('png') ? 'png' : 'jpg';
    final filename =
        'generated_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}_${timestamp.millisecond.toString().padLeft(3, '0')}.$ext';

    final bytes = base64Decode(base64Data);
    final defaultFilePath = path.join(defaultOutputDir.path, filename);
    await File(defaultFilePath).writeAsBytes(bytes);

    if (outputFolder != null &&
        outputFolder.isNotEmpty &&
        outputFolder != 'data/output') {
      final Directory customDir;
      if (outputFolder.startsWith('/') || outputFolder.contains(':')) {
        customDir = Directory(outputFolder);
      } else {
        customDir = Directory(path.join(appDir.path, outputFolder));
      }
      if (!await customDir.exists()) {
        await customDir.create(recursive: true);
      }
      await File(path.join(customDir.path, filename)).writeAsBytes(bytes);
    }

    return path.join('data', 'output', filename);
  }

  bool _isGeminiModel(String model) {
    return model.startsWith('gemini-');
  }

  bool _isGrsaiImageApi(String apiUrl) {
    final lower = apiUrl.toLowerCase();
    return lower.contains('grsai.dakka.com.cn') ||
        lower.contains('grsaiapi.com') ||
        lower.contains('/v1/draw/completions') ||
        lower.contains('/v1/draw/nano-banana') ||
        lower.contains('/v1/api/generate');
  }

  bool _isWan2gpBridgeApi(String apiUrl) {
    final lower = apiUrl.toLowerCase();
    return lower.contains('127.0.0.1:7861') ||
        lower.contains('localhost:7861') ||
        lower.endsWith(':7861');
  }

  bool _isWan2gpImageModel(String model) {
    return _wan2gpImageModels.contains(model.trim());
  }

  static bool _isDeepSeekApi(String apiUrl) {
    final lower = apiUrl.trim().toLowerCase();
    try {
      final host = Uri.parse(lower).host;
      if (host == 'api.deepseek.com' || host.endsWith('.deepseek.com')) {
        return true;
      }
    } catch (_) {
      // Fall back to a text check for partially-entered URLs in settings.
    }
    return lower.contains('api.deepseek.com');
  }

  @visibleForTesting
  static String normalizeOpenAiCompatibleModel({
    required String apiUrl,
    required String model,
  }) {
    final trimmed = model.trim();
    if (!_isDeepSeekApi(apiUrl)) {
      return trimmed;
    }

    final match = RegExp(
      r'^(deepseek-v4-(?:flash|pro))(?:\[(?:1m)\])?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return trimmed;
  }

  bool _shouldDisableDeepSeekThinking(String apiUrl, String model) {
    final normalized = normalizeOpenAiCompatibleModel(
      apiUrl: apiUrl,
      model: model,
    );
    return _isDeepSeekApi(apiUrl) && normalized == 'deepseek-v4-flash';
  }

  String _buildOpenAiChatCompletionsUrl(String apiUrl) {
    final trimmed = apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      return trimmed;
    }
    if (trimmed.endsWith('/v1')) {
      return '$trimmed/chat/completions';
    }
    return '$trimmed/v1/chat/completions';
  }

  String _buildOpenAiModelsUrl(String apiUrl) {
    final trimmed = apiUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      return trimmed.replaceFirst(RegExp(r'/chat/completions$'), '/models');
    }
    if (trimmed.endsWith('/v1')) {
      return '$trimmed/models';
    }
    return '$trimmed/v1/models';
  }

  Map<String, dynamic> _buildOpenAiChatRequestBody({
    required String apiUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    bool stream = false,
    bool jsonObjectResponse = false,
  }) {
    final requestModel = normalizeOpenAiCompatibleModel(
      apiUrl: apiUrl,
      model: model,
    );
    final body = <String, dynamic>{'model': requestModel, 'messages': messages};
    if (stream) {
      body['stream'] = true;
    }
    if (jsonObjectResponse) {
      body['response_format'] = {'type': 'json_object'};
    }
    if (_shouldDisableDeepSeekThinking(apiUrl, requestModel)) {
      body['thinking'] = {'type': 'disabled'};
    }
    return body;
  }

  String _resolveGptImageSize(
    String model,
    String aspectRatio,
    String imageSize,
  ) {
    return GptImageGenerationPreset.resolveOpenAiSize(
      model: model,
      aspectRatio: aspectRatio,
      imageSize: imageSize,
      legacyResolver: _resolveWan2gpImageResolution,
    );
  }

  String _resolveApiOrigin(String apiUrl) {
    final uri = Uri.parse(apiUrl.trim());
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Uri _buildGrsaiUnifiedApiUri(String apiUrl, String pathSuffix) {
    return Uri.parse('${_resolveApiOrigin(apiUrl)}$pathSuffix');
  }

  String _mimeTypeToExtension(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('jpeg') || normalized.contains('jpg')) {
      return 'jpg';
    }
    if (normalized.contains('webp')) {
      return 'webp';
    }
    if (normalized.contains('gif')) {
      return 'gif';
    }
    return 'png';
  }

  String _inferMimeTypeFromInput(String input) {
    if (input.startsWith('data:')) {
      final commaIndex = input.indexOf(',');
      if (commaIndex > 5) {
        final header = input.substring(5, commaIndex);
        final semiIndex = header.indexOf(';');
        if (semiIndex > 0) {
          return header.substring(0, semiIndex);
        }
        if (header.isNotEmpty) {
          return header;
        }
      }
    }

    final lowerPath = input.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerPath.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lowerPath.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/png';
  }

  Future<List<int>> _readImageBytesFromInput(String input) async {
    if (input.startsWith('data:')) {
      final commaIndex = input.indexOf(',');
      if (commaIndex == -1) {
        throw Exception('参考图 data URI 格式不正确');
      }
      return base64Decode(input.substring(commaIndex + 1));
    }

    if (input.startsWith('http://') || input.startsWith('https://')) {
      final response = await _dio.get<List<int>>(
        input,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw Exception('参考图下载失败：未返回图片字节');
      }
      return data;
    }

    final file = File(input);
    if (!await file.exists()) {
      throw Exception('参考图不存在: $input');
    }
    return file.readAsBytes();
  }

  Future<MultipartFile> _buildGptImageMultipartFile(
    String input,
    int index,
  ) async {
    final mimeType = _inferMimeTypeFromInput(input);
    final ext = _mimeTypeToExtension(mimeType);
    final bytes = await _readImageBytesFromInput(input);
    return MultipartFile.fromBytes(
      bytes,
      filename: 'reference_${index + 1}.$ext',
    );
  }

  bool _shouldRelayReferenceImages(String apiUrl, String model) {
    if (_isGeminiModel(model) || _isWan2gpImageModel(model)) {
      return false;
    }
    if (GptImageGenerationPreset.isModel(model) && !_isGrsaiImageApi(apiUrl)) {
      return false;
    }
    return true;
  }

  Future<String> _convertInputToDataUri(String input) async {
    if (input.startsWith('data:')) {
      return input;
    }
    final bytes = await _readImageBytesFromInput(input);
    final mimeType = _inferMimeTypeFromInput(input);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<List<String>> _prepareGeminiReferenceInputs(
    List<String> inputs,
  ) async {
    final prepared = <String>[];
    for (final input in inputs) {
      prepared.add(await _convertInputToDataUri(input));
    }
    return prepared;
  }

  Future<List<String>> _prepareBase64ReferenceInputs(
    List<String> inputs,
  ) async {
    final prepared = <String>[];
    for (final input in inputs) {
      if (input.startsWith('http://') || input.startsWith('https://')) {
        prepared.add(input);
        continue;
      }
      prepared.add(await _convertInputToDataUri(input));
    }
    return prepared;
  }

  Future<List<String>> _normalizeReferenceInputsForApi({
    required String apiUrl,
    required String model,
    required List<String> urls,
    String uploadMethod = Settings.uploadMethodRelayUrl,
  }) async {
    final normalized = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (normalized.isEmpty) {
      return const [];
    }

    if (_isGeminiModel(model)) {
      return _prepareGeminiReferenceInputs(normalized);
    }

    if (_shouldRelayReferenceImages(apiUrl, model)) {
      if (uploadMethod == Settings.uploadMethodBase64) {
        return _prepareBase64ReferenceInputs(normalized);
      }
      return _imageRelayService.uploadImageInputs(normalized);
    }

    return normalized;
  }

  Future<String> _compressImageInputForGrsai(String input) async {
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return input;
    }

    final bytes = await _readImageBytesFromInput(input);
    final decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) {
      return input;
    }

    img.Image current = decoded;
    if (current.width > 1536 || current.height > 1536) {
      if (current.width >= current.height) {
        current = img.copyResize(current, width: 1536);
      } else {
        current = img.copyResize(current, height: 1536);
      }
    }

    int quality = 82;
    List<int> encoded = img.encodeJpg(current, quality: quality);
    while (encoded.length > 900 * 1024 && quality > 45) {
      quality -= 10;
      encoded = img.encodeJpg(current, quality: quality);
    }

    if (encoded.length > 900 * 1024 &&
        (current.width > 1024 || current.height > 1024)) {
      if (current.width >= current.height) {
        current = img.copyResize(current, width: 1024);
      } else {
        current = img.copyResize(current, height: 1024);
      }
      quality = 72;
      encoded = img.encodeJpg(current, quality: quality);
      while (encoded.length > 900 * 1024 && quality > 40) {
        quality -= 8;
        encoded = img.encodeJpg(current, quality: quality);
      }
    }

    return 'data:image/jpeg;base64,${base64Encode(encoded)}';
  }

  Future<List<String>> _prepareGrsaiUnifiedImages(List<String> inputs) async {
    final prepared = <String>[];
    for (final input in inputs) {
      final normalized = input.trim();
      if (normalized.isEmpty) {
        continue;
      }
      prepared.add(await _compressImageInputForGrsai(normalized));
    }
    return prepared;
  }

  String _extractErrorMessage(dynamic data, String fallback) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }

      final detail = data['error_detail'] ?? data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }

      final message = data['message'] ?? data['msg'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }

      final nestedData = data['data'];
      if (nestedData is Map) {
        final nested = _extractErrorMessage(nestedData, '');
        if (nested.trim().isNotEmpty) {
          return nested;
        }
      }

      final failureReason = data['failure_reason'];
      if (failureReason is String && failureReason.trim().isNotEmpty) {
        return failureReason.trim();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return fallback;
  }

  Future<String> _saveOpenAiImageResponse(
    dynamic data, {
    String? outputFolder,
  }) async {
    if (data is! Map ||
        data['data'] is! List ||
        (data['data'] as List).isEmpty) {
      throw Exception('GPT Image API 未返回图片数据');
    }

    final first = (data['data'] as List).first;
    if (first is! Map) {
      throw Exception('GPT Image API 返回格式不正确');
    }

    final b64Json = first['b64_json']?.toString() ?? '';
    if (b64Json.isNotEmpty) {
      final outputFormat = first['output_format']?.toString() ?? 'png';
      final mimeType = outputFormat == 'jpeg'
          ? 'image/jpeg'
          : outputFormat == 'webp'
          ? 'image/webp'
          : 'image/png';
      return _saveBase64Image(b64Json, mimeType, outputFolder: outputFolder);
    }

    final url = first['url']?.toString() ?? '';
    if (url.isNotEmpty) {
      return _downloadAndSaveImage(url, outputFolder: outputFolder);
    }

    throw Exception('GPT Image API 未返回 b64_json 或 url');
  }

  Stream<GenerateProgress> _generateViaOpenAiCompatibleGptImage({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
    required List<String> urls,
    String? outputFolder,
  }) async* {
    final normalizedBase = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    final size = _resolveGptImageSize(model, aspectRatio, imageSize);
    final quality = GptImageGenerationPreset.supportsQuality(model)
        ? GptImageGenerationPreset.normalizeQuality(imageQuality)
        : '';
    final hasReferenceImages = urls.isNotEmpty;
    final endpoint = hasReferenceImages
        ? '$normalizedBase/v1/images/edits'
        : '$normalizedBase/v1/images/generations';

    try {
      late final Response response;
      if (hasReferenceImages) {
        final formData = FormData();
        formData.fields.add(MapEntry('model', model));
        formData.fields.add(MapEntry('prompt', prompt));
        if (size.isNotEmpty) {
          formData.fields.add(MapEntry('size', size));
        }
        if (quality.isNotEmpty) {
          formData.fields.add(MapEntry('quality', quality));
        }
        for (int i = 0; i < urls.length; i++) {
          formData.files.add(
            MapEntry('image[]', await _buildGptImageMultipartFile(urls[i], i)),
          );
        }

        response = await _dio.post(
          endpoint,
          options: Options(
            headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
            responseType: ResponseType.json,
          ),
          data: formData,
        );
      } else {
        response = await _dio.post(
          endpoint,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            responseType: ResponseType.json,
          ),
          data: {
            'model': model,
            'prompt': prompt,
            if (size.isNotEmpty) 'size': size,
            if (quality.isNotEmpty) 'quality': quality,
          },
        );
      }

      final localPath = await _saveOpenAiImageResponse(
        response.data,
        outputFolder: outputFolder,
      );
      await _writeImagePromptMeta(localPath, prompt);
      yield GenerateProgress(
        status: 'succeeded',
        progress: 100,
        results: [localPath],
      );
    } on DioException catch (e) {
      final errorMsg = _extractErrorMessage(
        e.response?.data,
        e.message ?? '网络请求失败',
      );
      yield GenerateProgress(status: 'failed', error: errorMsg);
    } catch (e) {
      yield GenerateProgress(status: 'failed', error: e.toString());
    }
  }

  List<String> _extractResultUrls(dynamic data) {
    if (data is! Map || data['results'] is! List) {
      return const [];
    }

    return (data['results'] as List)
        .whereType<Map>()
        .map((item) => item['url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  Stream<GenerateProgress> _generateViaGrsaiUnifiedImageApi({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
    required List<String> urls,
    String? outputFolder,
  }) async* {
    final generateUri = _buildGrsaiUnifiedApiUri(apiUrl, '/v1/api/generate');
    final resultUri = _buildGrsaiUnifiedApiUri(apiUrl, '/v1/api/result');

    final preparedImages = await _prepareGrsaiUnifiedImages(urls);
    final Map<String, dynamic> body = {
      'model': model,
      'prompt': prompt,
      'urls': preparedImages,
      'replyType': 'json',
    };

    if (GptImageGenerationPreset.isModel(model)) {
      body['aspectRatio'] = _resolveGptImageSize(model, aspectRatio, imageSize);
      if (GptImageGenerationPreset.supportsQuality(model)) {
        body['quality'] = GptImageGenerationPreset.normalizeQuality(
          imageQuality,
        );
      }
    } else {
      body['aspectRatio'] = aspectRatio;
      body['imageSize'] = imageSize;
    }

    try {
      final submitResponse = await _dio.postUri(
        generateUri,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          responseType: ResponseType.json,
        ),
        data: body,
      );

      Map<String, dynamic> responseData = Map<String, dynamic>.from(
        submitResponse.data as Map,
      );

      while (true) {
        final status = responseData['status']?.toString() ?? '';
        final resultUrls = _extractResultUrls(responseData);

        if (status == 'succeeded' && resultUrls.isNotEmpty) {
          final localPaths = <String>[];
          for (final url in resultUrls) {
            final localPath = await _downloadAndSaveImage(
              url,
              outputFolder: outputFolder,
            );
            await _writeImagePromptMeta(localPath, prompt);
            localPaths.add(localPath);
          }
          yield GenerateProgress(
            status: 'succeeded',
            progress: 100,
            results: localPaths,
          );
          return;
        }

        if (status == 'failed') {
          yield GenerateProgress(
            status: 'failed',
            error: _extractErrorMessage(responseData, 'Grsai 统一图片接口生成失败'),
          );
          return;
        }

        final taskId = responseData['id']?.toString() ?? '';
        if (taskId.isEmpty) {
          yield GenerateProgress(
            status: 'failed',
            error: _extractErrorMessage(responseData, 'Grsai 统一图片接口未返回任务ID'),
          );
          return;
        }

        yield GenerateProgress(
          status: status.isEmpty ? 'running' : status,
          progress: null,
        );

        await Future<void>.delayed(const Duration(seconds: 1));
        final resultResponse = await _dio.getUri(
          resultUri.replace(queryParameters: {'id': taskId}),
          options: Options(
            headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
            responseType: ResponseType.json,
          ),
        );
        responseData = Map<String, dynamic>.from(resultResponse.data as Map);
      }
    } on DioException catch (e) {
      final errorMsg = _extractErrorMessage(
        e.response?.data,
        e.message ?? '网络请求失败',
      );
      yield GenerateProgress(status: 'failed', error: errorMsg);
    } catch (e) {
      yield GenerateProgress(status: 'failed', error: e.toString());
    }
  }

  Stream<GenerateProgress> _generateViaStreamingDrawApi({
    required String endpoint,
    required String apiKey,
    required Map<String, dynamic> body,
    required String prompt,
    String? outputFolder,
  }) async* {
    final response = await _dio.post(
      endpoint,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiKey.trim()}',
        },
        responseType: ResponseType.stream,
      ),
      data: body,
    );

    final responseStream = response.data as ResponseBody;
    GenerateProgress? lastProgress;

    Stream<String> stream;
    try {
      stream = responseStream.stream.map((bytes) => utf8.decode(bytes));
    } catch (e) {
      yield GenerateProgress(status: 'failed', error: '流解析初始化失败: $e');
      return;
    }

    await for (var chunk in stream) {
      final lines = chunk.split('\n');
      for (var line in lines) {
        if (line.startsWith('data: ')) {
          try {
            final data = jsonDecode(line.substring(6));
            lastProgress = GenerateProgress.fromJson(data);

            if (lastProgress.status == 'failed') {
              yield lastProgress;
              return;
            }

            if (lastProgress.status != 'succeeded') {
              yield lastProgress;
            }
          } catch (e) {
            debugPrint('JSON解析错误: $e, Line: $line');
            yield GenerateProgress(status: 'failed', error: '数据解析异常: $e');
            return;
          }
        }
      }
    }

    if (lastProgress != null &&
        lastProgress.status == 'succeeded' &&
        lastProgress.results != null) {
      final localPaths = <String>[];
      for (final url in lastProgress.results!) {
        final localPath = await _downloadAndSaveImage(
          url,
          outputFolder: outputFolder,
        );
        await _writeImagePromptMeta(localPath, prompt);
        localPaths.add(localPath);
      }
      yield GenerateProgress(
        status: 'succeeded',
        progress: 100,
        results: localPaths,
        error: null,
      );
      return;
    }

    if (lastProgress != null && lastProgress.status == 'failed') {
      yield lastProgress;
      return;
    }

    yield GenerateProgress(status: 'failed', error: '生成服务未返回有效结果');
  }

  Future<bool> _checkWan2gpImageModelStatus(
    String apiUrl,
    String modelName,
  ) async {
    try {
      final response = await _dio.getUri(
        _resolveBridgeUri(apiUrl, '/api/models'),
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is Map && data['models'] is List) {
        return (data['models'] as List).any(
          (item) => item is Map && item['id']?.toString() == modelName,
        );
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<List<String>> _fetchWan2gpImageModels(String apiUrl) async {
    try {
      final response = await _dio.getUri(
        _resolveBridgeUri(apiUrl, '/api/models'),
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is Map && data['models'] is List) {
        return (data['models'] as List)
            .whereType<Map>()
            .where((item) => item['type']?.toString() == 'image')
            .map((item) => item['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  String _resolveWan2gpImageResolution(String aspectRatio, String imageSize) {
    final size = imageSize.toUpperCase();
    final ratio = aspectRatio.toLowerCase();
    if (ratio == '16:9') {
      return size == '4K'
          ? '3840x2160'
          : size == '2K'
          ? '2048x1152'
          : '1536x864';
    }
    if (ratio == '9:16') {
      return size == '4K'
          ? '2160x3840'
          : size == '2K'
          ? '1152x2048'
          : '864x1536';
    }
    if (ratio == '5:4') {
      return size == '4K'
          ? '2560x2048'
          : size == '2K'
          ? '1920x1536'
          : '1280x1024';
    }
    if (ratio == '4:5') {
      return size == '4K'
          ? '2048x2560'
          : size == '2K'
          ? '1536x1920'
          : '1024x1280';
    }
    if (ratio == '4:3') {
      return size == '4K'
          ? '3072x2304'
          : size == '2K'
          ? '1536x1152'
          : '1152x864';
    }
    if (ratio == '3:4') {
      return size == '4K'
          ? '2304x3072'
          : size == '2K'
          ? '1152x1536'
          : '864x1152';
    }
    if (ratio == '21:9') {
      return size == '4K'
          ? '3360x1440'
          : size == '2K'
          ? '2688x1152'
          : '1344x576';
    }
    if (ratio == '9:21') {
      return size == '4K'
          ? '1440x3360'
          : size == '2K'
          ? '1152x2688'
          : '576x1344';
    }
    if (ratio == '3:2') {
      return size == '4K'
          ? '3072x2048'
          : size == '2K'
          ? '1536x1024'
          : '1216x832';
    }
    if (ratio == '2:3') {
      return size == '4K'
          ? '2048x3072'
          : size == '2K'
          ? '1024x1536'
          : '832x1216';
    }
    if (ratio == '3:1') {
      return size == '4K'
          ? '3744x1248'
          : size == '2K'
          ? '2304x768'
          : '1536x512';
    }
    if (ratio == '1:3') {
      return size == '4K'
          ? '1248x3744'
          : size == '2K'
          ? '768x2304'
          : '512x1536';
    }
    if (ratio == '2:1') {
      return size == '4K'
          ? '3072x1536'
          : size == '2K'
          ? '2048x1024'
          : '1536x768';
    }
    if (ratio == '1:2') {
      return size == '4K'
          ? '1536x3072'
          : size == '2K'
          ? '1024x2048'
          : '768x1536';
    }
    return size == '4K'
        ? '2880x2880'
        : size == '2K'
        ? '2048x2048'
        : '1024x1024';
  }

  Uri _resolveBridgeUri(String apiUrl, String pathSuffix) {
    final normalized = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    return Uri.parse('$normalized$pathSuffix');
  }

  Stream<GenerateProgress> _generateViaWan2gpImageBridge({
    required String apiUrl,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    int? sampleSteps,
    String? outputFolder,
  }) async* {
    final submitUri = _resolveBridgeUri(apiUrl, '/api/generate/image');
    final isZImageBase = ZImageBaseGenerationPreset.isModel(model);
    final resolution = isZImageBase
        ? ZImageBaseGenerationPreset.resolveResolution(aspectRatio, imageSize)
        : _resolveWan2gpImageResolution(aspectRatio, imageSize);
    final resolvedSampleSteps = isZImageBase
        ? ZImageBaseGenerationPreset.normalizeSampleSteps(
            sampleSteps,
            imageSize: imageSize,
          )
        : imageSize.toUpperCase() == '4K'
        ? 40
        : imageSize.toUpperCase() == '2K'
        ? 35
        : 30;
    final submitResponse = await _dio.postUri(
      submitUri,
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.json,
      ),
      data: {
        'prompt': prompt,
        'negative_prompt': '',
        'resolution': resolution,
        'sample_steps': resolvedSampleSteps,
        'guide_scale': isZImageBase
            ? ZImageBaseGenerationPreset.guidanceScale
            : 4.0,
        'shift_scale': isZImageBase
            ? ZImageBaseGenerationPreset.flowShift
            : 6.0,
        'seed': -1,
        'sample_solver': 'unified_2s',
        'task_type': 'image',
        'model_name': model,
        'batch_size': 1,
      },
    );

    final submitData = Map<String, dynamic>.from(submitResponse.data as Map);
    final taskId = submitData['task_id']?.toString() ?? '';
    if (taskId.isEmpty) {
      yield GenerateProgress(status: 'failed', error: '本地Wan2GP未返回任务ID');
      return;
    }

    final statusUri = _resolveBridgeUri(apiUrl, '/api/task/$taskId/status');
    final resultUri = _resolveBridgeUri(apiUrl, '/api/task/$taskId/result');

    while (true) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final statusResponse = await _dio.getUri(
        statusUri,
        options: Options(responseType: ResponseType.json),
      );
      final statusData = Map<String, dynamic>.from(statusResponse.data as Map);
      final status = statusData['status']?.toString() ?? 'queued';
      final progress = statusData['progress'] is Map<String, dynamic>
          ? statusData['progress'] as Map<String, dynamic>
          : statusData['progress'] is Map
          ? Map<String, dynamic>.from(statusData['progress'] as Map)
          : <String, dynamic>{};
      final percentage = (progress['percentage'] as num?)?.toInt() ?? 0;

      if (status == 'queued' || status == 'running') {
        yield GenerateProgress(status: status, progress: percentage);
        continue;
      }

      if (status == 'failed' || status == 'cancelled') {
        try {
          final resultResponse = await _dio.getUri(
            resultUri,
            options: Options(responseType: ResponseType.json),
          );
          final resultData = Map<String, dynamic>.from(
            resultResponse.data as Map,
          );
          yield GenerateProgress(
            status: 'failed',
            error: resultData['error']?.toString() ?? '本地Wan2GP生成失败',
          );
        } catch (_) {
          yield GenerateProgress(status: 'failed', error: '本地Wan2GP生成失败');
        }
        return;
      }

      if (status == 'completed') {
        final resultResponse = await _dio.getUri(
          resultUri,
          options: Options(responseType: ResponseType.json),
        );
        final resultData = Map<String, dynamic>.from(
          resultResponse.data as Map,
        );
        final imageUrl = resultData['image_url']?.toString() ?? '';
        if (imageUrl.isEmpty) {
          yield GenerateProgress(status: 'failed', error: '本地Wan2GP未返回图片地址');
          return;
        }
        final absoluteImageUrl = imageUrl.startsWith('http')
            ? imageUrl
            : _resolveBridgeUri(apiUrl, imageUrl).toString();
        final localPath = await _downloadAndSaveImage(
          absoluteImageUrl,
          outputFolder: outputFolder,
        );
        await _writeImagePromptMeta(localPath, prompt);
        yield GenerateProgress(
          status: 'succeeded',
          progress: 100,
          results: [localPath],
        );
        return;
      }
    }
  }

  Future<void> _writeImagePromptMeta(String imagePath, String prompt) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final absolutePath = path.isAbsolute(imagePath)
        ? imagePath
        : path.join(appDir.path, imagePath);
    final metaFile = File('$absolutePath.json');
    await metaFile.writeAsString(
      jsonEncode({
        'prompt': prompt,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  Stream<GenerateProgress> generateImage({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required String imageSize,
    String imageQuality = 'auto',
    int? sampleSteps,
    List<String> urls = const [],
    String uploadMethod = Settings.uploadMethodRelayUrl,
    String? outputFolder,
  }) async* {
    // z_image_* 模型始终通过 Wan2GP bridge 提交，避免被固定端口限制。
    if (_isWan2gpImageModel(model)) {
      yield* _generateViaWan2gpImageBridge(
        apiUrl: apiUrl,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageSize: imageSize,
        sampleSteps: sampleSteps,
        outputFolder: outputFolder,
      );
      return;
    }

    final normalizedUrls = await _normalizeReferenceInputsForApi(
      apiUrl: apiUrl,
      model: model,
      urls: urls,
      uploadMethod: uploadMethod,
    );

    Map<String, dynamic> body;
    String endpoint;

    // Gemini API 通道（诗影代理）
    if (_isGeminiModel(model)) {
      endpoint = apiUrl.endsWith('/')
          ? '${apiUrl}v1beta/models/$model:generateContent'
          : '$apiUrl/v1beta/models/$model:generateContent';

      final parts = <Map<String, dynamic>>[
        {'text': prompt},
      ];
      for (final url in normalizedUrls) {
        if (url.startsWith('data:')) {
          final commaIdx = url.indexOf(',');
          if (commaIdx != -1) {
            final header = url.substring(5, commaIdx);
            final base64Data = url.substring(commaIdx + 1);
            final mimeMatch = RegExp(r'([^;]+)').firstMatch(header);
            parts.add({
              'inline_data': {
                'mime_type': mimeMatch?.group(1) ?? 'image/png',
                'data': base64Data,
              },
            });
          }
        }
      }

      body = {
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
          'imageConfig': {
            'aspectRatio': aspectRatio == 'auto' ? '1:1' : aspectRatio,
            'imageSize': imageSize,
          },
        },
      };

      try {
        final response = await _dio.post(
          endpoint,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            responseType: ResponseType.json,
          ),
          data: body,
        );

        final data = response.data;
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          yield GenerateProgress(status: 'failed', error: 'Gemini API 未返回有效结果');
          return;
        }

        final responseParts = candidates[0]['content']?['parts'] as List?;
        if (responseParts == null || responseParts.isEmpty) {
          yield GenerateProgress(status: 'failed', error: 'Gemini API 返回内容为空');
          return;
        }

        final localPaths = <String>[];
        for (final part in responseParts) {
          final inlineData = part['inlineData'] ?? part['inline_data'];
          if (inlineData != null) {
            final base64Data = inlineData['data'] as String? ?? '';
            final mimeType =
                inlineData['mimeType'] as String? ??
                inlineData['mime_type'] as String? ??
                'image/png';
            if (base64Data.isNotEmpty) {
              final localPath = await _saveBase64Image(
                base64Data,
                mimeType,
                outputFolder: outputFolder,
              );
              await _writeImagePromptMeta(localPath, prompt);
              localPaths.add(localPath);
            }
          }
        }

        if (localPaths.isEmpty) {
          yield GenerateProgress(status: 'failed', error: 'Gemini API 未返回图片数据');
          return;
        }

        yield GenerateProgress(
          status: 'succeeded',
          progress: 100,
          results: localPaths,
        );
      } on DioException catch (e) {
        String errorMsg = e.message ?? '网络请求失败';
        if (e.response?.data != null) {
          try {
            final errData = e.response!.data;
            if (errData is Map && errData['error'] != null) {
              errorMsg = errData['error']['message'] ?? errorMsg;
            }
          } catch (_) {}
        }
        yield GenerateProgress(status: 'failed', error: errorMsg);
      } catch (e) {
        yield GenerateProgress(status: 'failed', error: e.toString());
      }
      return;
    }

    if (GptImageGenerationPreset.isModel(model)) {
      if (_isGrsaiImageApi(apiUrl)) {
        yield* _generateViaGrsaiUnifiedImageApi(
          apiUrl: apiUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          aspectRatio: aspectRatio,
          imageSize: imageSize,
          imageQuality: imageQuality,
          urls: normalizedUrls,
          outputFolder: outputFolder,
        );
        return;
      }

      yield* _generateViaOpenAiCompatibleGptImage(
        apiUrl: apiUrl,
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageSize: imageSize,
        imageQuality: imageQuality,
        urls: normalizedUrls,
        outputFolder: outputFolder,
      );
      return;
    } else {
      if (_isGrsaiImageApi(apiUrl)) {
        yield* _generateViaGrsaiUnifiedImageApi(
          apiUrl: apiUrl,
          apiKey: apiKey,
          model: model,
          prompt: prompt,
          aspectRatio: aspectRatio,
          imageSize: imageSize,
          imageQuality: imageQuality,
          urls: normalizedUrls,
          outputFolder: outputFolder,
        );
        return;
      }

      endpoint = apiUrl.contains('/v1/draw/nano-banana')
          ? apiUrl
          : (apiUrl.endsWith('/')
                ? '${apiUrl}v1/draw/nano-banana'
                : '$apiUrl/v1/draw/nano-banana');
      body = {
        'model': model,
        if (normalizedUrls.isNotEmpty) 'urls': normalizedUrls,
        'prompt': prompt,
        'aspectRatio': aspectRatio,
        'imageSize': imageSize,
      };
    }

    yield* _generateViaStreamingDrawApi(
      endpoint: endpoint,
      apiKey: apiKey,
      body: body,
      prompt: prompt,
      outputFolder: outputFolder,
    );
  }

  Future<String> chat({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
    bool jsonObjectResponse = false,
  }) async {
    final isClaude = apiUrl.contains('claudecode') || model.contains('claude');

    if (isClaude) {
      // 对 Claude 使用流式方式收集结果，以避免某些代理服务器对非流式长请求的 502 超时限制
      final buffer = StringBuffer();
      try {
        final stream = chatStream(
          apiUrl: apiUrl,
          apiKey: apiKey,
          model: model,
          messages: messages,
          systemPrompt: systemPrompt,
        );

        await for (final chunk in stream) {
          buffer.write(chunk);
        }

        final result = buffer.toString();
        if (result.isEmpty) {
          throw Exception('AI 返回内容为空，请检查网络或 API 状态');
        }
        return result;
      } catch (e) {
        if (e is DioException) {
          rethrow;
        }
        throw Exception('Claude 请求失败: $e');
      }
    } else {
      final url = _buildOpenAiChatCompletionsUrl(apiUrl);
      final requestMessages = <Map<String, dynamic>>[
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        ...messages.map(
          (message) => <String, dynamic>{
            'role': message['role'],
            'content': message['content'],
          },
        ),
      ];

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
        ),
        data: _buildOpenAiChatRequestBody(
          apiUrl: apiUrl,
          model: model,
          messages: requestMessages,
          jsonObjectResponse: jsonObjectResponse,
        ),
      );

      return response.data['choices'][0]['message']['content'] as String;
    }
  }

  /// Chat with image(s) support - sends base64 images to vision-capable models
  Future<String> chatWithImages({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String textPrompt,
    required List<String> imageBase64List,
    String? systemPrompt,
  }) async {
    final isClaude = apiUrl.contains('claudecode') || model.contains('claude');

    // Build content array: text + images
    final contentParts = <Map<String, dynamic>>[
      {'type': 'text', 'text': textPrompt},
    ];

    for (final base64 in imageBase64List) {
      // detect format
      String mediaType = 'image/png';
      if (base64.startsWith('/9j/')) {
        mediaType = 'image/jpeg';
      } else if (base64.startsWith('UklGR')) {
        mediaType = 'image/webp';
      }
      contentParts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:$mediaType;base64,$base64'},
      });
    }

    if (isClaude) {
      final url = apiUrl.endsWith('/v1/messages')
          ? apiUrl
          : (apiUrl.endsWith('/')
                ? '${apiUrl}v1/messages'
                : '$apiUrl/v1/messages');

      // Claude uses content blocks array format
      final claudeContent = <Map<String, dynamic>>[];
      for (final base64 in imageBase64List) {
        String mediaType = 'image/png';
        if (base64.startsWith('/9j/')) {
          mediaType = 'image/jpeg';
        } else if (base64.startsWith('UklGR')) {
          mediaType = 'image/webp';
        }
        claudeContent.add({
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': base64},
        });
      }
      claudeContent.add({'type': 'text', 'text': textPrompt});

      final requestData = <String, dynamic>{
        'model': model,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': claudeContent},
        ],
      };
      if (systemPrompt != null) {
        requestData['system'] = systemPrompt;
      }

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
        ),
        data: requestData,
      );

      final content = response.data['content'] as List;
      return content
          .whereType<Map<String, dynamic>>()
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] as String)
          .join();
    } else {
      final url = _buildOpenAiChatCompletionsUrl(apiUrl);
      final requestMessages = <Map<String, dynamic>>[
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': contentParts},
      ];

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
        ),
        data: _buildOpenAiChatRequestBody(
          apiUrl: apiUrl,
          model: model,
          messages: requestMessages,
        ),
      );

      return response.data['choices'][0]['message']['content'] as String;
    }
  }

  Future<List<String>> polishPromptBatch({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String originalPrompt,
    required int count,
  }) async {
    final systemPrompt =
        '你是一个专业的AI绘画提示词优化专家。用户会给你一个原始提示词，你需要生成$count个不同的优化版本。每个版本都要保持原意，但在细节、角度、氛围等方面有所不同。直接输出$count行，每行一个优化后的提示词，不要编号或其他说明。';

    final response = await chat(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [
        {'role': 'user', 'content': originalPrompt},
      ],
    );

    return response
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(count)
        .toList();
  }

  Future<List<String>> polishPrompt({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String systemPrompt,
  }) async {
    final content = await chat(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
    );
    return content.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  Future<String> autoPolishPrompt({
    required String apiUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required String systemPrompt,
  }) async {
    final content = await chat(
      apiUrl: apiUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
    );
    return content.trim();
  }

  Stream<String> chatStream({
    required String apiUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) async* {
    final isClaude = apiUrl.contains('claudecode') || model.contains('claude');

    if (isClaude) {
      final url = apiUrl.endsWith('/v1/messages')
          ? apiUrl
          : (apiUrl.endsWith('/')
                ? '${apiUrl}v1/messages'
                : '$apiUrl/v1/messages');

      final requestData = <String, dynamic>{
        'model': model,
        'max_tokens': 4096,
        'stream': true,
        'messages': messages
            .map((m) => {'role': m['role'], 'content': m['content']})
            .toList(),
      };
      if (systemPrompt != null) {
        requestData['system'] = systemPrompt;
      }

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          responseType: ResponseType.stream,
        ),
        data: requestData,
      );

      final responseStream = response.data as ResponseBody;
      final stream = responseStream.stream.map(
        (bytes) => utf8.decode(bytes, allowMalformed: true),
      );

      await for (var chunk in stream) {
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6).trim();
            if (dataStr == '[DONE]') continue;
            try {
              final data = jsonDecode(dataStr);
              if (data['type'] == 'content_block_delta' &&
                  data['delta'] != null) {
                yield data['delta']['text'] ?? '';
              }
            } catch (e) {
              debugPrint('Claude SSE 解析错误: $e, Line: $line');
            }
          }
        }
      }
    } else {
      final url = _buildOpenAiChatCompletionsUrl(apiUrl);
      final requestMessages = <Map<String, dynamic>>[
        if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
        ...messages.map(
          (message) => <String, dynamic>{
            'role': message['role'],
            'content': message['content'],
          },
        ),
      ];

      final response = await _dio.post(
        url,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          responseType: ResponseType.stream,
        ),
        data: _buildOpenAiChatRequestBody(
          apiUrl: apiUrl,
          model: model,
          messages: requestMessages,
          stream: true,
        ),
      );

      final responseStream = response.data as ResponseBody;
      final stream = responseStream.stream.map(
        (bytes) => utf8.decode(bytes, allowMalformed: true),
      );

      await for (var chunk in stream) {
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final dataStr = line.substring(6).trim();
            if (dataStr == '[DONE]') continue;
            try {
              final data = jsonDecode(dataStr);
              if (data['choices'] != null && data['choices'].isNotEmpty) {
                final delta = data['choices'][0]['delta'];
                if (delta != null) {
                  if (delta['content'] != null) {
                    yield delta['content'];
                  }
                }
              }
            } catch (e) {
              debugPrint('OpenAI SSE 解析错误: $e, Line: $line');
            }
          }
        }
      }
    }
  }

  Future<int?> getApiCredits(String apiUrl, String apiKey) async {
    try {
      final uri = Uri.parse(apiUrl);
      final baseUrl =
          '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 80 && uri.port != 443 ? ':${uri.port}' : ''}';
      final response = await _dio.post(
        '$baseUrl/client/openapi/getAPIKeyCredits',
        options: Options(headers: {'Content-Type': 'application/json'}),
        data: {'apiKey': apiKey},
      );
      if (response.data['code'] == 0) {
        return response.data['data']['credits'] as int;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> checkModelStatus(String apiUrl, String modelName) async {
    if (_isWan2gpImageModel(modelName)) {
      return _checkWan2gpImageModelStatus(apiUrl, modelName);
    }

    if (_isWan2gpBridgeApi(apiUrl)) {
      return _checkWan2gpImageModelStatus(apiUrl, modelName);
    }
    try {
      final response = await _dio.get(
        '$apiUrl/client/common/getModelStatus?model=$modelName',
      );
      if (response.data['code'] == 0) {
        return response.data['data']['status'] as bool;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<String>> fetchModels(String apiUrl, String apiKey) async {
    if (_isWan2gpBridgeApi(apiUrl)) {
      return _fetchWan2gpImageModels(apiUrl);
    }
    try {
      final url = _buildOpenAiModelsUrl(apiUrl);
      final response = await _dio.get(
        url,
        options: Options(
          headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
          responseType: ResponseType.json,
        ),
      );
      final data = response.data;
      if (data is Map && data['data'] is List) {
        return (data['data'] as List)
            .map((m) => m['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // ignore and fall back to Wan2GP bridge probing below
    }
    return _fetchWan2gpImageModels(apiUrl);
  }
}

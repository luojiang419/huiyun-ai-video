import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';

import '../models/settings.dart';
import '../models/video_api_models.dart';
import '../models/video_generate_params.dart';
import 'image_relay_service.dart';

class VideoApiService {
  static const String _transparentPlaceholderDataUri =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  final String _baseUrl;
  final String _apiKey;
  final String _referenceUploadMethod;
  final ImageRelayService _imageRelayService = ImageRelayService();

  VideoApiService({
    String? baseUrl,
    String? apiKey,
    String referenceUploadMethod = Settings.uploadMethodRelayUrl,
    Dio? dio,
  })
    : _baseUrl = _normalizeBaseUrl(baseUrl ?? ''),
      _apiKey = apiKey?.trim() ?? '',
      _referenceUploadMethod = _normalizeUploadMethod(referenceUploadMethod),
      _dio = dio ?? _createDio(_normalizeBaseUrl(baseUrl ?? ''));

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  static String _normalizeUploadMethod(String uploadMethod) {
    return uploadMethod == Settings.uploadMethodBase64
        ? Settings.uploadMethodBase64
        : Settings.uploadMethodRelayUrl;
  }

  static Dio _createDio(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 180),
      ),
    );

    if (baseUrl.startsWith('https://')) {
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (certificate, host, port) => true;
          return client;
        };
      }
    }

    return dio;
  }

  bool get _isDirectVideoApi {
    final lower = _baseUrl.toLowerCase();
    return lower.contains('/open/api/video');
  }

  bool get _isJuziVideoApi {
    final lower = _baseUrl.toLowerCase();
    return lower.contains('juziaigc.com');
  }

  Options _authOptions({bool json = false, Duration? sendTimeout}) {
    final headers = <String, dynamic>{};
    if (_apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiKey';
    }
    if (json) {
      headers['Content-Type'] = Headers.jsonContentType;
    }
    return Options(headers: headers, sendTimeout: sendTimeout);
  }

  Future<TaskSubmitResult> submitT2V(VideoGenerateParams params) async {
    if (_isDirectVideoApi) {
      return _submitDirectT2V(params);
    }
    _logger.i('提交文生视频任务');
    final response = await _dio.post(
      '/api/generate/t2v',
      data: params.toJson(),
    );
    return TaskSubmitResult.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<TaskSubmitResult> submitI2V(
    VideoGenerateParams params,
    String imagePath,
  ) async {
    if (_isDirectVideoApi) {
      return _submitDirectI2V(params, imagePath);
    }
    _logger.i('提交图生视频任务: $imagePath');
    final file = await MultipartFile.fromFile(
      imagePath,
      filename: imagePath.split(Platform.pathSeparator).last,
    );
    final payload = {'image': file, ...params.toJson()};
    final formData = FormData.fromMap(payload);
    final response = await _dio.post(
      '/api/generate/i2v',
      data: formData,
      options: Options(sendTimeout: const Duration(seconds: 300)),
    );
    return TaskSubmitResult.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<VideoTaskProgress> getTaskStatus(String taskId) async {
    if (_isDirectVideoApi) {
      return _getDirectTaskStatus(taskId);
    }
    final response = await _dio.get('/api/task/$taskId/status');
    return VideoTaskProgress.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<Map<String, dynamic>> getTaskResult(String taskId) async {
    if (_isDirectVideoApi) {
      return _getDirectTaskResult(taskId);
    }
    final response = await _dio.get('/api/task/$taskId/result');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> cancelTask(String taskId) async {
    if (_isDirectVideoApi) {
      return;
    }
    await _dio.post('/api/task/$taskId/cancel');
  }

  Future<List<Map<String, dynamic>>> getTasks() async {
    final response = await _dio.get('/api/tasks');
    return List<Map<String, dynamic>>.from(response.data['tasks'] ?? []);
  }

  Future<List<ModelInfo>> fetchModels() async {
    try {
      final response = await _dio.get('/api/models');
      final models = (response.data['models'] as List?) ?? const [];
      return models
          .map((item) => ModelInfo.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<ModelCatalog?> fetchModelCatalog() async {
    try {
      final response = await _dio.get('/api/models');
      return ModelCatalog.fromJson(Map<String, dynamic>.from(response.data));
    } catch (_) {
      return null;
    }
  }

  Future<VideoServerInfo> getServerInfo() async {
    final response = await _dio.get('/api/server/info');
    return VideoServerInfo.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<bool> healthCheck() async {
    try {
      if (_isDirectVideoApi) {
        final response = await _dio.getUri(Uri.parse(_baseUrl));
        return response.statusCode == 200;
      }
      final response = await _dio.get('/api/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> downloadVideo(String videoUrl, String savePath) async {
    await _dio.download(videoUrl, savePath);
    return savePath;
  }

  Future<TaskSubmitResult> _submitDirectT2V(VideoGenerateParams params) async {
    _logger.i('提交直连文生视频任务');
    final formData = FormData.fromMap({
      'model': _resolveDirectModel(params),
      'prompt': params.prompt,
      'aspect_ratio': _resolveAspectRatio(params.resolution),
      'image_urls[0]': _transparentPlaceholderDataUri,
      'image_urls[1]': _transparentPlaceholderDataUri,
      ..._extractDirectWebhookFields(params),
    });
    final response = await _postDirectVideoForm(formData);
    return _parseDirectSubmitResult(response.data);
  }

  Future<TaskSubmitResult> _submitDirectI2V(
    VideoGenerateParams params,
    String imagePath,
  ) async {
    _logger.i('提交直连图生视频任务: $imagePath');
    final referenceValues = await _prepareDirectReferenceValues(imagePath);
    final formData = FormData.fromMap({
      'model': _resolveDirectModel(params),
      'prompt': params.prompt,
      'aspect_ratio': _resolveAspectRatio(params.resolution),
      'image_urls[0]': referenceValues.first,
      'image_urls[1]': referenceValues.length > 1
          ? referenceValues[1]
          : referenceValues.first,
      ..._extractDirectWebhookFields(params),
    });
    final response = await _postDirectVideoForm(formData);
    return _parseDirectSubmitResult(response.data);
  }

  Future<Response<dynamic>> _postDirectVideoForm(FormData formData) async {
    try {
      return await _dio.postUri(
        Uri.parse(_baseUrl),
        data: formData,
        options: _authOptions(sendTimeout: const Duration(seconds: 300)),
      );
    } on DioException catch (e) {
      throw StateError(_describeDioError('视频提交失败', e));
    }
  }

  TaskSubmitResult _parseDirectSubmitResult(dynamic rawData) {
    final payload = _asJsonMap(rawData);
    if (payload.isEmpty) {
      throw StateError('视频提交失败：未返回有效数据');
    }

    final code = (payload['code'] as num?)?.toInt();
    if (code != null && code != 200) {
      throw StateError(
        payload['msg']?.toString() ??
            payload['message']?.toString() ??
            '视频提交失败',
      );
    }

    final data = payload['data'] is Map<String, dynamic>
        ? payload['data'] as Map<String, dynamic>
        : payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : <String, dynamic>{};
    final taskId =
        data['juzi_id']?.toString() ??
        data['id']?.toString() ??
        payload['juzi_id']?.toString() ??
        payload['task_id']?.toString() ??
        '';
    if (taskId.isEmpty) {
      throw StateError('视频提交失败：未获取到任务ID');
    }

    return TaskSubmitResult(taskId: taskId, status: 'queued');
  }

  Future<VideoTaskProgress> _getDirectTaskStatus(String taskId) async {
    final payload = await _fetchDirectStatusPayload(taskId);
    final normalized = _normalizeDirectStatusPayload(payload);
    final rawStatus = normalized['status']?.toString().toLowerCase() ?? 'queued';
    final progressValue = (normalized['progress'] as num?)?.toDouble() ?? 0;

    String mappedStatus;
    switch (rawStatus) {
      case 'succeeded':
      case 'completed':
        mappedStatus = 'completed';
        break;
      case 'failed':
      case 'error':
        mappedStatus = 'failed';
        break;
      case 'pending':
      case 'submitted':
      case 'queued':
        mappedStatus = 'queued';
        break;
      default:
        mappedStatus = 'running';
        break;
    }

    final percentage = progressValue.clamp(0, 100).toDouble();
    return VideoTaskProgress(
      taskId: taskId,
      status: mappedStatus,
      currentStep: percentage.round(),
      totalSteps: 100,
      percentage: percentage,
    );
  }

  Future<Map<String, dynamic>> _getDirectTaskResult(String taskId) async {
    final payload = await _fetchDirectStatusPayload(taskId);
    final normalized = _normalizeDirectStatusPayload(payload);
    final videoUrl =
        normalized['juzi_url']?.toString() ??
        normalized['video_url']?.toString() ??
        normalized['url']?.toString() ??
        normalized['output_url']?.toString() ??
        '';
    return {
      'video_url': videoUrl,
      'url': videoUrl,
      'error': normalized['error']?.toString() ?? normalized['message']?.toString(),
    };
  }

  Future<Map<String, dynamic>> _fetchDirectStatusPayload(String taskId) async {
    final endpoints = <String>{
      '$_baseUrl/status',
      _baseUrl.replaceFirst(RegExp(r'/video$'), '/vNotify'),
    };
    Object? lastError;
    for (final endpoint in endpoints.where((item) => item.trim().isNotEmpty)) {
      try {
        final response = await _dio.postUri(
          Uri.parse(endpoint),
          data: {'juzi_id': taskId},
          options: _authOptions(json: true),
        );
        final payload = _asJsonMap(response.data);
        if (payload.isNotEmpty) {
          return payload;
        }
      } on DioException catch (e) {
        lastError = _describeDioError('视频任务状态查询失败', e);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError('视频任务状态查询失败: ${lastError ?? '未返回有效响应'}');
  }

  Map<String, dynamic> _normalizeDirectStatusPayload(
    Map<String, dynamic> payload,
  ) {
    if (payload['data'] is Map<String, dynamic>) {
      return payload['data'] as Map<String, dynamic>;
    }
    if (payload['data'] is Map) {
      return Map<String, dynamic>.from(payload['data'] as Map);
    }
    return payload;
  }

  Map<String, dynamic> _asJsonMap(dynamic rawData) {
    if (rawData is Map<String, dynamic>) {
      return rawData;
    }
    if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }
    if (rawData is String) {
      final trimmed = rawData.trim();
      if (trimmed.isEmpty) {
        return const {};
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {'message': trimmed};
      }
    }
    return const {};
  }

  Map<String, String> _extractDirectWebhookFields(VideoGenerateParams params) {
    final webhookUrl = params.advancedSettings['webhook_url']?.toString().trim();
    if (webhookUrl == null || webhookUrl.isEmpty) {
      return const {};
    }
    return {'webhook_url': webhookUrl};
  }

  String _resolveDirectModel(VideoGenerateParams params) {
    final model = params.modelName.trim();
    if (model.isEmpty) {
      return 'VEO 3.1 Fast 多参考版';
    }
    final looksLikeWan2gp = RegExp(
      r'(?:^|[-_])(t2v|i2v|wan|a14b|14b)',
      caseSensitive: false,
    ).hasMatch(model);
    if (looksLikeWan2gp && _isJuziVideoApi) {
      return 'VEO 3.1 Fast 多参考版';
    }
    return model;
  }

  String _resolveAspectRatio(String resolution) {
    final match = RegExp(r'(\d+)\s*[*xX]\s*(\d+)').firstMatch(resolution);
    if (match == null) {
      return '16:9';
    }
    final width = int.tryParse(match.group(1) ?? '') ?? 0;
    final height = int.tryParse(match.group(2) ?? '') ?? 0;
    if (width == 0 || height == 0) {
      return '16:9';
    }
    return height > width ? '9:16' : '16:9';
  }

  Future<List<String>> _prepareDirectReferenceValues(String imagePath) async {
    if (_shouldUseRelayUrlForDirectSubmit()) {
      final relayUrl = await _imageRelayService.uploadImageInput(imagePath);
      if (relayUrl.startsWith('http://') || relayUrl.startsWith('https://')) {
        return [relayUrl, relayUrl];
      }
    }

    final dataUri = await _convertImageInputToDataUri(imagePath);
    return [dataUri, dataUri];
  }

  bool _shouldUseRelayUrlForDirectSubmit() {
    return _isDirectVideoApi &&
        _referenceUploadMethod == Settings.uploadMethodRelayUrl;
  }

  String _describeDioError(String prefix, DioException error) {
    final statusCode = error.response?.statusCode;
    final rawData = error.response?.data;
    final payload = _asJsonMap(rawData);
    final message =
        payload['msg']?.toString() ??
        payload['message']?.toString() ??
        payload['error']?.toString() ??
        (rawData is String ? rawData.trim() : '');
    final pieces = <String>[prefix];
    if (statusCode != null) {
      pieces.add('HTTP $statusCode');
    }
    if (message.isNotEmpty) {
      pieces.add(message);
    } else if (error.message?.trim().isNotEmpty == true) {
      pieces.add(error.message!.trim());
    }
    return pieces.join('：');
  }

  Future<String> _convertImageInputToDataUri(String imagePath) async {
    final trimmed = imagePath.trim();
    if (trimmed.startsWith('data:')) {
      return trimmed;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final response = await _dio.getUri<List<int>>(
        Uri.parse(trimmed),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data ?? const <int>[];
      final mimeType = response.headers.value(Headers.contentTypeHeader) ??
          'image/png';
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    }

    final file = File(trimmed);
    final bytes = await file.readAsBytes();
    final mimeType = _guessMimeType(trimmed);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.gif')) {
      return 'image/gif';
    }
    if (lower.endsWith('.bmp')) {
      return 'image/bmp';
    }
    return 'image/png';
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:mime/mime.dart';

class VideoPromptPolishResult {
  final String originalPrompt;
  final String polishedPrompt;
  final bool success;
  final String? errorMessage;
  final String? rawResponse;

  const VideoPromptPolishResult({
    required this.originalPrompt,
    required this.polishedPrompt,
    required this.success,
    this.errorMessage,
    this.rawResponse,
  });
}

class VideoVlmService {
  final Dio _dio;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  String _apiUrl;
  String _model;

  VideoVlmService({
    required String apiUrl,
    required String model,
    String? apiKey,
  }) : _apiUrl = apiUrl,
       _model = model,
       _dio = Dio(
         BaseOptions(
           connectTimeout: const Duration(seconds: 30),
           receiveTimeout: const Duration(seconds: 120),
           headers: apiKey != null && apiKey.isNotEmpty
               ? {'Authorization': 'Bearer $apiKey'}
               : {},
         ),
       );

  void updateConfig({String? apiUrl, String? model, String? apiKey}) {
    if (apiUrl != null) _apiUrl = apiUrl;
    if (model != null) _model = model;
    if (apiKey != null && apiKey.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $apiKey';
    } else if (apiKey != null) {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<bool> testConnection() async {
    try {
      final response = await _dio.get(
        _apiUrl.replaceAll('/v1/chat/completions', '/v1/models'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<VideoPromptPolishResult> polishT2VPrompt(String text) async {
    final originalPrompt = text.trim();
    if (originalPrompt.isEmpty) {
      return const VideoPromptPolishResult(
        originalPrompt: '',
        polishedPrompt: '',
        success: false,
        errorMessage: '提示词为空，无法润色',
      );
    }

    try {
      final content = await _postTextOnlyChat(
        systemPrompt: _t2vPolishSystemPrompt,
        userPrompt: '用户原始提示词：$originalPrompt',
      );
      final polishedPrompt = _cleanPrompt(content);
      if (polishedPrompt.isEmpty) {
        return VideoPromptPolishResult(
          originalPrompt: originalPrompt,
          polishedPrompt: originalPrompt,
          success: false,
          errorMessage: 'AI 未返回有效润色内容',
          rawResponse: content,
        );
      }
      return VideoPromptPolishResult(
        originalPrompt: originalPrompt,
        polishedPrompt: polishedPrompt,
        success: true,
        rawResponse: content,
      );
    } catch (e) {
      _logger.e('VLM文生润色失败: $e');
      return VideoPromptPolishResult(
        originalPrompt: originalPrompt,
        polishedPrompt: originalPrompt,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<VideoPromptPolishResult> polishI2VPrompt(
    String imagePath,
    String userPrompt,
  ) async {
    final originalPrompt = userPrompt.trim();
    try {
      final base64Image = await _imageToBase64(imagePath);
      final mimeType = lookupMimeType(imagePath) ?? 'image/jpeg';
      final response = await _dio.post(
        _apiUrl,
        data: {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': _i2vPolishSystemPrompt},
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text':
                      '请先分析图片，再基于画面内容主导生成动态视频提示词。'
                      '\n用户补充提示词：${originalPrompt.isEmpty ? '无' : originalPrompt}'
                      '\n输出要求：只输出最终可直接给视频模型使用的一段完整动态提示词。',
                },
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
                },
              ],
            },
          ],
          'max_tokens': 2048,
          'temperature': 0.7,
        },
      );
      final content =
          response.data['choices']?[0]?['message']?['content']?.toString() ??
          '';
      final polishedPrompt = _cleanPrompt(content);
      if (polishedPrompt.isEmpty) {
        return VideoPromptPolishResult(
          originalPrompt: originalPrompt,
          polishedPrompt: originalPrompt,
          success: false,
          errorMessage: 'AI 未返回有效润色内容',
          rawResponse: content,
        );
      }
      return VideoPromptPolishResult(
        originalPrompt: originalPrompt,
        polishedPrompt: polishedPrompt,
        success: true,
        rawResponse: content,
      );
    } catch (e) {
      _logger.e('VLM图生润色失败: $e');
      return VideoPromptPolishResult(
        originalPrompt: originalPrompt,
        polishedPrompt: originalPrompt,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<String> _postTextOnlyChat({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    try {
      final response = await _dio.post(
        _apiUrl,
        data: {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'max_tokens': 2048,
          'temperature': 0.7,
        },
      );
      return response.data['choices']?[0]?['message']?['content']?.toString() ??
          '';
    } on DioException {
      final fallback = await _dio.post(
        _apiUrl,
        data: {
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': userPrompt},
              ],
            },
          ],
          'max_tokens': 2048,
          'temperature': 0.7,
        },
      );
      return fallback.data['choices']?[0]?['message']?['content']?.toString() ??
          '';
    }
  }

  String _cleanPrompt(String prompt) {
    final patterns = [
      RegExp(r'^我是[^\n]*\n?', multiLine: true),
      RegExp(r'^作为[^\n]*\n?', multiLine: true),
      RegExp(r'^好的[，,][^\n]*\n?', multiLine: true),
      RegExp(r'^以下是[^\n]*\n?', multiLine: true),
      RegExp(r'^根据[^\n]*分析[：:][^\n]*\n?', multiLine: true),
    ];
    var cleaned = prompt;
    for (final pattern in patterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }
    return cleaned
        .replaceAll(RegExp(r'^```[a-zA-Z]*\s*', multiLine: true), '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'^(润色结果|最终提示词|画面描述)[：:]\s*', multiLine: true), '')
        .trim();
  }

  Future<String> _imageToBase64(String path) async {
    final bytes = await File(path).readAsBytes();
    return base64Encode(bytes);
  }

  static const _t2vPolishSystemPrompt =
      '''你是视频生成提示词润色助手。你的唯一任务是：把用户输入的简单文本扩写成一段更精彩、更适合视频生成模型的动态画面提示词。

严格要求：
1. 保留用户原始意图，不要改成完全不同的内容
2. 必须补充动态元素，包括主体动作、镜头运动、场景变化、光影变化、节奏感
3. 结果必须是一段可以直接提交给视频模型的完整提示词
4. 不要输出解释、分析过程、标题、项目符号、身份声明
5. 不要使用“我是”“下面是”“润色结果”之类前置语
6. 输出应明显丰富于原文，但不要堆砌空洞辞藻或模板化长文
7. 输出重点是动态画面，而不是静态美术描述''';

  static const _i2vPolishSystemPrompt =
      '''你是图生视频提示词润色助手。你的唯一任务是：先分析用户提供的图片，再以画面内容为主导，结合用户补充文字，输出一段适合视频生成模型的完整动态提示词。

严格要求：
1. 以画面内容为主导，优先遵循图片中的主体、环境、构图和情绪
2. 用户补充文字只用于增强不冲突的风格、剧情或重点
3. 必须补充镜头运动、主体动作、表情变化、环境动态和光影节奏
4. 若用户没有输入文字，也必须基于图片直接生成完整动态提示词
5. 输出只能是一段最终提示词，不要输出分析过程、结构化标签、标题或解释
6. 如果用户文字与图片明显冲突，以图片内容为准，只吸收不冲突信息
7. 结果要有明确电影感、运动感和镜头语言，适合直接提交给视频模型''';
}

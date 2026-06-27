import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../providers/generate_provider.dart';
import '../providers/api_config_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/credits_provider.dart';
import '../providers/generated_images_provider.dart';
import '../providers/settings_provider.dart';
import '../models/api_config.dart';
import '../utils/image_api_config_resolver.dart';
import '../models/message.dart';
import '../utils/error_translator.dart';
import '../models/session.dart';

final generateLogicServiceProvider = Provider(
  (ref) => GenerateLogicService(ref),
);

class GenerateImageTaskRequest {
  final String prompt;
  final String model;
  final String aspectRatio;
  final String imageSize;
  final String imageQuality;
  final int? sampleSteps;
  final List<String> referenceImages;
  final List<String> referenceImagePaths;

  const GenerateImageTaskRequest({
    required this.prompt,
    required this.model,
    required this.aspectRatio,
    required this.imageSize,
    this.imageQuality = 'auto',
    this.sampleSteps,
    this.referenceImages = const [],
    this.referenceImagePaths = const [],
  });
}

class GenerateLogicService {
  final Ref _ref;
  final Map<String, List<String>> _batchResults = {};
  final Map<String, int> _batchCompleted = {};

  GenerateLogicService(this._ref);

  Future<Session?> _ensureCurrentSession() async {
    var currentSession = _ref.read(currentSessionProvider);
    if (currentSession != null) {
      return currentSession;
    }
    await _ref.read(currentSessionProvider.notifier).loadLastSession();
    currentSession = _ref.read(currentSessionProvider);
    return currentSession;
  }

  bool _isTerminalMessageText(String text) {
    return text.startsWith('生成完成') ||
        text.startsWith('生成失败') ||
        text.startsWith('批量生成完成') ||
        text.startsWith('AI任务生成完成') ||
        text.startsWith('多角度生成完成');
  }

  static String buildQueuedProgressText({
    required String progressLabel,
    required int completed,
    required int total,
    required int failed,
    required int elapsedSeconds,
  }) {
    final failedText = failed == 0 ? '' : '，失败$failed个';
    return '$progressLabel ($completed/$total$failedText)，已等待 ${elapsedSeconds}s';
  }

  static String buildQueuedTerminalText({
    required int total,
    required int failed,
    required int elapsedSeconds,
  }) {
    final prefix = failed == 0
        ? 'AI任务生成完成 ($total/$total)'
        : 'AI任务生成完成 ($total/$total)，失败$failed个';
    return '$prefix，用时 ${elapsedSeconds}s';
  }

  Future<List<ApiConfig>> _loadApiConfigs() async {
    final notifier = _ref.read(apiConfigsProvider.notifier);
    await notifier.ensureLoaded();
    return _ref.read(apiConfigsProvider).whereType<ApiConfig>().toList();
  }

  List<ApiConfig> _resolveImageConfigs(List<ApiConfig> configs, String model) {
    final resolved =
        ImageApiConfigResolver.resolveImageConfigCandidatesForModel(
          configs,
          model,
        );
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final defaultImage = configs.firstWhere(
      (c) => c.isDefault && c.type == 'image',
      orElse: () => configs.firstWhere(
        (c) => c.type == 'image',
        orElse: () => configs.first,
      ),
    );
    return [defaultImage];
  }

  static List<String> buildReferenceInputs(
    List<String> referenceImages,
    List<String> referenceImagePaths,
  ) {
    final inputs = <String>[];
    final inputCount = referenceImages.length > referenceImagePaths.length
        ? referenceImages.length
        : referenceImagePaths.length;

    for (int i = 0; i < inputCount; i++) {
      final imagePath = i < referenceImagePaths.length
          ? referenceImagePaths[i].trim()
          : '';
      if (imagePath.isNotEmpty) {
        inputs.add(imagePath);
        continue;
      }

      final imageData = i < referenceImages.length
          ? referenceImages[i].trim()
          : '';
      if (imageData.isEmpty) {
        continue;
      }

      if (imageData.startsWith('data:')) {
        inputs.add(imageData);
      } else {
        inputs.add('data:image/png;base64,$imageData');
      }
    }
    return inputs;
  }

  Future<void> generateBatch({
    required String originalPrompt,
    required String polishedPrompt,
    required String model,
    required String aspectRatio,
    required String imageSize,
    String imageQuality = 'auto',
    int? sampleSteps,
    required List<String> referenceImages,
    required List<String> referenceImagePaths,
    required int batchIndex,
    required int totalBatch,
  }) async {
    final batchId = '${DateTime.now().millisecondsSinceEpoch}_$totalBatch';

    if (batchIndex == 0) {
      _batchResults[batchId] = [];
      _batchCompleted[batchId] = 0;

      final currentSession = await _ensureCurrentSession();
      if (currentSession == null) return;

      await _ref
          .read(currentSessionProvider.notifier)
          .addMessage(
            Message(
              type: 'user',
              text: originalPrompt,
              images: [],
              params: {
                'model': model,
                'aspectRatio': aspectRatio,
                'imageSize': imageSize,
                'imageQuality': imageQuality,
                if (sampleSteps != null) 'sampleSteps': sampleSteps,
                'referenceImages': referenceImagePaths,
                'batchCount': totalBatch,
              },
            ),
          );

      final assistantMessage = Message(
        type: 'assistant',
        text: '批量生成中 (0/$totalBatch)',
        images: [],
      );
      await _ref
          .read(currentSessionProvider.notifier)
          .addMessage(assistantMessage);
    }

    final currentSession = await _ensureCurrentSession();
    if (currentSession == null) return;
    final targetSessionName = currentSession.name;
    final messageId = currentSession.messages.last.id;

    try {
      final results = await runImageTask(
        GenerateImageTaskRequest(
          prompt: polishedPrompt,
          model: model,
          aspectRatio: aspectRatio,
          imageSize: imageSize,
          imageQuality: imageQuality,
          sampleSteps: sampleSteps,
          referenceImages: referenceImages,
          referenceImagePaths: referenceImagePaths,
        ),
      );

      _batchResults[batchId]?.addAll(results);
      _batchCompleted[batchId] = (_batchCompleted[batchId] ?? 0) + 1;

      final completed = _batchCompleted[batchId] ?? 0;
      if (completed >= totalBatch) {
        await _updateMessageSafe(
          targetSessionName,
          messageId,
          Message(
            id: messageId,
            type: 'assistant',
            text: '批量生成完成',
            images: _batchResults[batchId] ?? [],
            params: {
              'prompt': polishedPrompt,
              'model': model,
              'aspectRatio': aspectRatio,
              'imageSize': imageSize,
              'imageQuality': imageQuality,
              if (sampleSteps != null) 'sampleSteps': sampleSteps,
              'batchCount': totalBatch,
            },
          ),
        );

        for (final imagePath in _batchResults[batchId] ?? []) {
          _ref.read(generatedImagesProvider.notifier).addImage(imagePath);
        }
        _ref.read(galleryImagesProvider.notifier).loadImages();

        _batchResults.remove(batchId);
        _batchCompleted.remove(batchId);
        await _ref.read(creditsProvider.notifier).fetchCredits();
      } else {
        await _updateMessageSafe(
          targetSessionName,
          messageId,
          Message(
            id: messageId,
            type: 'assistant',
            text: '批量生成中 ($completed/$totalBatch)',
            images: _batchResults[batchId] ?? [],
            params: {
              'prompt': polishedPrompt,
              'model': model,
              'aspectRatio': aspectRatio,
              'imageSize': imageSize,
              'imageQuality': imageQuality,
              if (sampleSteps != null) 'sampleSteps': sampleSteps,
              'batchCount': totalBatch,
            },
          ),
        );
      }
    } catch (e) {
      _batchCompleted[batchId] = (_batchCompleted[batchId] ?? 0) + 1;
      final completed = _batchCompleted[batchId] ?? 0;
      if (completed >= totalBatch) {
        _batchResults.remove(batchId);
        _batchCompleted.remove(batchId);
      }
    }
  }

  Future<List<String>> generateQueuedTasks({
    required String originalPrompt,
    required List<GenerateImageTaskRequest> tasks,
    int delayMs = 800,
    int maxConcurrency = 3,
    String progressLabel = 'AI任务生成中',
  }) async {
    if (tasks.isEmpty) return const [];

    final currentSession = await _ensureCurrentSession();
    if (currentSession == null) return const [];
    final targetSessionName = currentSession.name;

    await _ref
        .read(currentSessionProvider.notifier)
        .addMessage(
          Message(
            type: 'user',
            text: originalPrompt,
            images: [],
            params: {
              'taskCount': tasks.length,
              'delayMs': delayMs,
              'maxConcurrency': maxConcurrency,
            },
          ),
        );

    final assistantMessage = Message(
      type: 'assistant',
      text: buildQueuedProgressText(
        progressLabel: progressLabel,
        completed: 0,
        total: tasks.length,
        failed: 0,
        elapsedSeconds: 0,
      ),
      images: [],
    );
    await _ref
        .read(currentSessionProvider.notifier)
        .addMessage(assistantMessage);
    final messageId = assistantMessage.id;

    final results = <String>[];
    final errors = <String>[];
    var completed = 0;
    var nextIndex = 0;
    final safeConcurrency = maxConcurrency < 1
        ? 1
        : maxConcurrency > 5
        ? 5
        : maxConcurrency;
    final safeDelayMs = delayMs < 0
        ? 800
        : delayMs > 5000
        ? 5000
        : delayMs;
    final startTime = DateTime.now();
    Timer? messageUpdateTimer;

    messageUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (completed >= tasks.length) return;
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      await _updateProgressMessageText(
        targetSessionName,
        messageId,
        buildQueuedProgressText(
          progressLabel: progressLabel,
          completed: completed,
          total: tasks.length,
          failed: errors.length,
          elapsedSeconds: elapsed,
        ),
      );
    });

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        nextIndex += 1;
        if (index >= tasks.length) return;
        if (safeDelayMs > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: index * safeDelayMs),
          );
        }
        try {
          final taskResults = await runImageTask(tasks[index]);
          results.addAll(taskResults);
        } catch (e) {
          errors.add(ErrorTranslator.translate(e.toString()));
        } finally {
          completed += 1;
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          await _updateMessageSafe(
            targetSessionName,
            messageId,
            Message(
              id: messageId,
              type: 'assistant',
              text: completed >= tasks.length
                  ? buildQueuedTerminalText(
                      total: tasks.length,
                      failed: errors.length,
                      elapsedSeconds: elapsed,
                    )
                  : buildQueuedProgressText(
                      progressLabel: progressLabel,
                      completed: completed,
                      total: tasks.length,
                      failed: errors.length,
                      elapsedSeconds: elapsed,
                    ),
              images: List<String>.from(results),
              params: {
                'taskCount': tasks.length,
                'completed': completed,
                'failed': errors.length,
                'delayMs': safeDelayMs,
                'maxConcurrency': safeConcurrency,
                'elapsedSeconds': elapsed,
              },
            ),
          );
        }
      }
    }

    try {
      await Future.wait(List.generate(safeConcurrency, (_) => runWorker()));
    } finally {
      messageUpdateTimer.cancel();
    }

    for (final imagePath in results) {
      _ref.read(generatedImagesProvider.notifier).addImage(imagePath);
    }
    _ref.read(galleryImagesProvider.notifier).loadImages();
    await _ref.read(creditsProvider.notifier).fetchCredits();
    return results;
  }

  Future<List<String>> runImageTask(GenerateImageTaskRequest task) async {
    final configs = await _loadApiConfigs();
    if (configs.isEmpty) {
      throw Exception('请先配置API');
    }

    final imageConfigs = configs
        .where((config) => config.type == 'image')
        .toList();
    if (imageConfigs.isEmpty) {
      throw Exception('请先配置图片生成API');
    }

    final candidateConfigs = _resolveImageConfigs(configs, task.model);
    final apiService = _ref.read(apiServiceProvider);
    final settings = _ref.read(settingsProvider);
    final urls = buildReferenceInputs(
      task.referenceImages,
      task.referenceImagePaths,
    );
    Exception? lastError;

    for (final candidateConfig in candidateConfigs) {
      final results = <String>[];
      try {
        await for (final progress in apiService.generateImage(
          apiUrl: candidateConfig.url,
          apiKey: candidateConfig.key,
          model: task.model,
          prompt: task.prompt,
          aspectRatio: task.aspectRatio,
          imageSize: task.imageSize,
          imageQuality: task.imageQuality,
          sampleSteps: task.sampleSteps,
          urls: urls,
          uploadMethod: settings.uploadMethod,
          outputFolder: settings.outputFolder,
        )) {
          if (progress.status == 'failed') {
            throw Exception(progress.error ?? '未知错误');
          }
          if (progress.results != null) {
            results.addAll(progress.results!);
          }
        }
        if (results.isNotEmpty) {
          return results;
        }
        throw Exception('生成结果为空');
      } catch (error) {
        lastError = Exception(
          '${candidateConfig.name}(${candidateConfig.url}) 生成失败: $error',
        );
      }
    }

    throw lastError ?? Exception('图片生成失败');
  }

  Future<void> generate({
    required String prompt,
    required String model,
    required String aspectRatio,
    required String imageSize,
    String imageQuality = 'auto',
    int? sampleSteps,
    required List<String> referenceImages, // Base64 strings
    required List<String> referenceImagePaths,
  }) async {
    final configs = await _loadApiConfigs();
    if (configs.isEmpty) {
      throw Exception('请先配置API');
    }

    // Capture current session name
    final currentSession = await _ensureCurrentSession();
    if (currentSession == null) return;
    final targetSessionName = currentSession.name;

    // Add User Message
    await _ref
        .read(currentSessionProvider.notifier)
        .addMessage(
          Message(
            type: 'user',
            text: prompt,
            images: [],
            params: {
              'model': model,
              'aspectRatio': aspectRatio,
              'imageSize': imageSize,
              'imageQuality': imageQuality,
              if (sampleSteps != null) 'sampleSteps': sampleSteps,
              'referenceImages': referenceImagePaths,
            },
          ),
        );

    // Add Assistant Placeholder
    final assistantMessage = Message(
      type: 'assistant',
      text: '生成中，已等待 0s',
      images: [],
    );
    await _ref
        .read(currentSessionProvider.notifier)
        .addMessage(assistantMessage);

    // Get message ID for safe updating
    final messageId = assistantMessage.id;

    // Start Timer (Internal)
    final startTime = DateTime.now();

    // Message Update Timer
    Timer? messageUpdateTimer;
    messageUpdateTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      await _updateProgressMessageText(
        targetSessionName,
        messageId,
        '生成中，已等待 ${elapsed}s',
      );
    });

    try {
      final results = await runImageTask(
        GenerateImageTaskRequest(
          prompt: prompt,
          model: model,
          aspectRatio: aspectRatio,
          imageSize: imageSize,
          imageQuality: imageQuality,
          sampleSteps: sampleSteps,
          referenceImages: referenceImages,
          referenceImagePaths: referenceImagePaths,
        ),
      );

      messageUpdateTimer.cancel();
      final totalTime = DateTime.now().difference(startTime).inSeconds;

      await _updateMessageSafe(
        targetSessionName,
        messageId,
        Message(
          id: messageId,
          type: 'assistant',
          text: '生成完成',
          images: results,
          params: {
            'prompt': prompt,
            'model': model,
            'aspectRatio': aspectRatio,
            'imageSize': imageSize,
            'imageQuality': imageQuality,
            if (sampleSteps != null) 'sampleSteps': sampleSteps,
            'time': totalTime,
          },
        ),
      );

      for (final imagePath in results) {
        _ref.read(generatedImagesProvider.notifier).addImage(imagePath);
      }
      _ref.read(galleryImagesProvider.notifier).loadImages();

      await _ref.read(creditsProvider.notifier).fetchCredits();
    } catch (e) {
      messageUpdateTimer.cancel();
      await _updateMessageSafe(
        targetSessionName,
        messageId,
        Message(
          id: messageId,
          type: 'assistant',
          text: '生成失败: ${ErrorTranslator.translate(e.toString())}',
          images: [],
        ),
      );
      await _ref.read(creditsProvider.notifier).fetchCredits();
    }
  }

  Future<void> _updateMessageSafe(
    String targetSessionName,
    String messageId,
    Message message,
  ) async {
    final currentSession = _ref.read(currentSessionProvider);
    if (currentSession?.name == targetSessionName) {
      // If current session is the target, use notifier (updates UI and file)
      final index = currentSession!.messages.indexWhere(
        (m) => m.id == messageId,
      );
      if (index != -1) {
        await _ref
            .read(currentSessionProvider.notifier)
            .updateMessage(index, message);
      }
    } else {
      // If not current, load from file, update, and save
      final sessionService = _ref.read(sessionServiceProvider);
      final session = await sessionService.loadSession(targetSessionName);
      if (session != null) {
        final index = session.messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final messages = List<Message>.from(session.messages);
          messages[index] = message;
          final updatedSession = Session(
            name: session.name,
            created: session.created,
            messages: messages,
          );
          await sessionService.saveSession(updatedSession);
        }
      }
    }
  }

  Future<void> _updateProgressMessageText(
    String targetSessionName,
    String messageId,
    String text,
  ) async {
    final currentSession = _ref.read(currentSessionProvider);
    if (currentSession?.name == targetSessionName) {
      final index = currentSession!.messages.indexWhere(
        (m) => m.id == messageId,
      );
      if (index == -1) return;
      final currentMessage = currentSession.messages[index];
      if (_isTerminalMessageText(currentMessage.text)) {
        return;
      }
      await _ref
          .read(currentSessionProvider.notifier)
          .updateMessage(
            index,
            Message(
              id: currentMessage.id,
              type: currentMessage.type,
              text: text,
              images: currentMessage.images,
              videos: currentMessage.videos,
              params: currentMessage.params,
            ),
          );
      return;
    }

    final sessionService = _ref.read(sessionServiceProvider);
    final session = await sessionService.loadSession(targetSessionName);
    if (session == null) return;
    final index = session.messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final currentMessage = session.messages[index];
    if (_isTerminalMessageText(currentMessage.text)) {
      return;
    }

    final messages = List<Message>.from(session.messages);
    messages[index] = Message(
      id: currentMessage.id,
      type: currentMessage.type,
      text: text,
      images: currentMessage.images,
      videos: currentMessage.videos,
      params: currentMessage.params,
    );
    await sessionService.saveSession(
      Session(name: session.name, created: session.created, messages: messages),
    );
  }
}

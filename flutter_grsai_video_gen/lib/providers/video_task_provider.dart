import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/compute_node.dart';
import '../models/message.dart';
import '../models/video_api_models.dart';
import '../models/video_generate_params.dart';
import '../models/video_item.dart';
import '../models/video_task.dart';
import '../models/session.dart';
import '../services/video_api_service.dart';
import 'api_config_provider.dart';
import 'background_task_provider.dart';
import 'core_services_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';
import 'video_config_provider.dart';
import 'video_gallery_provider.dart';
import 'video_node_provider.dart';

final videoTaskProvider =
    StateNotifierProvider<VideoTaskNotifier, List<VideoTask>>((ref) {
      return VideoTaskNotifier(ref);
    });

class _VideoServiceTarget {
  final String id;
  final String name;
  final String apiUrl;
  final String apiKey;

  const _VideoServiceTarget({
    required this.id,
    required this.name,
    required this.apiUrl,
    this.apiKey = '',
  });
}

class VideoTaskNotifier extends StateNotifier<List<VideoTask>> {
  final Ref _ref;
  final Map<String, Timer> _pollTimers = {};

  VideoTaskNotifier(this._ref) : super([]);

  @override
  void dispose() {
    for (final timer in _pollTimers.values) {
      timer.cancel();
    }
    _pollTimers.clear();
    super.dispose();
  }

  Future<VideoTask> submitT2V(
    VideoGenerateParams params, {
    String? targetNodeId,
    bool writeToCurrentSession = false,
  }) async {
    final target = _selectTarget(targetNodeId);
    final settings = _ref.read(settingsProvider);
    final service = VideoApiService(
      baseUrl: target.apiUrl,
      apiKey: target.apiKey,
      referenceUploadMethod: settings.uploadMethod,
    );
    final normalizedParams = _normalizeParamsForTarget(params, target);
    final result = await service.submitT2V(normalizedParams);
    final sessionBinding = writeToCurrentSession
        ? await _createT2vSessionMessages(
            prompt: normalizedParams.prompt,
            taskId: result.taskId,
            modelName: normalizedParams.modelName,
            resolution: normalizedParams.resolution,
          )
        : null;

    final task = VideoTask(
      id: result.taskId,
      type: VideoTaskType.t2v,
      params: normalizedParams,
      assignedNodeId: target.id,
      assignedNodeName: target.name,
      createdAt: DateTime.now(),
      totalSteps: normalizedParams.sampleSteps,
      sessionName: sessionBinding?.sessionName,
      sessionMessageId: sessionBinding?.assistantMessageId,
    );
    _appendTask(task);
    _addBackgroundTask(task);
    _startPolling(task, service, target);
    return task;
  }

  Future<VideoTask> submitI2V(
    VideoGenerateParams params,
    String imagePath, {
    String? targetNodeId,
    bool writeToCurrentSession = false,
  }) async {
    final target = _selectTarget(targetNodeId);
    final fileService = _ref.read(fileServiceProvider);
    final settings = _ref.read(settingsProvider);
    var managedImagePath = imagePath;
    if (!managedImagePath.startsWith(
          fileService.getVideoReferenceDirectory(),
        ) &&
        File(managedImagePath).existsSync()) {
      managedImagePath = await fileService.saveVideoReferenceImage(
        File(managedImagePath),
      );
    }

    final service = VideoApiService(
      baseUrl: target.apiUrl,
      apiKey: target.apiKey,
      referenceUploadMethod: settings.uploadMethod,
    );
    final normalizedParams = _normalizeParamsForTarget(params, target);
    final result = await service.submitI2V(normalizedParams, managedImagePath);
    final sessionBinding = writeToCurrentSession
        ? await _createSessionMessages(
            prompt: normalizedParams.prompt,
            imagePath: managedImagePath,
            taskId: result.taskId,
            modelName: normalizedParams.modelName,
            resolution: normalizedParams.resolution,
          )
        : null;
    final task = VideoTask(
      id: result.taskId,
      type: VideoTaskType.i2v,
      params: normalizedParams,
      imagePath: managedImagePath,
      assignedNodeId: target.id,
      assignedNodeName: target.name,
      createdAt: DateTime.now(),
      totalSteps: normalizedParams.sampleSteps,
      sessionName: sessionBinding?.sessionName,
      sessionMessageId: sessionBinding?.assistantMessageId,
    );
    _appendTask(task);
    _addBackgroundTask(task);
    _startPolling(task, service, target);
    return task;
  }

  Future<void> cancelTask(String id) async {
    final task = state.where((item) => item.id == id).firstOrNull;
    if (task == null) return;

    _pollTimers[id]?.cancel();
    _pollTimers.remove(id);
    if (task.assignedNodeId != null) {
      final target = _resolveTarget(task.assignedNodeId!);
      if (target != null) {
        try {
          await VideoApiService(
            baseUrl: target.apiUrl,
            apiKey: target.apiKey,
          ).cancelTask(id);
        } catch (_) {
          // ignore
        }
      }
    }
    _replaceTask(
      task.copyWith(
        status: VideoTaskStatus.cancelled,
        completedAt: DateTime.now(),
      ),
    );
    await _syncSessionCancelled(
      task.copyWith(
        status: VideoTaskStatus.cancelled,
        completedAt: DateTime.now(),
      ),
    );
    _ref
        .read(backgroundTaskProvider.notifier)
        .updateTask(
          id,
          description: '任务已取消',
          progress: 0,
          isComplete: true,
          onCancel: null,
        );
  }

  void _appendTask(VideoTask task) {
    state = [task, ...state];
  }

  void _replaceTask(VideoTask task) {
    state = [
      for (final item in state)
        if (item.id == task.id) task else item,
    ];
  }

  void _addBackgroundTask(VideoTask task) {
    _ref
        .read(backgroundTaskProvider.notifier)
        .addTask(
          BackgroundTask(
            id: task.id,
            title: task.type == VideoTaskType.t2v ? '文生视频' : '图生视频',
            description: '任务已提交',
            progress: 0,
            targetPageIndex: 2,
            onCancel: () {
              unawaited(cancelTask(task.id));
            },
          ),
        );
  }

  void _startPolling(
    VideoTask initialTask,
    VideoApiService service,
    _VideoServiceTarget target,
  ) {
    _pollTimers[initialTask.id]?.cancel();
    _pollTimers[initialTask.id] = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      try {
        final progress = await service.getTaskStatus(initialTask.id);
        final current = state
            .where((item) => item.id == initialTask.id)
            .firstOrNull;
        if (current == null) {
          timer.cancel();
          return;
        }
        var next = current.copyWith(
          currentStep: progress.currentStep,
          totalSteps: progress.totalSteps,
          etaSeconds: progress.etaSeconds,
        );

        switch (progress.status) {
          case 'queued':
            next = next.copyWith(status: VideoTaskStatus.queued);
            break;
          case 'running':
            next = next.copyWith(
              status: VideoTaskStatus.running,
              startedAt: current.startedAt ?? DateTime.now(),
            );
            break;
          case 'completed':
            timer.cancel();
            _pollTimers.remove(initialTask.id);
            next = next.copyWith(
              status: VideoTaskStatus.completed,
              completedAt: DateTime.now(),
            );
            final result = await service.getTaskResult(initialTask.id);
            final videoUrl =
                result['video_url']?.toString() ?? result['url']?.toString();
            if (videoUrl == null || videoUrl.isEmpty) {
              next = next.copyWith(
                status: VideoTaskStatus.failed,
                errorMessage: '任务已完成，但未返回视频地址',
              );
              _replaceTask(next);
              await _syncSessionFailure(next);
              _ref
                  .read(backgroundTaskProvider.notifier)
                  .updateTask(
                    next.id,
                    description: next.errorMessage,
                    isFailed: true,
                    error: next.errorMessage,
                    onCancel: null,
                  );
              return;
            }

            final fileService = _ref.read(fileServiceProvider);
            final fileName =
                '${DateTime.now().millisecondsSinceEpoch}_${next.type.name}_${next.params.resolution.replaceAll('*', 'x')}.mp4';
            final targetPath =
                '${fileService.getVideoOutputDirectory()}/$fileName';
            await service.downloadVideo(videoUrl, targetPath);
            final thumb = await fileService.generateVideoThumbnail(targetPath);
            next = next.copyWith(
              videoUrl: videoUrl,
              resultVideoPath: targetPath,
              fileSize: (result['file_size'] as num?)?.toInt(),
              seedUsed: (result['seed'] as num?)?.toInt(),
            );
            _replaceTask(next);
            final savedVideo = VideoItem(
              id: next.id,
              taskId: next.id,
              localPath: targetPath,
              fileName: fileName,
              fileSize: next.fileSize ?? File(targetPath).lengthSync(),
              resolution: next.params.resolution,
              prompt: next.params.prompt,
              thumbnailPath: thumb,
              type: next.type,
              nodeName: target.name,
              createdAt: next.createdAt,
              sourceImagePath: next.imagePath,
              paramsSnapshot: next.params,
            );
            await _ref.read(videoGalleryProvider.notifier).addVideo(savedVideo);
            await _syncSessionResult(next, savedVideo, statusText: '视频生成完成');
            _ref
                .read(backgroundTaskProvider.notifier)
                .updateTask(
                  next.id,
                  description: '视频已生成',
                  progress: 1,
                  isComplete: true,
                  onCancel: null,
                );
            return;
          case 'failed':
            timer.cancel();
            _pollTimers.remove(initialTask.id);
            final result = await service.getTaskResult(initialTask.id);
            next = next.copyWith(
              status: VideoTaskStatus.failed,
              completedAt: DateTime.now(),
              errorMessage:
                  result['error']?.toString() ??
                  result['message']?.toString() ??
                  '生成失败',
            );
            _replaceTask(next);
            await _syncSessionFailure(next);
            _ref
                .read(backgroundTaskProvider.notifier)
                .updateTask(
                  next.id,
                  description: next.errorMessage,
                  isFailed: true,
                  error: next.errorMessage,
                  onCancel: null,
                );
            return;
          case 'cancelled':
            timer.cancel();
            _pollTimers.remove(initialTask.id);
            next = next.copyWith(
              status: VideoTaskStatus.cancelled,
              completedAt: DateTime.now(),
            );
            _replaceTask(next);
            await _syncSessionCancelled(next);
            _ref
                .read(backgroundTaskProvider.notifier)
                .updateTask(
                  next.id,
                  description: '任务已取消',
                  isComplete: true,
                  onCancel: null,
                );
            return;
        }

        _replaceTask(next);
        _ref
            .read(backgroundTaskProvider.notifier)
            .updateTask(
              next.id,
              description: _buildTaskDescription(progress),
              progress: progress.percentage <= 0
                  ? 0
                  : progress.percentage / 100,
              onCancel: () {
                unawaited(cancelTask(next.id));
              },
            );
      } catch (e) {
        timer.cancel();
        _pollTimers.remove(initialTask.id);
        final current = state
            .where((item) => item.id == initialTask.id)
            .firstOrNull;
        if (current != null) {
          final failed = current.copyWith(
            status: VideoTaskStatus.failed,
            completedAt: DateTime.now(),
            errorMessage: e.toString(),
          );
          _replaceTask(failed);
          await _syncSessionFailure(failed);
          _ref
              .read(backgroundTaskProvider.notifier)
              .updateTask(
                failed.id,
                description: failed.errorMessage,
                isFailed: true,
                error: failed.errorMessage,
                onCancel: null,
              );
        }
      }
    });
  }

  _VideoServiceTarget _selectTarget(String? targetNodeId) {
    final nodes = _ref.read(videoNodesProvider);
    if (targetNodeId != null) {
      if (targetNodeId == 'local-7861') {
        return _localBridgeTarget();
      }
      if (targetNodeId == 'default-video-api') {
        final directTarget = _resolveDefaultVideoTarget();
        if (directTarget != null) {
          return directTarget;
        }
      }
      final explicit = nodes
          .where((node) => node.id == targetNodeId)
          .firstOrNull;
      if (explicit != null) {
        return _toTarget(explicit);
      }
    }

    final defaultNode = nodes.where((node) => node.isDefault).firstOrNull;
    if (defaultNode != null && defaultNode.isOnline) {
      return _toTarget(defaultNode);
    }

    final firstOnline = nodes.where((node) => node.isOnline).firstOrNull;
    if (firstOnline != null) {
      return _toTarget(firstOnline);
    }

    final defaultVideoTarget = _resolveDefaultVideoTarget();
    if (defaultVideoTarget != null) {
      return defaultVideoTarget;
    }

    return _localBridgeTarget();
  }

  _VideoServiceTarget? _resolveTarget(String id) {
    if (id == 'local-7861') {
      return _localBridgeTarget();
    }
    if (id == 'default-video-api') {
      return _resolveDefaultVideoTarget();
    }
    final node = _ref
        .read(videoNodesProvider)
        .where((node) => node.id == id)
        .firstOrNull;
    return node == null ? null : _toTarget(node);
  }

  _VideoServiceTarget _localBridgeTarget() {
    final bridge = _ref.read(videoSettingsProvider).wan2gp;
    return _VideoServiceTarget(
      id: 'local-7861',
      name: '本地7861桥接',
      apiUrl: 'http://127.0.0.1:${bridge.port}',
    );
  }

  _VideoServiceTarget? _resolveDefaultVideoTarget() {
    final config = _ref
        .read(apiConfigsProvider)
        .where((item) => item.type == 'video' && item.isDefault)
        .firstOrNull;
    final url = config?.url.trim() ?? '';
    if (url.isEmpty) {
      return null;
    }
    return _VideoServiceTarget(
      id: 'default-video-api',
      name: config!.name,
      apiUrl: url,
      apiKey: config.key.trim(),
    );
  }

  _VideoServiceTarget _toTarget(ComputeNode node) {
    return _VideoServiceTarget(
      id: node.id,
      name: node.name,
      apiUrl: node.effectiveApiUrl,
    );
  }

  VideoGenerateParams _normalizeParamsForTarget(
    VideoGenerateParams params,
    _VideoServiceTarget target,
  ) {
    final apiUrl = target.apiUrl.toLowerCase();
    if (!apiUrl.contains('/open/api/video')) {
      return params;
    }

    final directModel = _ref
        .read(apiConfigsProvider)
        .where((item) => item.type == 'video' && item.isDefault)
        .firstOrNull
        ?.model
        .trim();
    if (directModel == null || directModel.isEmpty) {
      return params;
    }

    final currentModel = params.modelName.trim();
    final looksLikeWan2gp = currentModel.isEmpty ||
        RegExp(
          r'(?:^|[-_])(t2v|i2v|wan|a14b|14b)',
          caseSensitive: false,
        ).hasMatch(currentModel);
    if (!looksLikeWan2gp && currentModel != directModel) {
      return params;
    }

    return params.copyWith(modelName: directModel, taskType: directModel);
  }

  String _buildTaskDescription(VideoTaskProgress progress) {
    if (progress.status == 'queued') {
      return progress.queuePosition > 0
          ? '排队中，第 ${progress.queuePosition} 位'
          : '排队中';
    }
    if (progress.status == 'running') {
      if (progress.totalSteps > 0) {
        return '生成中 ${progress.currentStep}/${progress.totalSteps}';
      }
      return '生成中';
    }
    return progress.status;
  }

  Future<_SessionBinding?> _createSessionMessages({
    required String prompt,
    required String imagePath,
    required String taskId,
    required String modelName,
    required String resolution,
  }) async {
    final session = _ref.read(currentSessionProvider);
    if (session == null) return null;

    final notifier = _ref.read(currentSessionProvider.notifier);
    final userMessage = Message(
      type: 'user',
      text: prompt,
      images: const [],
      params: {
        'prompt': prompt,
        'referenceImages': [imagePath],
        'mediaType': 'image',
      },
    );
    await notifier.addMessage(userMessage);

    final assistantMessage = Message(
      type: 'assistant',
      text: '视频生成中...',
      images: const [],
      videos: const [],
      params: {
        'prompt': prompt,
        'taskId': taskId,
        'sourceImagePath': imagePath,
        'mediaType': 'video',
        'status': 'running',
        'model': modelName,
        'resolution': resolution,
      },
    );
    await notifier.addMessage(assistantMessage);
    return _SessionBinding(
      sessionName: session.name,
      assistantMessageId: assistantMessage.id,
    );
  }

  Future<_SessionBinding?> _createT2vSessionMessages({
    required String prompt,
    required String taskId,
    required String modelName,
    required String resolution,
  }) async {
    final session = _ref.read(currentSessionProvider);
    if (session == null) return null;

    final notifier = _ref.read(currentSessionProvider.notifier);
    final userMessage = Message(
      type: 'user',
      text: prompt,
      images: const [],
      params: {'prompt': prompt, 'mediaType': 'video', 'videoMode': 't2v'},
    );
    await notifier.addMessage(userMessage);

    final assistantMessage = Message(
      type: 'assistant',
      text: '视频生成中...',
      images: const [],
      videos: const [],
      params: {
        'prompt': prompt,
        'taskId': taskId,
        'mediaType': 'video',
        'videoMode': 't2v',
        'status': 'running',
        'model': modelName,
        'resolution': resolution,
      },
    );
    await notifier.addMessage(assistantMessage);
    return _SessionBinding(
      sessionName: session.name,
      assistantMessageId: assistantMessage.id,
    );
  }

  Future<void> _syncSessionResult(
    VideoTask task,
    VideoItem item, {
    required String statusText,
  }) async {
    if (task.sessionName == null || task.sessionMessageId == null) return;
    final notifier = _ref.read(currentSessionProvider.notifier);
    final currentSession = _ref.read(currentSessionProvider);
    final message = Message(
      id: task.sessionMessageId,
      type: 'assistant',
      text: statusText,
      images: const [],
      videos: [item.localPath],
      params: {
        'prompt': task.params.prompt,
        'taskId': task.id,
        'videoItemId': item.id,
        'sourceImagePath': item.sourceImagePath,
        'mediaType': 'video',
        'status': 'completed',
        'model': task.params.modelName,
        'resolution': item.resolution,
      },
    );
    if (currentSession?.name == task.sessionName) {
      await notifier.updateMessageById(task.sessionMessageId!, message);
      return;
    }
    final sessionService = _ref.read(sessionServiceProvider);
    final session = await sessionService.loadSession(task.sessionName!);
    if (session == null) return;
    final index = session.messages.indexWhere(
      (msg) => msg.id == task.sessionMessageId,
    );
    if (index == -1) return;
    final messages = List<Message>.from(session.messages);
    messages[index] = message;
    await sessionService.saveSession(
      Session(name: session.name, created: session.created, messages: messages),
    );
  }

  Future<void> _syncSessionFailure(VideoTask task) async {
    if (task.sessionName == null || task.sessionMessageId == null) return;
    await _syncSessionStatus(
      task,
      text: '视频生成失败: ${task.errorMessage ?? "未知错误"}',
      status: 'failed',
    );
  }

  Future<void> _syncSessionCancelled(VideoTask task) async {
    if (task.sessionName == null || task.sessionMessageId == null) return;
    await _syncSessionStatus(task, text: '视频任务已取消', status: 'cancelled');
  }

  Future<void> _syncSessionStatus(
    VideoTask task, {
    required String text,
    required String status,
  }) async {
    final notifier = _ref.read(currentSessionProvider.notifier);
    final currentSession = _ref.read(currentSessionProvider);
    final message = Message(
      id: task.sessionMessageId,
      type: 'assistant',
      text: text,
      images: const [],
      params: {
        'prompt': task.params.prompt,
        'taskId': task.id,
        'sourceImagePath': task.imagePath,
        'mediaType': 'video',
        'status': status,
        'model': task.params.modelName,
        'resolution': task.params.resolution,
      },
    );
    if (currentSession?.name == task.sessionName) {
      await notifier.updateMessageById(task.sessionMessageId!, message);
      return;
    }
    final sessionService = _ref.read(sessionServiceProvider);
    final session = await sessionService.loadSession(task.sessionName!);
    if (session == null) return;
    final index = session.messages.indexWhere(
      (msg) => msg.id == task.sessionMessageId,
    );
    if (index == -1) return;
    final messages = List<Message>.from(session.messages);
    messages[index] = message;
    await sessionService.saveSession(
      Session(name: session.name, created: session.created, messages: messages),
    );
  }
}

class _SessionBinding {
  final String sessionName;
  final String assistantMessageId;

  const _SessionBinding({
    required this.sessionName,
    required this.assistantMessageId,
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 后台任务状态
class BackgroundTask {
  final String id;
  final String title;
  final String description;
  final double progress; // 0.0 ~ 1.0
  final bool isComplete;
  final bool isFailed;
  final String? error;
  final int? targetPageIndex; // 点击任务时跳转的页面索引
  final VoidCallback? onTap; // 自定义点击回调
  final VoidCallback? onCancel; // 取消任务回调

  BackgroundTask({
    required this.id,
    required this.title,
    this.description = '',
    this.progress = 0.0,
    this.isComplete = false,
    this.isFailed = false,
    this.error,
    this.targetPageIndex,
    this.onTap,
    this.onCancel,
  });

  BackgroundTask copyWith({
    String? title,
    String? description,
    double? progress,
    bool? isComplete,
    bool? isFailed,
    String? error,
    int? targetPageIndex,
    VoidCallback? onTap,
    VoidCallback? onCancel,
  }) {
    return BackgroundTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      progress: progress ?? this.progress,
      isComplete: isComplete ?? this.isComplete,
      isFailed: isFailed ?? this.isFailed,
      error: error ?? this.error,
      targetPageIndex: targetPageIndex ?? this.targetPageIndex,
      onTap: onTap ?? this.onTap,
      onCancel: onCancel ?? this.onCancel,
    );
  }
}

class BackgroundTaskNotifier extends StateNotifier<List<BackgroundTask>> {
  BackgroundTaskNotifier() : super([]);

  void addTask(BackgroundTask task) {
    // 防止重复添加同ID任务
    if (state.any((t) => t.id == task.id)) return;
    state = [...state, task];
  }

  void updateTask(
    String id, {
    String? description,
    double? progress,
    bool? isComplete,
    bool? isFailed,
    String? error,
    VoidCallback? onCancel,
  }) {
    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(
          description: description,
          progress: progress,
          isComplete: isComplete,
          isFailed: isFailed,
          error: error,
          onCancel: onCancel,
        );
      }
      return t;
    }).toList();
  }

  void removeTask(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  bool hasActiveTask(String idPrefix) {
    return state.any(
      (t) => t.id.startsWith(idPrefix) && !t.isComplete && !t.isFailed,
    );
  }

  void clearCompleted() {
    state = state.where((t) => !t.isComplete && !t.isFailed).toList();
  }
}

final backgroundTaskProvider =
    StateNotifierProvider<BackgroundTaskNotifier, List<BackgroundTask>>((ref) {
      return BackgroundTaskNotifier();
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shot.dart';

/// 匹配任务的全局状态，用于支持最小化后恢复对话框
class MatchingTaskState {
  final String taskId;
  final int currentIndex;
  final int totalShots;
  final String currentThinking;
  final bool isRunning;
  final bool isMinimized;
  final List<Shot> shots;
  final List<int>? originalIndices;

  const MatchingTaskState({
    required this.taskId,
    required this.currentIndex,
    required this.totalShots,
    required this.currentThinking,
    required this.isRunning,
    required this.isMinimized,
    required this.shots,
    this.originalIndices,
  });

  MatchingTaskState copyWith({
    String? taskId,
    int? currentIndex,
    int? totalShots,
    String? currentThinking,
    bool? isRunning,
    bool? isMinimized,
    List<Shot>? shots,
    List<int>? originalIndices,
  }) {
    return MatchingTaskState(
      taskId: taskId ?? this.taskId,
      currentIndex: currentIndex ?? this.currentIndex,
      totalShots: totalShots ?? this.totalShots,
      currentThinking: currentThinking ?? this.currentThinking,
      isRunning: isRunning ?? this.isRunning,
      isMinimized: isMinimized ?? this.isMinimized,
      shots: shots ?? this.shots,
      originalIndices: originalIndices ?? this.originalIndices,
    );
  }
}

class MatchingTaskNotifier extends StateNotifier<MatchingTaskState?> {
  MatchingTaskNotifier() : super(null);

  void startTask({
    required String taskId,
    required int totalShots,
    required List<Shot> shots,
    List<int>? originalIndices,
  }) {
    state = MatchingTaskState(
      taskId: taskId,
      currentIndex: 0,
      totalShots: totalShots,
      currentThinking: '',
      isRunning: true,
      isMinimized: false,
      shots: shots,
      originalIndices: originalIndices,
    );
  }

  void updateProgress(int index, String thinking) {
    if (state == null) return;
    state = state!.copyWith(
      currentIndex: index,
      currentThinking: thinking,
    );
  }

  void updateThinking(String thinking) {
    if (state == null) return;
    state = state!.copyWith(currentThinking: thinking);
  }

  void minimize() {
    if (state == null) return;
    state = state!.copyWith(isMinimized: true);
  }

  void restore() {
    if (state == null) return;
    state = state!.copyWith(isMinimized: false);
  }

  void complete() {
    if (state == null) return;
    state = state!.copyWith(isRunning: false);
  }

  void clear() {
    state = null;
  }
}

final matchingTaskProvider =
    StateNotifierProvider<MatchingTaskNotifier, MatchingTaskState?>((ref) {
  return MatchingTaskNotifier();
});

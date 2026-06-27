import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/background_task_provider.dart';

/// 悬浮在底部的后台任务进度条
class BackgroundTaskBar extends ConsumerWidget {
  const BackgroundTaskBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(backgroundTaskProvider);
    final activeTasks = tasks.where((t) => !t.isComplete && !t.isFailed).toList();
    final completedTasks = tasks.where((t) => t.isComplete || t.isFailed).toList();

    if (tasks.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 20,
      bottom: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF2a2a2a),
        child: Container(
          width: 360,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF3a3a3a))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.task_alt, color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text('后台任务 (${activeTasks.length}进行中)',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (completedTasks.isNotEmpty)
                      InkWell(
                        onTap: () => ref.read(backgroundTaskProvider.notifier).clearCompleted(),
                        child: const Text('清除已完成', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ),
                  ],
                ),
              ),
              // 任务列表
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _buildTaskItem(context, ref, task);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskItem(BuildContext context, WidgetRef ref, BackgroundTask task) {
    final Color statusColor;
    final IconData statusIcon;
    if (task.isFailed) {
      statusColor = Colors.red;
      statusIcon = Icons.error_outline;
    } else if (task.isComplete) {
      statusColor = const Color(0xFF4CAF50);
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = AppColors.primary;
      statusIcon = Icons.hourglass_top;
    }

    final bool canTap = task.onTap != null || task.targetPageIndex != null;

    return InkWell(
      onTap: canTap ? () {
        if (task.onTap != null) {
          task.onTap!();
        }
      } : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(task.title,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (task.isComplete || task.isFailed)
                  InkWell(
                    onTap: () => ref.read(backgroundTaskProvider.notifier).removeTask(task.id),
                    child: const Icon(Icons.close, color: Colors.white30, size: 14),
                  ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(task.description,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (!task.isComplete && !task.isFailed) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  backgroundColor: Colors.white12,
                  color: statusColor,
                  minHeight: 4,
                ),
              ),
              if (task.progress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${(task.progress * 100).toInt()}%',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
                ),
            ],
            if (task.isFailed && task.error != null) ...[
              const SizedBox(height: 4),
              Text(task.error!, style: const TextStyle(color: Colors.red, fontSize: 10),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (canTap && !task.isComplete && !task.isFailed) ...[
              const SizedBox(height: 4),
              const Text('点击查看进度', style: TextStyle(color: AppColors.primary, fontSize: 9)),
            ],
          ],
        ),
      ),
    );
  }
}

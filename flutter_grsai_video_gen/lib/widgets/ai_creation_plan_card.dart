import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AiCreationPlanCard extends StatelessWidget {
  final Map<String, dynamic> executionPlan;

  const AiCreationPlanCard({super.key, required this.executionPlan});

  @override
  Widget build(BuildContext context) {
    final mode = executionPlan['mode']?.toString() ?? 'image_generate';
    final prompt = executionPlan['prompt']?.toString() ?? '';
    final tasks = _readTasks(executionPlan['imageTasks']);
    final totalCount = tasks.fold<int>(
      0,
      (sum, task) => sum + _readInt(task['batchCount'], 1).clamp(1, 99).toInt(),
    );

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.route_outlined,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '执行计划',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _chip(_modeLabel(mode)),
              if (totalCount > 0) ...[
                const SizedBox(width: 6),
                _chip('$totalCount 张'),
              ],
            ],
          ),
          if (prompt.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              prompt,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                height: 1.45,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          if (tasks.isEmpty)
            const Text(
              '等待素材或下一步指令',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            Column(
              children: tasks
                  .take(4)
                  .map((task) => _taskRow(task))
                  .toList(growable: false),
            ),
          if (tasks.length > 4) ...[
            const SizedBox(height: 6),
            Text(
              '还有 ${tasks.length - 4} 个任务将在后台继续执行',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _taskRow(Map<String, dynamic> task) {
    final angle = task['angleLabel']?.toString() ?? '';
    final operation = task['operation']?.toString() ?? 'image_generate';
    final prompt = task['prompt']?.toString() ?? '';
    final refs = _readStringList(task['referenceImageIds']);
    final query = task['referenceQuery']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            operation == 'image_edit'
                ? Icons.auto_fix_high_outlined
                : Icons.image_outlined,
            color: AppColors.primary,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      angle.trim().isEmpty ? _operationLabel(operation) : angle,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (refs.isNotEmpty || query.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _chip(refs.isNotEmpty ? '参考图 ${refs.length}' : '待匹配参考'),
                    ],
                  ],
                ),
                if (prompt.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    prompt,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.primary, fontSize: 11),
      ),
    );
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case 'image_edit':
        return '图片续创';
      case 'multi_angle':
        return '多角度';
      case 'storyboard':
        return '分镜';
      default:
        return '图片生成';
    }
  }

  static String _operationLabel(String operation) {
    return operation == 'image_edit' ? '图片修改' : '图片生成';
  }

  static List<Map<String, dynamic>> _readTasks(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  static int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}

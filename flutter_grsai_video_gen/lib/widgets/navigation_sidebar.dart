import '../constants/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../providers/background_task_provider.dart';
import '../providers/matching_task_provider.dart';

class NavigationSidebar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const NavigationSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  ConsumerState<NavigationSidebar> createState() => _NavigationSidebarState();
}

class _NavigationSidebarState extends ConsumerState<NavigationSidebar> {
  bool _isExpanded = true;
  bool _taskPanelExpanded = false;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(backgroundTaskProvider);
    final activeTasks = tasks
        .where((t) => !t.isComplete && !t.isFailed)
        .toList();
    final hasActiveTasks = activeTasks.isNotEmpty;
    final hasTasks = tasks.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _isExpanded ? AppSizes.navbarExpanded : AppSizes.navbarCollapsed,
      decoration: const BoxDecoration(
        color: AppColors.navbar,
        border: Border(right: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        children: [
          _buildToggleButton(),
          _buildNavItem(0, '🖼️', '图片生成'),
          _buildNavItem(1, '🎨', '影视工坊'),
          _buildNavItem(2, '🎬', '视频生成'),
          _buildNavItem(3, '📦', '影视资产库'),
          _buildNavItem(4, '🖼️', '分镜图管理'),
          _buildNavItem(5, '📁', '作品管理'),
          _buildNavItem(6, '🔧', 'API配置'),
          _buildNavItem(7, '⚙️', '设置'),
          _buildNavItem(8, 'ℹ️', '关于绘云AI'),
          // 后台任务区域
          if (hasTasks) _buildTaskSection(tasks, activeTasks, hasActiveTasks),
          const Spacer(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        padding: const EdgeInsets.all(15),
        alignment: Alignment.centerLeft,
        child: const Text(
          '☰',
          style: TextStyle(color: AppColors.text, fontSize: 20),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String icon, String label) {
    final isSelected = widget.selectedIndex == index;
    return InkWell(
      onTap: () => widget.onItemSelected(index),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _isExpanded ? 20 : 15,
          vertical: 15,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.hover : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: _isExpanded
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            if (_isExpanded) ...[
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 后台任务区域
  Widget _buildTaskSection(
    List<BackgroundTask> tasks,
    List<BackgroundTask> activeTasks,
    bool hasActiveTasks,
  ) {
    final completedTasks = tasks
        .where((t) => t.isComplete || t.isFailed)
        .toList();

    return Column(
      children: [
        const Divider(color: AppColors.border1, height: 1),
        // 折叠按钮
        InkWell(
          onTap: () => setState(() => _taskPanelExpanded = !_taskPanelExpanded),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: _isExpanded ? 20 : 15,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: _isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                // 带脉冲效果的图标
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _taskPanelExpanded ? Icons.expand_less : Icons.task_alt,
                      color: hasActiveTasks
                          ? AppColors.primary
                          : const Color(0xFF4CAF50),
                      size: 20,
                    ),
                    if (hasActiveTasks)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.navbar,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${activeTasks.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_isExpanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasActiveTasks ? '${activeTasks.length}个任务运行中' : '任务已完成',
                      style: TextStyle(
                        color: hasActiveTasks
                            ? AppColors.primary
                            : const Color(0xFF4CAF50),
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _taskPanelExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        ),
        // 展开的任务列表
        if (_taskPanelExpanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: const BoxDecoration(
              color: Color(0xFF1a1a1a),
              border: Border(top: BorderSide(color: AppColors.border1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 清除已完成按钮
                if (completedTasks.isNotEmpty)
                  InkWell(
                    onTap: () => ref
                        .read(backgroundTaskProvider.notifier)
                        .clearCompleted(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      width: double.infinity,
                      child: Text(
                        '清除已完成 (${completedTasks.length})',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                // 任务列表
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) =>
                        _buildTaskItem(tasks[index]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTaskItem(BackgroundTask task) {
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

    final bool canTap = task.targetPageIndex != null || task.onTap != null;

    void handleTap() {
      // 匹配任务：先跳转到影视工坊页面，再恢复对话框
      if (task.id.startsWith('match_') && !task.isComplete && !task.isFailed) {
        if (task.targetPageIndex != null) {
          widget.onItemSelected(task.targetPageIndex!);
        }
        ref.read(matchingTaskProvider.notifier).restore();
        return;
      }
      if (task.onTap != null) {
        task.onTap!();
      } else if (task.targetPageIndex != null) {
        widget.onItemSelected(task.targetPageIndex!);
      }
    }

    if (!_isExpanded) {
      return Tooltip(
        message: '${task.title}: ${task.description}',
        child: InkWell(
          onTap: canTap ? handleTap : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a2a),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(statusIcon, color: statusColor, size: 14),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onTap: canTap ? handleTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF2a2a2a),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 12),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!task.isComplete && !task.isFailed && task.onCancel != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: task.onCancel,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (task.isComplete || task.isFailed)
                  InkWell(
                    onTap: () => ref
                        .read(backgroundTaskProvider.notifier)
                        .removeTask(task.id),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white30,
                      size: 12,
                    ),
                  ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                task.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (!task.isComplete && !task.isFailed) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: task.progress > 0 ? task.progress : null,
                  backgroundColor: Colors.white12,
                  color: statusColor,
                  minHeight: 3,
                ),
              ),
            ],
            if (task.isFailed && task.error != null) ...[
              const SizedBox(height: 2),
              Text(
                task.error!,
                style: const TextStyle(color: Colors.red, fontSize: 8),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (canTap && !task.isComplete && !task.isFailed) ...[
              const SizedBox(height: 2),
              const Text(
                '点击跳转',
                style: TextStyle(color: AppColors.primary, fontSize: 8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(15),
      child: _isExpanded
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appReleaseVersion,
                  style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                ),
                SizedBox(height: 4),
                Text(
                  'Leo.j 开发出品',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

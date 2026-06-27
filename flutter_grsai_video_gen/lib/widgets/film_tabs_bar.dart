import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/film_project_provider.dart';

class FilmTabsBar extends ConsumerWidget {
  const FilmTabsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectState = ref.watch(filmProjectProvider);
    final project = projectState.currentProject;

    if (project == null || project.tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 48,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: project.tabs.length,
              onReorder: (oldIndex, newIndex) => ref.read(filmProjectProvider.notifier).reorderTabs(oldIndex, newIndex),
              buildDefaultDragHandles: false,
              itemBuilder: (context, index) {
                final tab = project.tabs[index];
                final isActive = tab.id == project.currentTabId;

                return ReorderableDragStartListener(
                  key: ValueKey(tab.id),
                  index: index,
                  child: GestureDetector(
                    onTap: () => ref.read(filmProjectProvider.notifier).switchTab(tab.id),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tab.name,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                          if (project.tabs.length > 1) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => ref.read(filmProjectProvider.notifier).removeTab(tab.id),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: isActive ? Colors.white : Colors.white54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _showAddTabDialog(context, ref),
            tooltip: '添加标签页',
          ),
        ],
      ),
    );
  }

  void _showAddTabDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建标签页'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入标签页名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(filmProjectProvider.notifier).addTab(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

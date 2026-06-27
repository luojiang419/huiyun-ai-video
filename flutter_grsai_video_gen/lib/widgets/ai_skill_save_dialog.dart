import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/ai_assistant_provider.dart';

class AiSkillSaveDialog extends ConsumerStatefulWidget {
  const AiSkillSaveDialog({super.key});

  @override
  ConsumerState<AiSkillSaveDialog> createState() =>
      _AiSkillSaveDialogState();
}

class _AiSkillSaveDialogState extends ConsumerState<AiSkillSaveDialog> {
  final _nameController = TextEditingController();
  String _selectedCategory = '自定义';
  final List<String> _categories = [
    '影视制作',
    '人物肖像',
    '场景概念',
    '商业摄影',
    '自然风光',
    '艺术风格',
    '特殊场景',
    '自定义',
  ];
  List<String> _suggestedTags = [];
  final List<String> _selectedTags = [];

  @override
  void initState() {
    super.initState();
    // auto-suggest name from last prompt
    final state = ref.read(aiAssistantProvider);
    final prompt = state.lastOriginalPrompt ?? '';
    if (prompt.isNotEmpty) {
      _nameController.text = prompt.length > 20
          ? '${prompt.substring(0, 20)}...'
          : prompt;
      _suggestTags(prompt);
    }
  }

  void _suggestTags(String prompt) {
    final tagKeywords = {
      '科幻': ['科幻', '未来', '赛博', '科技', '太空'],
      '城市': ['城市', '建筑', '街道', '都市', '楼'],
      '夜景': ['夜景', '夜', '灯光', '霓虹', '月亮'],
      '人物': ['人', '女孩', '男孩', '男', '女', '角色', '肖像'],
      '自然': ['自然', '山', '水', '海', '森林', '天空', '花'],
      '电影': ['电影', '影视', '画面', '镜头', '景'],
      '美食': ['美食', '食物', '料理', '甜品'],
      '动物': ['动物', '猫', '狗', '鸟', '鱼'],
    };

    final lower = prompt.toLowerCase();
    for (final entry in tagKeywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) {
          if (!_suggestedTags.contains(entry.key)) {
            _suggestedTags.add(entry.key);
          }
          break;
        }
      }
    }

    if (_suggestedTags.isEmpty) {
      _suggestedTags = ['通用'];
    }
    _selectedTags.addAll(_suggestedTags);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📚 保存为技能',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // name field
            const Text(
              '技能名称：',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.primary),
                ),
                hintText: '输入技能名称...',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.5)),
              ),
            ),
            const SizedBox(height: 16),

            // category
            const Text(
              '选择分类：',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _categories.map((cat) {
                final selected = cat == _selectedCategory;
                return InkWell(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withOpacity(0.2)
                          : AppColors.inputBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border2,
                      ),
                    ),
                    child: Text(
                      cat,
                      style: TextStyle(
                        color:
                            selected ? AppColors.primary : AppColors.text,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // tags
            const Text(
              '标签（点击选择/取消）：',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _suggestedTags.map((tag) {
                final selected = _selectedTags.contains(tag);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedTags.remove(tag);
                      } else {
                        _selectedTags.add(tag);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.border2,
                      ),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color:
                            selected ? AppColors.primary : AppColors.text,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    '跳过',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty) return;
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('💾 保存技能'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

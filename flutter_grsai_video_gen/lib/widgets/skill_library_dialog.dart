import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../models/skill.dart';
import '../providers/ai_assistant_provider.dart';

class SkillLibraryDialog extends ConsumerStatefulWidget {
  const SkillLibraryDialog({super.key});

  @override
  ConsumerState<SkillLibraryDialog> createState() =>
      _SkillLibraryDialogState();
}

class _SkillLibraryDialogState extends ConsumerState<SkillLibraryDialog> {
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final skills = ref.watch(skillListProvider);

    final builtinSkills =
        skills.where((s) => s.source == 'builtin').toList();
    final userSkills = skills.where((s) => s.source == 'user').toList();

    var filteredBuiltin = builtinSkills;
    var filteredUser = userSkills;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filteredBuiltin = builtinSkills
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.tags.any((t) => t.toLowerCase().contains(q)) ||
              s.category.toLowerCase().contains(q))
          .toList();
      filteredUser = userSkills
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.tags.any((t) => t.toLowerCase().contains(q)))
          .toList();
    }

    if (_selectedCategory != null) {
      filteredBuiltin = builtinSkills
          .where((s) => s.category == _selectedCategory)
          .toList();
      filteredUser =
          userSkills.where((s) => s.category == _selectedCategory).toList();
    }

    return Dialog(
      backgroundColor: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Row(
              children: [
                const Text(
                  '📚 技能库',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // search bar
            TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 18),
                hintText: '搜索技能...',
                hintStyle: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.border2),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            const SizedBox(height: 8),

            // category filter
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _categoryChip('全部', null),
                  _categoryChip('🎬 影视制作', '影视制作'),
                  _categoryChip('👤 人物肖像', '人物肖像'),
                  _categoryChip('🏙️ 场景概念', '场景概念'),
                  _categoryChip('📷 商业摄影', '商业摄影'),
                  _categoryChip('🏔️ 自然风光', '自然风光'),
                  _categoryChip('🎨 艺术风格', '艺术风格'),
                  _categoryChip('⚡ 特殊场景', '特殊场景'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // skill list
            Expanded(
              child: ListView(
                children: [
                  if (filteredBuiltin.isNotEmpty) ...[
                    _sectionHeader(
                        '内置专业技能（${filteredBuiltin.length}项）'),
                    const SizedBox(height: 6),
                    ...filteredBuiltin
                        .map((s) => _skillCard(s, isBuiltin: true)),
                  ],
                  if (filteredUser.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _sectionHeader(
                        '我的学习成果（${filteredUser.length}项）'),
                    const SizedBox(height: 6),
                    ...filteredUser
                        .map((s) => _skillCard(s, isBuiltin: false)),
                  ],
                  if (filteredBuiltin.isEmpty && filteredUser.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Text(
                          '没有找到匹配的技能',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChip(String label, String? category) {
    final selected = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () =>
            setState(() => _selectedCategory = selected ? null : category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primary.withOpacity(0.2) : AppColors.inputBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? AppColors.primary : AppColors.border2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      '── $title ──',
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
      ),
    );
  }

  Widget _skillCard(Skill skill, {required bool isBuiltin}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          // icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child:
                  Text(skill.icon, style: const TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 10),

          // info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${skill.category} · 使用${skill.usageCount}次 · ⭐${skill.rating}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // tags
          if (skill.tags.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Wrap(
                spacing: 4,
                children: skill.tags.take(3).map((t) {
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                  );
                }).toList(),
              ),
            ),

          // delete button for user skills
          if (!isBuiltin)
            IconButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF2A2A2A),
                    title: const Text('删除技能',
                        style: TextStyle(color: AppColors.text)),
                    content: Text('确定删除技能「${skill.name}」吗？',
                        style: const TextStyle(color: AppColors.textSecondary)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消',
                            style:
                                TextStyle(color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('删除',
                            style: TextStyle(color: Color(0xFFEF5350))),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref
                      .read(skillListProvider.notifier)
                      .deleteUserSkill(skill.id);
                }
              },
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textSecondary, size: 18),
              tooltip: '删除',
            ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../models/prompt_rule.dart';
import '../services/prompt_rule_service.dart';
import '../providers/generate_provider.dart';

class PromptRuleConfig extends ConsumerStatefulWidget {
  const PromptRuleConfig({super.key});

  @override
  ConsumerState<PromptRuleConfig> createState() => _PromptRuleConfigState();
}

class _PromptRuleConfigState extends ConsumerState<PromptRuleConfig> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PromptRuleService _service;
  List<PromptRule> _rules = [];
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _service = PromptRuleService(ref.read(apiServiceProvider));
    _rules = _service.getAllRules();
    _tabController = TabController(length: _rules.length, vsync: this);
    _loadRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    for (var rule in _rules) {
      final content = await _service.loadRuleContent(rule.id);
      rule.content = content;
      _controllers[rule.id] = TextEditingController(text: content);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveRule(String ruleId) async {
    final controller = _controllers[ruleId];
    if (controller == null) return;

    try {
      await _service.saveRuleContent(ruleId, controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  Future<void> _resetRule(String ruleId) async {
    final rule = _rules.firstWhere((r) => r.id == ruleId);

    final defaultContent = await _service.loadRuleContent(ruleId);
    final file = File(rule.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认重置', style: TextStyle(color: AppColors.text)),
        content: const Text('确定要重置为默认规则吗？当前修改将丢失。', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _controllers[ruleId]?.text = defaultContent;
      await _saveRule(ruleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI规则配置', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: _rules.map((rule) => Tab(text: rule.name)).toList(),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _rules.map((rule) => _buildRuleEditor(rule)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleEditor(PromptRule rule) {
    final controller = _controllers[rule.id];
    if (controller == null) return const SizedBox();

    return Column(
      children: [
        Row(
          children: [
            Text('文件路径: ${rule.filePath}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _resetRule(rule.id),
              icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
              label: const Text('重置为默认', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _saveRule(rule.id),
              icon: const Icon(Icons.save, size: 16),
              label: const Text('保存'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontFamily: 'monospace'),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.border2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

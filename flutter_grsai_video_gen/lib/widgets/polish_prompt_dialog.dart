import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';
import '../services/config_file_service.dart';

class PolishPromptDialog extends ConsumerStatefulWidget {
  final String originalPrompt;
  final Function(String) onSelect;

  const PolishPromptDialog({
    super.key,
    required this.originalPrompt,
    required this.onSelect,
  });

  @override
  ConsumerState<PolishPromptDialog> createState() => _PolishPromptDialogState();
}

class _PolishPromptDialogState extends ConsumerState<PolishPromptDialog> {
  List<String> _suggestions = [];
  String? _selectedSuggestion;
  bool _loading = false;
  final _modifyController = TextEditingController();
  String? _selectedAiConfig;
  String _systemPrompt = '';

  @override
  void initState() {
    super.initState();
    _initializeDefaultConfig();
    _loadSystemPrompt();
  }

  void _initializeDefaultConfig() {
    final configs = ref.read(apiConfigsProvider);
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isNotEmpty) {
      final defaultConfig = chatConfigs.firstWhere((c) => c.isDefault, orElse: () => chatConfigs.first);
      _selectedAiConfig = defaultConfig.id;
    }
  }

  Future<void> _loadSystemPrompt() async {
    final configService = ConfigFileService();
    _systemPrompt = await configService.loadSystemPrompt();
    _polishPrompt();
  }

  @override
  void dispose() {
    _modifyController.dispose();
    super.dispose();
  }

  Future<void> _polishPrompt({String? modifyRequest}) async {
    setState(() => _loading = true);

    try {
      final configs = ref.read(apiConfigsProvider);
      final chatConfigs = configs.where((c) => c.type == 'chat').toList();

      if (chatConfigs.isEmpty) {
        setState(() => _loading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先配置AI助手')),
          );
        }
        return;
      }

      final defaultConfig = _selectedAiConfig != null
          ? chatConfigs.firstWhere((c) => c.id == _selectedAiConfig, orElse: () => chatConfigs.first)
          : chatConfigs.firstWhere((c) => c.isDefault, orElse: () => chatConfigs.first);

      String systemPrompt;
      String promptToUse;

      if (modifyRequest != null && _selectedSuggestion != null) {
        systemPrompt = '$_systemPrompt\n\n用户选中了以下提示词：\n"$_selectedSuggestion"\n\n用户的修改需求：$modifyRequest\n\n请根据修改需求，生成三条新的提示词。';
        promptToUse = _selectedSuggestion!;
      } else {
        systemPrompt = _systemPrompt;
        promptToUse = widget.originalPrompt;
      }

      final apiService = ref.read(apiServiceProvider);
      final results = await apiService.polishPrompt(
        apiUrl: defaultConfig.url,
        apiKey: defaultConfig.key,
        model: defaultConfig.model,
        prompt: promptToUse,
        systemPrompt: systemPrompt,
      );

      setState(() {
        _suggestions = results;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('润色失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'AI提示词润色',
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                _buildAiModelSelect(),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.text),
                  onPressed: () => _polishPrompt(),
                  tooltip: '刷新',
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.text),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppColors.border1),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                border: Border.all(color: AppColors.border2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '原始提示词: ${widget.originalPrompt}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _suggestions.isEmpty
                      ? const Center(
                          child: Text('暂无建议', style: TextStyle(color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          itemCount: _suggestions.length,
                          itemBuilder: (context, index) {
                            final suggestion = _suggestions[index];
                            final isSelected = _selectedSuggestion == suggestion;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.hover : AppColors.inputBg,
                                border: Border.all(color: isSelected ? AppColors.primary : AppColors.border2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                title: Text(
                                  suggestion,
                                  style: const TextStyle(color: AppColors.text, fontSize: 14),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () {
                                        widget.onSelect(suggestion);
                                        Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      ),
                                      child: const Text('使用'),
                                    ),
                                  ],
                                ),
                                onTap: () => setState(() => _selectedSuggestion = isSelected ? null : suggestion),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modifyController,
                    style: const TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(
                      hintText: '输入修改需求...',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.inputBg,
                      border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border2)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_modifyController.text.trim().isNotEmpty) {
                      _polishPrompt(modifyRequest: _modifyController.text.trim());
                      _modifyController.clear();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3a3a3a),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                  child: const Text('修改', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiModelSelect() {
    final configs = ref.watch(apiConfigsProvider);
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();

    if (chatConfigs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: _selectedAiConfig ?? (chatConfigs.isNotEmpty ? chatConfigs.first.id : null),
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.sidebar,
        style: const TextStyle(color: AppColors.text, fontSize: 13),
        items: chatConfigs.map((config) => DropdownMenuItem(
          value: config.id,
          child: Text(config.name),
        )).toList(),
        onChanged: (value) => setState(() => _selectedAiConfig = value),
      ),
    );
  }
}

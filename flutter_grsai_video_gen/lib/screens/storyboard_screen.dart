import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../constants/app_colors.dart';
import '../services/storyboard_service.dart';
import '../services/film_workshop_storage_service.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';

class StoryboardScreen extends ConsumerStatefulWidget {
  const StoryboardScreen({super.key});

  @override
  ConsumerState<StoryboardScreen> createState() => _StoryboardScreenState();
}

class _StoryboardScreenState extends ConsumerState<StoryboardScreen> {
  final TextEditingController _projectNameController = TextEditingController();
  final TextEditingController _artStyleController = TextEditingController();
  final TextEditingController _worldViewController = TextEditingController();
  final TextEditingController _scriptController = TextEditingController();
  String _aspectRatio = '16:9';
  final List<Map<String, dynamic>> _assets = [];
  final TextEditingController _resultController = TextEditingController();
  bool _isProcessing = false;
  String _extractedAssets = '';
  late final StoryboardService _storyboardService;
  final FilmWorkshopStorageService _storageService = FilmWorkshopStorageService();
  String? _selectedAiConfigId;
  bool _isEditingSystemPrompt = false;
  final TextEditingController _systemPromptController = TextEditingController();
  String? _currentFilePath;
  String _saveStatus = '';
  final FocusNode _titleFocusNode = FocusNode();
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _storyboardService = StoryboardService(ref.read(apiServiceProvider));
    _loadSystemPrompt();
    _loadState();
    _titleFocusNode.addListener(() {
      if (!_titleFocusNode.hasFocus) {
        _saveStoryboard(showSnackbar: false);
      }
    });
    _projectNameController.addListener(_debouncedSaveState);
    _artStyleController.addListener(_debouncedSaveState);
    _worldViewController.addListener(_debouncedSaveState);
    _scriptController.addListener(_debouncedSaveState);
    _resultController.addListener(_debouncedSaveState);
  }

  void _debouncedSaveState() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _saveState);
  }

  Future<void> _loadState() async {
    final state = await _storageService.loadStoryboardState();
    if (state != null && mounted) {
      setState(() {
        _projectNameController.text = state['projectName'] ?? '';
        _artStyleController.text = state['artStyle'] ?? '';
        _worldViewController.text = state['worldView'] ?? '';
        _aspectRatio = state['aspectRatio'] ?? '16:9';
        _scriptController.text = state['script'] ?? '';
        _resultController.text = state['result'] ?? '';
      });
    }
  }

  void _saveState() {
    _storageService.saveStoryboardState(
      projectName: _projectNameController.text,
      artStyle: _artStyleController.text,
      worldView: _worldViewController.text,
      aspectRatio: _aspectRatio,
      script: _scriptController.text,
      result: _resultController.text,
    );
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _artStyleController.dispose();
    _worldViewController.dispose();
    _scriptController.dispose();
    _resultController.dispose();
    _systemPromptController.dispose();
    _titleFocusNode.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSystemPrompt() async {
    final content = await _storageService.loadSystemPrompt(_storyboardService.getDefaultSystemPrompt());
    if (mounted) setState(() => _systemPromptController.text = content);
  }

  Future<void> _saveSystemPrompt() async {
    await _storageService.saveSystemPrompt(_systemPromptController.text);
    if (mounted) {
      setState(() => _isEditingSystemPrompt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拆解规则已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navbar,
        title: SizedBox(
          width: 300,
          child: TextField(
            controller: _projectNameController,
            focusNode: _titleFocusNode,
            onSubmitted: (_) => _saveStoryboard(showSnackbar: false),
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              hintText: '未命名剧本_当前日期',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isEditingSystemPrompt = !_isEditingSystemPrompt;
              });
            },
            child: Text(_isEditingSystemPrompt ? '退出编辑' : '拆解规则', style: const TextStyle(color: AppColors.text)),
          ),
          const SizedBox(width: 8),
          if (_saveStatus.isNotEmpty)
            Text(_saveStatus, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          _buildLeftPanel(),
          Expanded(child: _buildRightPanel()),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: 400,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border1)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildScriptInput(),
            _buildExecutionPanel(),
            _buildGlobalSettings(),
            _buildAssetsManagement(),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettings() {
    return _buildSection(
      title: '全局设定',
      children: [
        _buildTextField(
          controller: _artStyleController,
          label: '画面美术风格',
          hint: '请选择或输入风格，例如：赛博朋克、吉卜力、好莱坞写实...',
        ),
        const SizedBox(height: 16),
        const Text('画幅比例', style: TextStyle(color: AppColors.text, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildRadioButton('16:9 电影宽屏', '16:9'),
            _buildRadioButton('9:16 竖屏短剧', '9:16'),
            _buildRadioButton('1:1 设定集插画', '1:1'),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          controller: _worldViewController,
          label: '世界观与环境基调',
          hint: '描述故事发生的总体背景，确保所有镜头氛围统一...',
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _buildAssetsManagement() {
    return _buildSection(
      title: '提取的资产信息',
      children: [
        if (_extractedAssets.isEmpty)
          const Text(
            '拆解分镜后将自动提取资产信息',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border1),
            ),
            child: Text(_extractedAssets, style: const TextStyle(color: AppColors.text, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildAssetCard(Map<String, dynamic> asset) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: asset['nameController'],
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              hintText: '输入名称（如：陈默）',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: asset['featureController'],
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              hintText: '特征描述（如：35岁，黑衣，右臂机械）',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _uploadAssetImage(asset),
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.border2, style: BorderStyle.solid),
              ),
              child: Center(
                child: asset['imagePath'] == null
                    ? const Text('点击或拖拽上传参考图', style: TextStyle(color: AppColors.textSecondary))
                    : Image.file(File(asset['imagePath'] as String), fit: BoxFit.cover, errorBuilder: (ctx, err, st) => const Icon(Icons.broken_image, color: AppColors.textSecondary)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptInput() {
    return _buildSection(
      title: '剧本输入区',
      children: [
        Container(
          height: 300,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border1),
          ),
          child: TextField(
            controller: _scriptController,
            maxLines: null,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              hintText: '在此输入您的文学描述或剧本段落。建议每次输入 100~800 字。AI 导演将根据剧情起伏、叙事焦点和视觉逻辑，自动为您切分出专业的连续分镜头...',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('当前字数：${_scriptController.text.length} / 800', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Row(
              children: [
                TextButton(
                  onPressed: () => _scriptController.clear(),
                  child: const Text('清空内容', style: TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: _importScript,
                  child: const Text('导入本地文档', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildExecutionPanel() {
    final apiConfigs = ref.watch(apiConfigsProvider);
    final aiConfigs = apiConfigs.where((c) => c.type == 'chat').toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.navbar,
        border: Border(top: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        children: [
          const Text('选择AI助手', style: TextStyle(color: AppColors.text, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedAiConfigId,
            dropdownColor: AppColors.sidebar,
            style: const TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.inputBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            items: aiConfigs.map((config) => DropdownMenuItem(
              value: config.id,
              child: Text(config.name),
            )).toList(),
            onChanged: (value) => setState(() => _selectedAiConfigId = value),
            hint: const Text('请选择AI助手', style: TextStyle(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: true,
            onChanged: (value) {},
            title: const Text('剧本拆分完成后，自动开始并行渲染画面', style: TextStyle(color: AppColors.text, fontSize: 12)),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _splitScript,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sidebar,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_isProcessing ? '处理中...' : '拆解分镜', style: const TextStyle(fontSize: 16, color: AppColors.text)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    if (_isEditingSystemPrompt) {
      return Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _systemPromptController,
                maxLines: null,
                expands: true,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '在此编辑拆解规则的系统提示词...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _saveSystemPrompt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.sidebar,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('保存规则', style: TextStyle(color: AppColors.text)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _resultController,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: AppColors.text, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '拆解结果将在此显示...',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _saveStoryboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.sidebar,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('保存分镜脚本', style: TextStyle(color: AppColors.text)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.text, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioButton(String label, String value) {
    return Expanded(
      child: RadioListTile<String>(
        value: value,
        groupValue: _aspectRatio,
        onChanged: (val) {
          setState(() => _aspectRatio = val!);
          _saveState();
        },
        title: Text(label, style: const TextStyle(color: AppColors.text, fontSize: 12)),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  void _addAsset() {
    setState(() {
      _assets.add({
        'nameController': TextEditingController(),
        'featureController': TextEditingController(),
        'imagePath': null,
      });
    });
  }

  void _uploadAssetImage(Map<String, dynamic> asset) {
    // TODO: 实现图片上传功能
  }

  void _importScript() async {
    // TODO: 实现文档导入功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文档导入功能开发中')),
    );
  }

  void _saveStoryboard({bool showSnackbar = true}) async {
    if (_resultController.text.isEmpty && _projectNameController.text.trim().isEmpty) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先输入剧本名称或拆解分镜')),
        );
      }
      return;
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final storyboardDir = path.join(appDir.path, 'data', 'storyboard');
      await Directory(storyboardDir).create(recursive: true);

      String fileName = _projectNameController.text.trim();
      if (fileName.isEmpty) {
        final now = DateTime.now();
        fileName = '未命名剧本_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      }

      final filePath = path.join(storyboardDir, '$fileName.txt');

      // 如果文件名改变了，重命名旧文件
      if (_currentFilePath != null && _currentFilePath != filePath) {
        final oldFile = File(_currentFilePath!);
        if (await oldFile.exists()) {
          await oldFile.rename(filePath);
        }
      }

      final file = File(filePath);
      await file.writeAsString(_resultController.text);
      _currentFilePath = filePath;

      if (mounted) {
        setState(() {
          final now = DateTime.now();
          _saveStatus = '✅ 已保存 ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        });

        if (showSnackbar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分镜脚本已保存')),
          );
        }
      }
    } catch (e) {
      if (showSnackbar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  void _splitScript() async {
    if (_scriptController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先输入剧本内容')),
        );
      }
      return;
    }

    if (_selectedAiConfigId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择AI助手')),
        );
      }
      return;
    }

    final apiConfigs = ref.read(apiConfigsProvider);
    final aiConfig = apiConfigs.firstWhere((c) => c.id == _selectedAiConfigId);

    setState(() => _isProcessing = true);

    try {
      final assets = _assets.map((asset) => {
        'name': (asset['nameController'] as TextEditingController).text,
        'feature': (asset['featureController'] as TextEditingController).text,
      }).toList();

      final shots = await _storyboardService.splitScript(
        apiUrl: aiConfig.url,
        apiKey: aiConfig.key,
        model: aiConfig.model,
        script: _scriptController.text,
        artStyle: _artStyleController.text,
        worldView: _worldViewController.text,
        aspectRatio: _aspectRatio,
        assets: assets,
      );

      if (mounted) {
        // 提取资产信息
        try {
          final extractedAssets = await _storyboardService.extractAssets(
            apiUrl: aiConfig.url,
            apiKey: aiConfig.key,
            model: aiConfig.model,
            shots: shots,
          );
          setState(() {
            _extractedAssets = extractedAssets.toFormattedString();
            // 自动填充各项信息
            _artStyleController.text = _artStyleController.text.isEmpty ? '根据剧本风格' : _artStyleController.text;
            _worldViewController.text = _worldViewController.text.isEmpty ? extractedAssets.atmosphere : _worldViewController.text;
          });
        } catch (e) {
          // 忽略资产提取错误
        }

        final result = StringBuffer();

        // 添加资产统计信息
        if (_extractedAssets.isNotEmpty) {
          result.writeln(_extractedAssets);
          result.writeln('\n');
        }

        for (int i = 0; i < shots.length; i++) {
          final shot = shots[i];
          result.writeln('==========');
          result.writeln('[镜头序号]: ${shot.shotNumber.isNotEmpty ? shot.shotNumber : (i + 1).toString().padLeft(2, '0')}');
          if (shot.shotName.isNotEmpty) {
            result.writeln('[镜头名称]: ${shot.shotName}');
          }
          result.writeln('[景别]: ${shot.shotType}');
          if (shot.cameraAngle.isNotEmpty) {
            result.writeln('[视角与摄影机]: ${shot.cameraAngle}');
          }
          if (shot.lighting.isNotEmpty) {
            result.writeln('[光影氛围]: ${shot.lighting}');
          }
          if (shot.sceneDescription.isNotEmpty) {
            result.writeln('[场景基础描述]: ${shot.sceneDescription}');
          }
          if (shot.sceneDetails.isNotEmpty) {
            result.writeln('[场景细节描述]: ${shot.sceneDetails}');
          }
          result.writeln('[画面文字]: ${shot.textInFrame}');
          result.writeln('[物体状态]: ${shot.objectState}');
          result.writeln('[角色名称]: ${shot.characterName}');
          result.writeln('[服装化妆]: ${shot.costume}');
          result.writeln('[人物动作]: ${shot.action}');
          result.writeln('[人物表情]: ${shot.expression}');
          result.writeln('[使用道具]: ${shot.props}');
          if (shot.prompt.isNotEmpty) {
            result.writeln('[画面描述]: ${shot.prompt}');
          }
          result.writeln();
        }

        setState(() {
          _resultController.text = result.toString();
          _isProcessing = false;
        });

        // 拆解完成后自动保存
        _saveStoryboard(showSnackbar: false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功拆分为 ${shots.length} 个镜头')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拆分失败: $e')),
        );
      }
    }
  }
}

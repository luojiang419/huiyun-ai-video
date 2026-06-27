import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';
import '../models/api_config.dart';
import '../services/api_service.dart';
import '../services/video_api_service.dart';

class ApiConfigScreen extends ConsumerStatefulWidget {
  const ApiConfigScreen({super.key});

  @override
  ConsumerState<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends ConsumerState<ApiConfigScreen> {
  @override
  Widget build(BuildContext context) {
    final configs = ref.watch(apiConfigsProvider);
    final imageConfigs = configs.where((c) => c.type == 'image').toList();
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();
    final visionConfigs = configs.where((c) => c.type == 'vision').toList();
    final videoConfigs = configs.where((c) => c.type == 'video').toList();
    final defaultImageConfig = imageConfigs
        .where((c) => c.isDefault)
        .firstOrNull;
    final defaultChatConfig = chatConfigs.where((c) => c.isDefault).firstOrNull;
    final defaultVisionConfig = visionConfigs
        .where((c) => c.isDefault)
        .firstOrNull;
    final defaultVideoConfig = videoConfigs
        .where((c) => c.isDefault)
        .firstOrNull;

    return Stack(
      children: [
        Container(
          color: AppColors.background,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'API配置',
                style: TextStyle(color: AppColors.text, fontSize: 24),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.sidebar,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '图片生成:',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: defaultImageConfig?.id,
                              hint: const Text(
                                '未配置',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dropdownColor: AppColors.background,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                              ),
                              underline: Container(
                                height: 1,
                                color: AppColors.border2,
                              ),
                              isExpanded: true,
                              items: imageConfigs
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  ref
                                      .read(apiConfigsProvider.notifier)
                                      .setDefault(id, 'image');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'AI助手:',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: defaultChatConfig?.id,
                              hint: const Text(
                                '未配置',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dropdownColor: AppColors.background,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                              ),
                              underline: Container(
                                height: 1,
                                color: AppColors.border2,
                              ),
                              isExpanded: true,
                              items: chatConfigs
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  ref
                                      .read(apiConfigsProvider.notifier)
                                      .setDefault(id, 'chat');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '视觉模型:',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: defaultVisionConfig?.id,
                              hint: const Text(
                                '未配置',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dropdownColor: AppColors.background,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                              ),
                              underline: Container(
                                height: 1,
                                color: AppColors.border2,
                              ),
                              isExpanded: true,
                              items: visionConfigs
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  ref
                                      .read(apiConfigsProvider.notifier)
                                      .setDefault(id, 'vision');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '视频模型:',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButton<String>(
                              value: defaultVideoConfig?.id,
                              hint: const Text(
                                '未配置',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              dropdownColor: AppColors.background,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                              ),
                              underline: Container(
                                height: 1,
                                color: AppColors.border2,
                              ),
                              isExpanded: true,
                              items: videoConfigs
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  ref
                                      .read(apiConfigsProvider.notifier)
                                      .setDefault(id, 'video');
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildConfigColumn('图片生成API', imageConfigs),
                    ),
                    const SizedBox(width: 20),
                    Expanded(child: _buildConfigColumn('AI助手API', chatConfigs)),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildConfigColumn('视觉模型API', visionConfigs),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildConfigColumn('视频模型API', videoConfigs),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 30,
          right: 110,
          child: ElevatedButton(
            onPressed: () => _showTestApiDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3a3a3a),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: const BorderSide(color: Color(0xFF555555)),
              elevation: 4,
            ),
            child: const Text(
              '测试API',
              style: TextStyle(color: Color(0xFFe0e0e0), fontSize: 14),
            ),
          ),
        ),
        Positioned(
          bottom: 30,
          right: 30,
          child: ElevatedButton(
            onPressed: () => _showAddConfigDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
              elevation: 4,
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigColumn(String title, List<ApiConfig> configs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: configs.isEmpty
              ? Center(
                  child: Text(
                    '暂无$title配置',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: configs.length,
                  itemBuilder: (context, index) {
                    final config = configs[index];
                    return _buildConfigCard(config);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConfigCard(ApiConfig config) {
    return InkWell(
      onTap: () => ref
          .read(apiConfigsProvider.notifier)
          .setDefault(config.id, config.type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.sidebar,
          border: Border.all(
            color: config.isDefault ? AppColors.primary : AppColors.border2,
            width: config.isDefault ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (config.isDefault)
                  Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.edit,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => _showEditConfigDialog(context, config),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  onPressed: () => ref
                      .read(apiConfigsProvider.notifier)
                      .deleteConfig(config.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '模型: ${config.model}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'URL: ${config.url}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAddConfigDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final keyController = TextEditingController();
    final modelController = TextEditingController();
    String type = 'image';
    List<String> fetchedModels = [];
    bool isLoadingModels = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text('新建API配置', style: TextStyle(color: AppColors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: '配置名称',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  dropdownColor: AppColors.sidebar,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: '类型',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'image', child: Text('图片生成')),
                    DropdownMenuItem(value: 'chat', child: Text('AI助手')),
                    DropdownMenuItem(value: 'vision', child: Text('视觉模型')),
                    DropdownMenuItem(value: 'video', child: Text('视频模型')),
                  ],
                  onChanged: (v) => setState(() {
                    type = v!;
                    fetchedModels = [];
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                // OpenAI 兼容接口和视频接口支持获取模型列表 + 手动输入
                if (type == 'image' ||
                    type == 'chat' ||
                    type == 'vision' ||
                    type == 'video') ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: modelController,
                          style: const TextStyle(color: AppColors.text),
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            labelStyle: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isLoadingModels
                            ? null
                            : () async {
                                if (urlController.text.isEmpty ||
                                    keyController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('请先填写 API URL 和 API Key'),
                                    ),
                                  );
                                  return;
                                }
                                setState(() => isLoadingModels = true);
                                try {
                                  final models = type == 'video'
                                      ? (await VideoApiService(
                                                  baseUrl: urlController.text,
                                                ).fetchModelCatalog())?.models
                                                .map((item) => item.id)
                                                .toList() ??
                                            []
                                      : await ApiService().fetchModels(
                                          urlController.text,
                                          keyController.text,
                                        );
                                  setState(() {
                                    fetchedModels = models;
                                    isLoadingModels = false;
                                  });
                                } catch (e) {
                                  setState(() => isLoadingModels = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('获取模型列表失败: $e')),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3a3a3a),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: const BorderSide(color: Color(0xFF555555)),
                        ),
                        child: isLoadingModels
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '获取模型',
                                style: TextStyle(
                                  color: Color(0xFFe0e0e0),
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (fetchedModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: fetchedModels.length,
                        itemBuilder: (context, index) {
                          final modelName = fetchedModels[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              modelName,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                              ),
                            ),
                            trailing: modelController.text == modelName
                                ? Icon(
                                    Icons.check,
                                    color: AppColors.primary,
                                    size: 18,
                                  )
                                : null,
                            onTap: () {
                              setState(() => modelController.text = modelName);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: modelController,
                    style: const TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                final config = ApiConfig(
                  id: const Uuid().v4(),
                  name: nameController.text,
                  type: type,
                  url: urlController.text,
                  key: keyController.text,
                  model: modelController.text,
                  isDefault: false,
                );
                ref.read(apiConfigsProvider.notifier).addConfig(config);
                Navigator.pop(context);
              },
              child: const Text(
                '添加',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditConfigDialog(BuildContext context, ApiConfig config) {
    final nameController = TextEditingController(text: config.name);
    final urlController = TextEditingController(text: config.url);
    final keyController = TextEditingController(text: config.key);
    final modelController = TextEditingController(text: config.model);
    String type = config.type;
    List<String> fetchedModels = [];
    bool isLoadingModels = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text('编辑API配置', style: TextStyle(color: AppColors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: '配置名称',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  dropdownColor: AppColors.sidebar,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: '类型',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'image', child: Text('图片生成')),
                    DropdownMenuItem(value: 'chat', child: Text('AI助手')),
                    DropdownMenuItem(value: 'vision', child: Text('视觉模型')),
                    DropdownMenuItem(value: 'video', child: Text('视频模型')),
                  ],
                  onChanged: (v) => setState(() {
                    type = v!;
                    fetchedModels = [];
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyController,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                // OpenAI 兼容接口和视频接口支持获取模型列表 + 手动输入
                if (type == 'image' ||
                    type == 'chat' ||
                    type == 'vision' ||
                    type == 'video') ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: modelController,
                          style: const TextStyle(color: AppColors.text),
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            labelStyle: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isLoadingModels
                            ? null
                            : () async {
                                if (urlController.text.isEmpty ||
                                    keyController.text.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('请先填写 API URL 和 API Key'),
                                    ),
                                  );
                                  return;
                                }
                                setState(() => isLoadingModels = true);
                                try {
                                  final models = type == 'video'
                                      ? (await VideoApiService(
                                                  baseUrl: urlController.text,
                                                ).fetchModelCatalog())?.models
                                                .map((item) => item.id)
                                                .toList() ??
                                            []
                                      : await ApiService().fetchModels(
                                          urlController.text,
                                          keyController.text,
                                        );
                                  setState(() {
                                    fetchedModels = models;
                                    isLoadingModels = false;
                                  });
                                } catch (e) {
                                  setState(() => isLoadingModels = false);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('获取模型列表失败: $e')),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3a3a3a),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: const BorderSide(color: Color(0xFF555555)),
                        ),
                        child: isLoadingModels
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '获取模型',
                                style: TextStyle(
                                  color: Color(0xFFe0e0e0),
                                  fontSize: 13,
                                ),
                              ),
                      ),
                    ],
                  ),
                  if (fetchedModels.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: fetchedModels.length,
                        itemBuilder: (context, index) {
                          final modelName = fetchedModels[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              modelName,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                              ),
                            ),
                            trailing: modelController.text == modelName
                                ? Icon(
                                    Icons.check,
                                    color: AppColors.primary,
                                    size: 18,
                                  )
                                : null,
                            onTap: () {
                              setState(() => modelController.text = modelName);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ] else ...[
                  TextField(
                    controller: modelController,
                    style: const TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                final updatedConfig = ApiConfig(
                  id: config.id,
                  name: nameController.text,
                  type: type,
                  url: urlController.text,
                  key: keyController.text,
                  model: modelController.text,
                  isDefault: config.isDefault,
                );
                ref
                    .read(apiConfigsProvider.notifier)
                    .updateConfig(updatedConfig);
                Navigator.pop(context);
              },
              child: const Text(
                '保存',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTestApiDialog(BuildContext context) {
    final testController = TextEditingController();
    final messages = <Map<String, String>>[];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
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
                      '测试API',
                      style: TextStyle(color: AppColors.text, fontSize: 18),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.text),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(color: AppColors.border1),
                Expanded(
                  child: ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg['role'] == 'user';
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        children: [
                          if (!isUser) ...[
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3a3a3a),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'A',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: LayoutBuilder(
                              builder: (context, constraints) => Container(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * 0.7,
                                ),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? AppColors.primary
                                      : const Color(0xFF3a3a3a),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  msg['content'] ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFFe0e0e0),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (isUser) ...[
                            const SizedBox(width: 12),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'U',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: testController,
                        style: const TextStyle(color: AppColors.text),
                        decoration: const InputDecoration(
                          hintText: '输入测试消息...',
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.inputBg,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border2),
                          ),
                        ),
                        onSubmitted: (value) async {
                          if (value.trim().isEmpty) return;

                          final configs = ref.read(apiConfigsProvider);
                          final chatConfigs = configs
                              .where((c) => c.type == 'chat')
                              .toList();
                          final defaultConfig = chatConfigs
                              .where((c) => c.isDefault)
                              .firstOrNull;

                          if (defaultConfig == null) {
                            setState(() {
                              messages.add({
                                'role': 'assistant',
                                'content': '请先在API配置中设置默认AI助手',
                              });
                            });
                            return;
                          }

                          setState(() {
                            messages.add({'role': 'user', 'content': value});
                            messages.add({'role': 'assistant', 'content': ''});
                          });
                          testController.clear();

                          try {
                            final apiService = ref.read(apiServiceProvider);
                            final stream = apiService.chatStream(
                              apiUrl: defaultConfig.url,
                              apiKey: defaultConfig.key,
                              model: defaultConfig.model,
                              messages: [
                                {'role': 'user', 'content': value},
                              ],
                              systemPrompt: '你是一个AI助手,请简洁地回答用户的问题。',
                            );

                            await for (var chunk in stream) {
                              setState(() {
                                final lastMsg = messages.last;
                                messages[messages.length - 1] = {
                                  'role': 'assistant',
                                  'content': (lastMsg['content'] ?? '') + chunk,
                                };
                              });
                            }
                          } catch (e) {
                            setState(() {
                              if (messages.last['content'] == '') {
                                messages.removeLast();
                              }
                              messages.add({
                                'role': 'assistant',
                                'content': '错误: $e',
                              });
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final value = testController.text.trim();
                        if (value.isEmpty) return;

                        final configs = ref.read(apiConfigsProvider);
                        final chatConfigs = configs
                            .where((c) => c.type == 'chat')
                            .toList();
                        final defaultConfig = chatConfigs
                            .where((c) => c.isDefault)
                            .firstOrNull;

                        if (defaultConfig == null) {
                          setState(() {
                            messages.add({
                              'role': 'assistant',
                              'content': '请先在API配置中设置默认AI助手',
                            });
                          });
                          return;
                        }

                        setState(() {
                          messages.add({'role': 'user', 'content': value});
                          messages.add({'role': 'assistant', 'content': ''});
                        });
                        testController.clear();

                        try {
                          final apiService = ref.read(apiServiceProvider);
                          final stream = apiService.chatStream(
                            apiUrl: defaultConfig.url,
                            apiKey: defaultConfig.key,
                            model: defaultConfig.model,
                            messages: [
                              {'role': 'user', 'content': value},
                            ],
                            systemPrompt: '你是一个AI助手,请简洁地回答用户的问题。',
                          );

                          await for (var chunk in stream) {
                            setState(() {
                              final lastMsg = messages.last;
                              messages[messages.length - 1] = {
                                'role': 'assistant',
                                'content': (lastMsg['content'] ?? '') + chunk,
                              };
                            });
                          }
                        } catch (e) {
                          setState(() {
                            if (messages.last['content'] == '') {
                              messages.removeLast();
                            }
                            messages.add({
                              'role': 'assistant',
                              'content': '错误: $e',
                            });
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      child: const Text(
                        '发送',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

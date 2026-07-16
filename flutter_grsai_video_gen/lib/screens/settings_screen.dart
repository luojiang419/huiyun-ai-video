import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/compute_node.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../providers/video_config_provider.dart';
import '../providers/video_node_provider.dart';
import '../services/video_vlm_service.dart';
import '../services/wan2gp_bridge_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _outputFolderController;
  late TextEditingController _customFilenameController;
  late TextEditingController _aiNicknameController;
  late TextEditingController _userNicknameController;
  late String _filenameRule;
  late String _uploadMethod;
  late String _updatePolicy;
  late String _updateNetworkMode;

  final TextEditingController _vlmUrlController = TextEditingController();
  final TextEditingController _vlmModelController = TextEditingController();
  final TextEditingController _vlmKeyController = TextEditingController();
  final TextEditingController _updateProxyAddressController =
      TextEditingController();

  final TextEditingController _bridgePythonController = TextEditingController();
  final TextEditingController _bridgeScriptController = TextEditingController();
  final TextEditingController _bridgePortController = TextEditingController();

  bool _autoLaunchBridge = false;
  bool _videoLoaded = false;
  bool _bridgeRunning = false;
  StreamSubscription<Wan2gpStatus>? _bridgeStatusSub;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _outputFolderController = TextEditingController(
      text: settings.outputFolder,
    );
    _customFilenameController = TextEditingController(
      text: settings.customFilename,
    );
    _aiNicknameController = TextEditingController(text: settings.aiNickname);
    _userNicknameController = TextEditingController(
      text: settings.userNickname,
    );
    _filenameRule = settings.filenameRule;
    _uploadMethod = settings.uploadMethod;
    _updatePolicy = settings.updatePolicy;
    _updateNetworkMode = settings.updateNetworkMode;
    _updateProxyAddressController.text = settings.updateManualProxyUrl;

    final bridgeService = ref.read(wan2gpBridgeServiceProvider);
    _bridgeRunning = bridgeService.isRunning;
    _bridgeStatusSub = bridgeService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _bridgeRunning = status == Wan2gpStatus.running;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(videoNodesProvider.notifier).refreshStatuses();
    });
  }

  @override
  void dispose() {
    _bridgeStatusSub?.cancel();
    _outputFolderController.dispose();
    _customFilenameController.dispose();
    _aiNicknameController.dispose();
    _userNicknameController.dispose();
    _vlmUrlController.dispose();
    _vlmModelController.dispose();
    _vlmKeyController.dispose();
    _updateProxyAddressController.dispose();
    _bridgePythonController.dispose();
    _bridgeScriptController.dispose();
    _bridgePortController.dispose();
    super.dispose();
  }

  void _syncVideoSettings() {
    if (_videoLoaded) return;
    final videoSettings = ref.watch(videoSettingsProvider);
    _vlmUrlController.text = videoSettings.vlm.apiUrl;
    _vlmModelController.text = videoSettings.vlm.model;
    _vlmKeyController.text = videoSettings.vlm.apiKey;
    _bridgePythonController.text = videoSettings.wan2gp.pythonPath;
    _bridgeScriptController.text = videoSettings.wan2gp.scriptPath;
    _bridgePortController.text = videoSettings.wan2gp.port.toString();
    _autoLaunchBridge = videoSettings.wan2gp.autoLaunch;
    _videoLoaded = true;
  }

  Future<void> _pickOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择输出文件夹',
    );
    if (result != null) {
      setState(() => _outputFolderController.text = result);
    }
  }

  Future<void> _openOutputFolder() async {
    String folderPath = _outputFolderController.text.trim();
    if (folderPath.isEmpty) {
      final appDir = File(Platform.resolvedExecutable).parent;
      folderPath = '${appDir.path}/data/output';
    }
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await Process.run('explorer', [dir.path]);
  }

  Future<void> _pickPythonPath() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
      dialogTitle: '选择 Python 可执行文件',
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _bridgePythonController.text = result.files.single.path!);
    }
  }

  Future<void> _pickBridgeScript() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['py'],
      dialogTitle: '选择 wan2gp bridge 脚本',
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _bridgeScriptController.text = result.files.single.path!);
    }
  }

  Future<void> _startBridge() async {
    final ok = await ref
        .read(wan2gpBridgeServiceProvider)
        .launch(
          pythonPath: _bridgePythonController.text.trim(),
          scriptPath: _bridgeScriptController.text.trim(),
          port: int.tryParse(_bridgePortController.text.trim()) ?? 7861,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? 'Wan2GP 已启动' : '启动失败')));
  }

  Future<void> _stopBridge() async {
    await ref.read(wan2gpBridgeServiceProvider).stop();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Wan2GP 已停止')));
  }

  Future<void> _testBridge() async {
    final port = int.tryParse(_bridgePortController.text.trim()) ?? 7861;
    final ok = await ref
        .read(wan2gpBridgeServiceProvider)
        .healthCheck('127.0.0.1', port);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '7861桥接连接成功' : '无法连接7861桥接')));
  }

  Future<void> _testVlm() async {
    final service = VideoVlmService(
      apiUrl: _vlmUrlController.text.trim(),
      apiKey: _vlmKeyController.text.trim(),
      model: _vlmModelController.text.trim(),
    );
    final ok = await service.testConnection();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? 'VLM连接成功' : 'VLM连接失败')));
  }

  Future<void> _showNodeDialog([ComputeNode? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(
      text: existing?.publicUrl ?? '',
    );
    final remarkController = TextEditingController(
      text: existing?.remark ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: Text(
          existing == null ? '添加计算节点' : '编辑计算节点',
          style: const TextStyle(color: AppColors.text),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('节点名称', nameController),
              const SizedBox(height: 12),
              _buildTextField('节点地址', urlController),
              const SizedBox(height: 12),
              _buildTextField('备注', remarkController),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty ||
                  urlController.text.trim().isEmpty) {
                return;
              }
              if (existing == null) {
                await ref
                    .read(videoNodesProvider.notifier)
                    .createNode(
                      name: nameController.text.trim(),
                      publicUrl: urlController.text.trim(),
                      remark: remarkController.text.trim().isEmpty
                          ? null
                          : remarkController.text.trim(),
                    );
              } else {
                await ref
                    .read(videoNodesProvider.notifier)
                    .updateNode(
                      existing.copyWith(
                        name: nameController.text.trim(),
                        publicUrl: urlController.text.trim(),
                        remark: remarkController.text.trim().isEmpty
                            ? null
                            : remarkController.text.trim(),
                      ),
                    );
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAllSettings() async {
    final current = ref.read(settingsProvider);
    final general = Settings(
      apiUrl: current.apiUrl,
      apiKey: current.apiKey,
      aiApiUrl: current.aiApiUrl,
      aiApiKey: current.aiApiKey,
      aiModel: current.aiModel,
      uploadMethod: _uploadMethod,
      updatePolicy: _updatePolicy,
      updateNetworkMode: _updateNetworkMode,
      updateManualProxyUrl: _updateProxyAddressController.text.trim(),
      outputFolder: _outputFolderController.text.trim(),
      filenameRule: _filenameRule,
      customFilename: _customFilenameController.text.trim(),
      aiNickname: _aiNicknameController.text.trim(),
      userNickname: _userNicknameController.text.trim(),
    );
    await ref.read(settingsProvider.notifier).updateSettings(general);

    await ref
        .read(videoSettingsProvider.notifier)
        .updateVlmConfig(
          apiUrl: _vlmUrlController.text.trim(),
          apiKey: _vlmKeyController.text.trim(),
          model: _vlmModelController.text.trim(),
        );
    await ref
        .read(videoSettingsProvider.notifier)
        .updateBridgeConfig(
          pythonPath: _bridgePythonController.text.trim(),
          scriptPath: _bridgeScriptController.text.trim(),
          port: int.tryParse(_bridgePortController.text.trim()) ?? 7861,
          autoLaunch: _autoLaunchBridge,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('设置已保存')));
  }

  Future<void> _checkAndInstallUpdateNow() async {
    if (_updatePolicy == Settings.updatePolicyDisabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新已禁止，请先将更新策略改为自动更新或手动更新')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在检查并下载更新...')));

    try {
      final job = await ref
          .read(updateProvider.notifier)
          .checkAndDownloadUpdate(includeSkipped: true);
      if (!mounted) return;
      if (job == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前已是最新版')));
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新包已就绪，正在启动安装程序...')));
      await ref.read(updateProvider.notifier).installPendingUpdate(job: job);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncVideoSettings();
    final nodes = ref.watch(videoNodesProvider);
    final updateState = ref.watch(updateProvider);
    final isUpdateBusy =
        updateState.status == UpdateStatus.checking ||
        updateState.status == UpdateStatus.downloading ||
        updateState.status == UpdateStatus.installing;
    final isUpdateDisabled = _updatePolicy == Settings.updatePolicyDisabled;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '设置',
                style: TextStyle(color: AppColors.text, fontSize: 24),
              ),
              OutlinedButton.icon(
                onPressed: isUpdateBusy || isUpdateDisabled
                    ? null
                    : _checkAndInstallUpdateNow,
                icon: const Icon(Icons.system_update_alt, size: 18),
                label: Text(isUpdateBusy ? '更新处理中...' : '检查更新'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _buildSection('通用设置', [
                  _buildOutputFolderRow(),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    '参考图上传方式',
                    _uploadMethod,
                    const [
                      (Settings.uploadMethodRelayUrl, '中继上传'),
                      (Settings.uploadMethodBase64, 'Base64上传'),
                    ],
                    (v) => setState(() => _uploadMethod = v!),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '中继不稳定时可切到 Base64 上传；如遇大图或接口更适合 URL，再切回中继上传。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildUpdateDownloadProxyControls(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          '下载文件名规则',
                          _filenameRule,
                          const [
                            ('date', '自定义字符-日期-时间'),
                            ('sequence', '自定义字符-序号'),
                          ],
                          (v) => setState(() => _filenameRule = v!),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          '自定义文件名前缀',
                          _customFilenameController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField('AI昵称', _aiNicknameController),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField('用户昵称', _userNicknameController),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection('Wan2GP 本地桥接', [
                  SwitchListTile(
                    value: _autoLaunchBridge,
                    title: const Text(
                      '启动软件时自动启动桥接',
                      style: TextStyle(color: AppColors.text),
                    ),
                    onChanged: (value) =>
                        setState(() => _autoLaunchBridge = value),
                  ),
                  _buildPathRow(
                    'Python 路径',
                    _bridgePythonController,
                    _pickPythonPath,
                  ),
                  const SizedBox(height: 12),
                  _buildPathRow(
                    '桥接脚本路径',
                    _bridgeScriptController,
                    _pickBridgeScript,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    '桥接端口',
                    _bridgePortController,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _bridgeRunning ? null : _startBridge,
                        child: Text(_bridgeRunning ? '运行中' : '立即启动'),
                      ),
                      OutlinedButton(
                        onPressed: _bridgeRunning ? _stopBridge : null,
                        child: const Text('停止'),
                      ),
                      OutlinedButton(
                        onPressed: _testBridge,
                        child: const Text('检测连接'),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection('视觉模型 VLM', [
                  _buildTextField('API 地址', _vlmUrlController),
                  const SizedBox(height: 12),
                  _buildTextField('模型名称', _vlmModelController),
                  const SizedBox(height: 12),
                  _buildTextField('API Key', _vlmKeyController),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _testVlm,
                    child: const Text('测试连接'),
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection('节点管理', [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showNodeDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('添加节点'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => ref
                            .read(videoNodesProvider.notifier)
                            .refreshStatuses(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新状态'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (nodes.isEmpty)
                    const Text(
                      '暂无计算节点',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    ...nodes.map((node) => _buildNodeCard(node)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              onPressed: _saveAllSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5cb85c),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text('保存设置', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: AppColors.text, fontSize: 18),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildOutputFolderRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('输出文件夹', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTextField('', _outputFolderController)),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickOutputFolder,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('选择'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openOutputFolder,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('打开'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpdateDownloadProxyControls() {
    final isManualProxy =
        _updateNetworkMode == Settings.updateNetworkManualProxy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown(
          '更新策略',
          _updatePolicy,
          const [
            (Settings.updatePolicyAutomatic, '自动更新（默认）'),
            (Settings.updatePolicyManual, '手动更新'),
            (Settings.updatePolicyDisabled, '禁止更新'),
          ],
          (value) {
            if (value == null) return;
            setState(() => _updatePolicy = value);
          },
        ),
        const SizedBox(height: 8),
        const Text(
          '自动更新会在启动后检查并下载；手动更新只响应“检查更新”；禁止更新不会发起更新请求。',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildDropdown(
          '更新网络',
          _updateNetworkMode,
          const [
            (Settings.updateNetworkAutomaticProxy, '自动检测代理（默认）'),
            (Settings.updateNetworkManualProxy, '手动代理'),
            (Settings.updateNetworkDirect, '直连'),
          ],
          (value) {
            if (value == null) return;
            setState(() => _updateNetworkMode = value);
          },
        ),
        const SizedBox(height: 8),
        Text(
          isManualProxy
              ? '手动代理可填写 http://127.0.0.1:7890、127.0.0.1:7890 或 SOCKS 地址。'
              : _updateNetworkMode == Settings.updateNetworkDirect
              ? '直连会显式绕过环境变量、系统代理和本机代理。'
              : '自动读取环境变量与 Windows 系统代理，并探测本机常用代理端口；找不到时直连。',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (isManualProxy) ...[
          const SizedBox(height: 12),
          _buildTextField('自定义代理地址', _updateProxyAddressController),
        ],
      ],
    );
  }

  Widget _buildPathRow(
    String label,
    TextEditingController controller,
    VoidCallback onPick,
  ) {
    return Row(
      children: [
        Expanded(child: _buildTextField(label, controller)),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onPick, child: const Text('浏览')),
      ],
    );
  }

  Widget _buildNodeCard(ComputeNode node) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: node.isDefault ? AppColors.primary : AppColors.border2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  node.name,
                  style: const TextStyle(color: AppColors.text, fontSize: 14),
                ),
              ),
              Text(
                node.isOnline ? '在线' : '离线',
                style: TextStyle(
                  color: node.isOnline ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            node.publicUrl,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (node.remark != null && node.remark!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              node.remark!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () =>
                    ref.read(videoNodesProvider.notifier).testConnection(node),
                child: const Text('测试连接'),
              ),
              OutlinedButton(
                onPressed: () => _showNodeDialog(node),
                child: const Text('编辑'),
              ),
              OutlinedButton(
                onPressed: () =>
                    ref.read(videoNodesProvider.notifier).setDefault(node.id),
                child: Text(node.isDefault ? '默认节点' : '设为默认'),
              ),
              OutlinedButton(
                onPressed: () =>
                    ref.read(videoNodesProvider.notifier).deleteNode(node.id),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            filled: true,
            fillColor: AppColors.inputBg,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border2),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<(String, String)> items,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            border: Border.all(color: AppColors.border2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: AppColors.sidebar,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            items: items
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

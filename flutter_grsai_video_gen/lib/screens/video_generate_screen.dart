import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/compute_node.dart';
import '../models/video_api_models.dart';
import '../models/video_generate_params.dart';
import '../models/video_item.dart';
import '../models/video_task.dart';
import '../providers/api_config_provider.dart';
import '../providers/video_config_provider.dart';
import '../providers/video_gallery_provider.dart';
import '../providers/video_node_provider.dart';
import '../providers/video_task_provider.dart';
import '../services/config_file_service.dart';
import '../services/file_service.dart';
import '../services/video_api_service.dart';
import '../services/video_vlm_service.dart';
import '../widgets/video_player_widget.dart';

List<ModelFamilyInfo> _resolveWan2gpFamilies(
  ModelCatalog catalog, {
  required String preferredType,
}) {
  final merged = _mergeModelFamilies(catalog.t2vFamilies, catalog.i2vFamilies);
  if (merged.isNotEmpty) {
    return merged;
  }
  return _buildFlatFallbackFamilies(
    catalog.models,
    preferredType: preferredType,
  );
}

List<ModelFamilyInfo> _mergeModelFamilies(
  List<ModelFamilyInfo> primary,
  List<ModelFamilyInfo> secondary,
) {
  final mergedFamilies = <String, ModelFamilyInfo>{};

  void mergeFrom(List<ModelFamilyInfo> families) {
    for (final family in families) {
      final familyKey = family.id.isNotEmpty ? family.id : family.label;
      final existingFamily = mergedFamilies[familyKey];
      if (existingFamily == null) {
        mergedFamilies[familyKey] = ModelFamilyInfo(
          id: family.id,
          label: family.label,
          bases: family.bases
              .map(
                (base) => ModelBaseInfo(
                  id: base.id,
                  label: base.label,
                  models: List<ModelChoiceInfo>.from(base.models),
                ),
              )
              .toList(),
        );
        continue;
      }

      final mergedBases = <String, ModelBaseInfo>{
        for (final base in existingFamily.bases)
          (base.id.isNotEmpty ? base.id : base.label): ModelBaseInfo(
            id: base.id,
            label: base.label,
            models: List<ModelChoiceInfo>.from(base.models),
          ),
      };

      for (final base in family.bases) {
        final baseKey = base.id.isNotEmpty ? base.id : base.label;
        final existingBase = mergedBases[baseKey];
        if (existingBase == null) {
          mergedBases[baseKey] = ModelBaseInfo(
            id: base.id,
            label: base.label,
            models: List<ModelChoiceInfo>.from(base.models),
          );
          continue;
        }

        final mergedModels = <String, ModelChoiceInfo>{
          for (final model in existingBase.models) model.id: model,
        };
        for (final model in base.models) {
          mergedModels.putIfAbsent(model.id, () => model);
        }

        mergedBases[baseKey] = ModelBaseInfo(
          id: existingBase.id,
          label: existingBase.label,
          models: mergedModels.values.toList(),
        );
      }

      mergedFamilies[familyKey] = ModelFamilyInfo(
        id: existingFamily.id,
        label: existingFamily.label,
        bases: mergedBases.values.toList(),
      );
    }
  }

  mergeFrom(primary);
  mergeFrom(secondary);
  return mergedFamilies.values.toList();
}

List<ModelFamilyInfo> _buildFlatFallbackFamilies(
  List<ModelInfo> models, {
  required String preferredType,
}) {
  final preferredModels = models
      .where((model) => model.type == preferredType)
      .toList();
  final sourceModels = preferredModels.isNotEmpty ? preferredModels : models;
  final choices = sourceModels
      .map(
        (model) => ModelChoiceInfo(
          id: model.id,
          label: model.name,
          name: model.name,
          type: model.type,
          description: model.description,
          loaded: model.loaded,
        ),
      )
      .toList();
  if (choices.isEmpty) {
    return [];
  }
  return [
    ModelFamilyInfo(
      id: 'fallback',
      label: preferredType == 't2v' ? '文生视频' : '图生视频',
      bases: [ModelBaseInfo(id: 'all', label: '全部模型', models: choices)],
    ),
  ];
}

class VideoGenerateScreen extends StatelessWidget {
  const VideoGenerateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        color: AppColors.background,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '视频生成',
              style: TextStyle(color: AppColors.text, fontSize: 24),
            ),
            const SizedBox(height: 16),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border2),
              ),
              child: const TabBar(
                indicatorColor: AppColors.primary,
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [
                  Tab(text: '文生视频'),
                  Tab(text: '图生视频'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Expanded(
              child: TabBarView(children: [VideoT2VTab(), VideoI2VTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoT2VTab extends ConsumerStatefulWidget {
  const VideoT2VTab({super.key});

  @override
  ConsumerState<VideoT2VTab> createState() => _VideoT2VTabState();
}

class _VideoT2VTabState extends ConsumerState<VideoT2VTab> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _negativePromptController =
      TextEditingController();
  final FocusNode _promptFocus = FocusNode();
  VideoGenerateParams _params = const VideoGenerateParams();
  String? _selectedNodeId;
  bool _negativeExpanded = false;
  bool _isSubmitting = false;
  bool _isPolishing = false;
  List<ModelFamilyInfo> _families = [];
  String? _selectedFamilyId;
  String? _selectedBaseId;
  int _selectedRecentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final config = await ConfigFileService().loadVideoSettingsConfig();
    if (!mounted) return;
    setState(() {
      _params = config.defaults.copyWith(taskType: 't2v-A14B');
    });
    await _fetchModels();
    await ref.read(videoNodesProvider.notifier).refreshStatuses();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  List<ComputeNode> get _nodeOptions {
    final nodes = ref.read(videoNodesProvider);
    final bridge = ref.read(videoSettingsProvider).wan2gp;
    final defaultVideoConfig = ref
        .read(apiConfigsProvider)
        .where((c) => c.type == 'video' && c.isDefault)
        .firstOrNull;
    return [
      ComputeNode(
        id: 'local-7861',
        name: '本地7861桥接',
        publicUrl: 'http://127.0.0.1:${bridge.port}',
        createdAt: DateTime.now(),
        isOnline: true,
      ),
      ...nodes,
      if (defaultVideoConfig != null &&
          defaultVideoConfig.url.trim().isNotEmpty &&
          !nodes.any(
            (node) => node.effectiveApiUrl == defaultVideoConfig.url.trim(),
          ))
        ComputeNode(
          id: 'default-video-api',
          name: '${defaultVideoConfig.name}（默认视频API）',
          publicUrl: defaultVideoConfig.url.trim(),
          createdAt: DateTime.now(),
          isOnline: true,
        ),
    ];
  }

  List<ModelBaseInfo> get _currentBases {
    final family = _families
        .where((item) => item.id == _selectedFamilyId)
        .firstOrNull;
    return family?.bases ?? const [];
  }

  List<ModelChoiceInfo> get _currentModels {
    final base = _currentBases
        .where((item) => item.id == _selectedBaseId)
        .firstOrNull;
    return base?.models ?? const [];
  }

  Future<void> _fetchModels() async {
    final candidates = <String>[];
    if (_selectedNodeId != null) {
      final explicit = _nodeOptions
          .where((item) => item.id == _selectedNodeId)
          .firstOrNull;
      if (explicit != null) {
        candidates.add(explicit.effectiveApiUrl);
      }
    }
    for (final node in _nodeOptions) {
      if (!candidates.contains(node.effectiveApiUrl)) {
        candidates.add(node.effectiveApiUrl);
      }
    }
    final videoConfigs = ref
        .read(apiConfigsProvider)
        .where((c) => c.type == 'video');
    final defaultVideoConfig = videoConfigs
        .where((c) => c.isDefault)
        .firstOrNull;
    if (defaultVideoConfig != null) {
      if (!candidates.contains(defaultVideoConfig.url)) {
        candidates.add(defaultVideoConfig.url);
      }
    }

    ModelCatalog? catalog;
    for (final url in candidates.where((item) => item.trim().isNotEmpty)) {
      catalog = await VideoApiService(baseUrl: url).fetchModelCatalog();
      if (catalog != null) break;
    }

    if (!mounted) return;
    final hiddenModelIds = ref
        .read(videoSettingsProvider)
        .hiddenModelIds
        .toSet();
    final filtered = catalog?.filterHiddenModels(hiddenModelIds);
    setState(() {
      _families = filtered != null
          ? _resolveWan2gpFamilies(filtered, preferredType: 't2v')
          : (defaultVideoConfig != null &&
                    defaultVideoConfig.model.trim().isNotEmpty
                ? _buildFallbackFamilies(
                    [
                      ModelInfo(
                        id: defaultVideoConfig.model.trim(),
                        name: defaultVideoConfig.model.trim(),
                        type: 't2v',
                      ),
                    ],
                    't2v',
                  )
                : const []);
      _applyModelHierarchySelection(_params.modelName);
    });
  }

  List<ModelFamilyInfo> _buildFallbackFamilies(
    List<ModelInfo> models,
    String targetType,
  ) {
    final choices = models
        .where((model) => model.type == targetType)
        .map(
          (model) => ModelChoiceInfo(
            id: model.id,
            label: model.name,
            name: model.name,
            type: model.type,
            description: model.description,
            loaded: model.loaded,
          ),
        )
        .toList();
    if (choices.isEmpty) {
      return [];
    }
    return [
      ModelFamilyInfo(
        id: 'fallback',
        label: targetType == 't2v' ? '文生视频' : '图生视频',
        bases: [ModelBaseInfo(id: 'all', label: '全部模型', models: choices)],
      ),
    ];
  }

  void _ensureDialogModelSelection({
    required String? familyId,
    required String? baseId,
    required String? modelId,
    required void Function(String familyId, String baseId, String modelId)
    onReady,
  }) {
    if (_families.isEmpty) return;

    String resolvedFamilyId = familyId ?? _families.first.id;
    final family =
        _families.where((item) => item.id == resolvedFamilyId).firstOrNull ??
        _families.first;
    resolvedFamilyId = family.id;

    String resolvedBaseId = baseId ?? family.bases.first.id;
    final base =
        family.bases.where((item) => item.id == resolvedBaseId).firstOrNull ??
        family.bases.first;
    resolvedBaseId = base.id;

    String resolvedModelId = modelId ?? base.models.first.id;
    final model =
        base.models.where((item) => item.id == resolvedModelId).firstOrNull ??
        base.models.first;
    resolvedModelId = model.id;

    onReady(resolvedFamilyId, resolvedBaseId, resolvedModelId);
  }

  void _applyModelHierarchySelection(String preferredModelId) {
    if (_families.isEmpty) {
      _selectedFamilyId = null;
      _selectedBaseId = null;
      return;
    }

    for (final family in _families) {
      for (final base in family.bases) {
        for (final model in base.models) {
          if (model.id == preferredModelId) {
            _selectedFamilyId = family.id;
            _selectedBaseId = base.id;
            _params = _params.copyWith(modelName: model.id, taskType: model.id);
            return;
          }
        }
      }
    }

    final firstFamily = _families.first;
    final firstBase = firstFamily.bases.first;
    final firstModel = firstBase.models.first;
    _selectedFamilyId = firstFamily.id;
    _selectedBaseId = firstBase.id;
    _params = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
  }

  Future<void> _handleFamilyChanged(String? familyId) async {
    if (familyId == null) return;
    final family = _families.where((item) => item.id == familyId).firstOrNull;
    if (family == null || family.bases.isEmpty) return;
    final firstBase = family.bases.first;
    if (firstBase.models.isEmpty) return;
    final firstModel = firstBase.models.first;
    final next = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
    setState(() {
      _selectedFamilyId = familyId;
      _selectedBaseId = firstBase.id;
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _handleBaseChanged(String? baseId) async {
    if (baseId == null) return;
    final base = _currentBases.where((item) => item.id == baseId).firstOrNull;
    if (base == null || base.models.isEmpty) return;
    final firstModel = base.models.first;
    final next = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
    setState(() {
      _selectedBaseId = baseId;
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _handleModelChanged(String? modelId) async {
    if (modelId == null) return;
    final next = _params.copyWith(modelName: modelId, taskType: modelId);
    setState(() {
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _polishPrompt() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isPolishing) return;

    setState(() => _isPolishing = true);
    final vlm = ref.read(videoSettingsProvider).vlm;
    final service = VideoVlmService(
      apiUrl: vlm.apiUrl,
      apiKey: vlm.apiKey,
      model: vlm.model,
    );
    final result = await service.polishT2VPrompt(text);
    if (!mounted) return;
    setState(() => _isPolishing = false);
    if (!result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage ?? 'AI润色失败')));
      return;
    }
    _promptController.text = result.polishedPrompt;
    _promptController.selection = TextSelection.collapsed(
      offset: _promptController.text.length,
    );
    _promptFocus.requestFocus();
  }

  Future<void> _submit() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(videoTaskProvider.notifier)
          .submitT2V(
            _params.copyWith(
              prompt: prompt,
              negativePrompt: _negativePromptController.text.trim(),
              modelName: _params.modelName,
              taskType: _params.modelName,
            ),
            targetNodeId: _selectedNodeId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文生视频任务已提交')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('提交失败: ${_formatVideoSubmitError(e)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _restoreFromVideo(VideoItem video) {
    final snapshot = video.paramsSnapshot;
    if (snapshot == null) return;
    setState(() {
      _params = snapshot;
      _selectedRecentIndex = _recentVideos.indexOf(video);
      _applyModelHierarchySelection(snapshot.modelName);
    });
    _promptController.text = snapshot.prompt;
    _negativePromptController.text = snapshot.negativePrompt;
  }

  Future<void> _downloadVideo(VideoItem video) async {
    final savedPath = await FileService().saveGeneratedFileWithDialog(
      video.localPath,
      dialogTitle: '导出视频文件',
      allowedExtensions: [video.fileName.split('.').last.toLowerCase()],
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存到: $savedPath')));
  }

  Future<void> _deleteVideo(VideoItem video) async {
    await ref.read(videoGalleryProvider.notifier).deleteVideo(video.id);
    if (!mounted) return;
    setState(() {
      if (_selectedRecentIndex > 0) {
        _selectedRecentIndex--;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除视频')));
  }

  Future<void> _showPreviewContextMenu(
    TapDownDetails details,
    VideoItem video,
  ) async {
    final action = await showMenu<String>(
      context: context,
      color: AppColors.sidebar,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('删除')),
        PopupMenuItem(value: 'download', child: Text('下载')),
        PopupMenuItem(value: 'copy_prompt', child: Text('复制提示词')),
        PopupMenuItem(value: 're_edit', child: Text('重新编辑')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'delete':
        await _deleteVideo(video);
        break;
      case 'download':
        await _downloadVideo(video);
        break;
      case 'copy_prompt':
        await Clipboard.setData(ClipboardData(text: video.prompt));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制提示词')));
        break;
      case 're_edit':
        _restoreFromVideo(video);
        break;
    }
  }

  Future<void> _showParamsDialog() async {
    if (_families.isEmpty) {
      await _fetchModels();
    }

    final resolutionController = TextEditingController(
      text: _params.resolution,
    );
    final frameController = TextEditingController(
      text: _params.frameNum.toString(),
    );
    final stepsController = TextEditingController(
      text: _params.sampleSteps.toString(),
    );
    final cfgController = TextEditingController(
      text: _params.guideScale.toString(),
    );
    final shiftController = TextEditingController(
      text: _params.shiftScale.toString(),
    );
    final seedController = TextEditingController(text: _params.seed.toString());
    String resolutionPreset = _resolvePresetSelection(
      resolutionController.text.trim(),
      _resolutionPresetOptions,
    );
    String framePreset = _resolvePresetSelection(
      frameController.text.trim(),
      _framePresetOptions,
    );
    String stepsPreset = _resolvePresetSelection(
      stepsController.text.trim(),
      _sampleStepsPresetOptions,
    );
    String solver = _params.sampleSolver;
    String? familyId = _selectedFamilyId;
    String? baseId = _selectedBaseId;
    String modelId = _params.modelName;
    bool advancedMode = _params.advancedSettings.isNotEmpty;
    final advancedControllers = _createAdvancedControllers(
      _params.advancedSettings,
    );

    _ensureDialogModelSelection(
      familyId: familyId,
      baseId: baseId,
      modelId: modelId,
      onReady: (resolvedFamilyId, resolvedBaseId, resolvedModelId) {
        familyId = resolvedFamilyId;
        baseId = resolvedBaseId;
        modelId = resolvedModelId;
      },
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final family = _families
              .where((item) => item.id == familyId)
              .firstOrNull;
          final bases = family?.bases ?? const <ModelBaseInfo>[];
          final base = bases.where((item) => item.id == baseId).firstOrNull;
          final models = base?.models ?? const <ModelChoiceInfo>[];
          return AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: const Text('生成参数', style: TextStyle(color: AppColors.text)),
            content: SizedBox(
              width: 820,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildDialogPresetField(
                      label: '分辨率',
                      controller: resolutionController,
                      presets: _resolutionPresetOptions,
                      selectedPreset: resolutionPreset,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          resolutionPreset = value;
                          final option = _findPresetOption(
                            _resolutionPresetOptions,
                            value,
                          );
                          if (option != null) {
                            resolutionController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          resolutionPreset = _resolvePresetSelection(
                            value.trim(),
                            _resolutionPresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogPresetField(
                      label: '帧数 / 时长',
                      controller: frameController,
                      presets: _framePresetOptions,
                      selectedPreset: framePreset,
                      isNumber: true,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          framePreset = value;
                          final option = _findPresetOption(
                            _framePresetOptions,
                            value,
                          );
                          if (option != null) {
                            frameController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          framePreset = _resolvePresetSelection(
                            value.trim(),
                            _framePresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogPresetField(
                      label: '采样步数',
                      controller: stepsController,
                      presets: _sampleStepsPresetOptions,
                      selectedPreset: stepsPreset,
                      isNumber: true,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          stepsPreset = value;
                          final option = _findPresetOption(
                            _sampleStepsPresetOptions,
                            value,
                          );
                          if (option != null) {
                            stepsController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          stepsPreset = _resolvePresetSelection(
                            value.trim(),
                            _sampleStepsPresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField('引导系数', cfgController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogField('偏移量', shiftController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogField('种子', seedController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '采样器',
                      value: solver,
                      items: const ['unipc', 'dpm++', 'euler'],
                      onChanged: (value) =>
                          setDialogState(() => solver = value!),
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型家族',
                      value: familyId,
                      items: _families.map((item) => item.id).toList(),
                      labels: {
                        for (final item in _families) item.id: item.label,
                      },
                      onChanged: (value) {
                        final selected = _families
                            .where((item) => item.id == value)
                            .first;
                        setDialogState(() {
                          familyId = value;
                          baseId = selected.bases.first.id;
                          modelId = selected.bases.first.models.first.id;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型基座',
                      value: baseId,
                      items: bases.map((item) => item.id).toList(),
                      labels: {for (final item in bases) item.id: item.label},
                      onChanged: (value) {
                        final selected = bases
                            .where((item) => item.id == value)
                            .first;
                        setDialogState(() {
                          baseId = value;
                          modelId = selected.models.first.id;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型',
                      value: modelId,
                      items: models.map((item) => item.id).toList(),
                      labels: {for (final item in models) item.id: item.label},
                      onChanged: (value) =>
                          setDialogState(() => modelId = value!),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setDialogState(() => advancedMode = !advancedMode),
                        icon: Icon(
                          advancedMode ? Icons.expand_less : Icons.tune,
                        ),
                        label: Text(advancedMode ? '收起高级模式' : '高级模式'),
                      ),
                    ),
                    if (advancedMode) ...[
                      const SizedBox(height: 8),
                      _buildAdvancedModePanel(
                        controllers: advancedControllers,
                        dialogSetState: setDialogState,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  final next = _params.copyWith(
                    resolution: resolutionController.text.trim(),
                    frameNum:
                        int.tryParse(frameController.text) ?? _params.frameNum,
                    sampleSteps:
                        int.tryParse(stepsController.text) ??
                        _params.sampleSteps,
                    guideScale:
                        double.tryParse(cfgController.text) ??
                        _params.guideScale,
                    shiftScale:
                        double.tryParse(shiftController.text) ??
                        _params.shiftScale,
                    seed: int.tryParse(seedController.text) ?? _params.seed,
                    sampleSolver: solver,
                    modelName: modelId,
                    taskType: modelId,
                    advancedSettings: _collectAdvancedSettings(
                      advancedControllers,
                    ),
                  );
                  await ref
                      .read(videoSettingsProvider.notifier)
                      .updateDefaults(next);
                  if (!mounted) return;
                  setState(() {
                    _params = next;
                    _selectedFamilyId = familyId;
                    _selectedBaseId = baseId;
                  });
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<VideoItem> get _recentVideos => ref
      .watch(videoGalleryProvider)
      .where((item) => item.type == VideoTaskType.t2v)
      .take(10)
      .toList();

  @override
  Widget build(BuildContext context) {
    final videos = _recentVideos;
    final selectedVideo = videos.isEmpty
        ? null
        : videos[_selectedRecentIndex.clamp(0, videos.length - 1)];

    return Column(
      children: [
        Expanded(child: _buildPreviewPanel(selectedVideo)),
        if (videos.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildRecentStrip(videos),
        ],
        const SizedBox(height: 12),
        _buildInputPanel(),
      ],
    );
  }

  Widget _buildPreviewPanel(VideoItem? selectedVideo) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: selectedVideo == null
          ? const Center(
              child: Text(
                '暂无文生视频结果',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : GestureDetector(
              onSecondaryTapDown: (details) =>
                  _showPreviewContextMenu(details, selectedVideo),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14),
                      ),
                      child: VideoPlayerWidget(
                        filePath: selectedVideo.localPath,
                        autoPlay: false,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedVideo.prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => openFullscreenVideo(
                            context,
                            selectedVideo.localPath,
                          ),
                          icon: const Icon(
                            Icons.fullscreen,
                            color: AppColors.text,
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

  Widget _buildRecentStrip(List<VideoItem> videos) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, index) {
          final video = videos[index];
          final selected = index == _selectedRecentIndex;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedRecentIndex = index);
              _restoreFromVideo(video);
            },
            child: Container(
              width: 132,
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border2,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child:
                    video.thumbnailPath != null &&
                        File(video.thumbnailPath!).existsSync()
                    ? Image.file(File(video.thumbnailPath!), fit: BoxFit.cover)
                    : Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.movie_creation_outlined,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: videos.length,
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTinyButton('参数', Icons.settings, _showParamsDialog),
              const SizedBox(width: 8),
              _buildTinyButton(
                _isPolishing ? '润色中' : 'AI润色',
                Icons.auto_awesome,
                _polishPrompt,
              ),
              const SizedBox(width: 8),
              _buildTinyButton(
                _negativeExpanded ? '收起负面词' : '负面提示词',
                Icons.expand_more,
                () => setState(() => _negativeExpanded = !_negativeExpanded),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildNodeSelector()),
            ],
          ),
          if (_negativeExpanded) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _negativePromptController,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                hintText: '输入负面提示词',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBg,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border2),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  focusNode: _promptFocus,
                  minLines: 2,
                  maxLines: 5,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    hintText: '描述想要的动态画面、镜头运动、角色动作、光影节奏...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
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
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSubmitting
                      ? AppColors.primary.withValues(alpha: 0.75)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  onPressed: _isSubmitting ? null : _submit,
                  tooltip: '发送',
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNodeSelector() {
    final nodes = _nodeOptions;
    final currentValue = _selectedNodeId ?? nodes.first.id;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: AppColors.sidebar,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          items: nodes
              .map(
                (node) => DropdownMenuItem(
                  value: node.id,
                  child: Text(
                    '${node.name}${node.isOnline ? " · 在线" : " · 离线"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() => _selectedNodeId = value);
            _fetchModels();
          },
        ),
      ),
    );
  }

  Widget _buildTinyButton(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 15),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoI2VTab extends ConsumerStatefulWidget {
  final String? initialImagePath;
  final String? initialPrompt;
  final bool embedded;
  final VoidCallback? onSubmitted;

  const VideoI2VTab({
    super.key,
    this.initialImagePath,
    this.initialPrompt,
    this.embedded = false,
    this.onSubmitted,
  });

  @override
  ConsumerState<VideoI2VTab> createState() => _VideoI2VTabState();
}

class _VideoI2VTabState extends ConsumerState<VideoI2VTab> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _negativePromptController =
      TextEditingController();
  VideoGenerateParams _params = const VideoGenerateParams(taskType: 'i2v');
  String? _selectedNodeId;
  String? _imagePath;
  bool _negativeExpanded = false;
  bool _isSubmitting = false;
  bool _isPolishing = false;
  List<ModelFamilyInfo> _families = [];
  String? _selectedFamilyId;
  String? _selectedBaseId;
  int _selectedRecentIndex = 0;

  @override
  void initState() {
    super.initState();
    _imagePath = widget.initialImagePath;
    if (widget.initialPrompt != null) {
      _promptController.text = widget.initialPrompt!;
    }
    _initialize();
  }

  Future<void> _initialize() async {
    final config = await ConfigFileService().loadVideoSettingsConfig();
    if (!mounted) return;
    setState(() {
      _params = config.defaults.copyWith(taskType: 'i2v');
    });
    await _fetchModels();
    await ref.read(videoNodesProvider.notifier).refreshStatuses();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativePromptController.dispose();
    super.dispose();
  }

  List<ComputeNode> get _nodeOptions {
    final nodes = ref.read(videoNodesProvider);
    final bridge = ref.read(videoSettingsProvider).wan2gp;
    final defaultVideoConfig = ref
        .read(apiConfigsProvider)
        .where((c) => c.type == 'video' && c.isDefault)
        .firstOrNull;
    return [
      ComputeNode(
        id: 'local-7861',
        name: '本地7861桥接',
        publicUrl: 'http://127.0.0.1:${bridge.port}',
        createdAt: DateTime.now(),
        isOnline: true,
      ),
      ...nodes,
      if (defaultVideoConfig != null &&
          defaultVideoConfig.url.trim().isNotEmpty &&
          !nodes.any(
            (node) => node.effectiveApiUrl == defaultVideoConfig.url.trim(),
          ))
        ComputeNode(
          id: 'default-video-api',
          name: '${defaultVideoConfig.name}（默认视频API）',
          publicUrl: defaultVideoConfig.url.trim(),
          createdAt: DateTime.now(),
          isOnline: true,
        ),
    ];
  }

  List<ModelBaseInfo> get _currentBases {
    final family = _families
        .where((item) => item.id == _selectedFamilyId)
        .firstOrNull;
    return family?.bases ?? const [];
  }

  List<ModelChoiceInfo> get _currentModels {
    final base = _currentBases
        .where((item) => item.id == _selectedBaseId)
        .firstOrNull;
    return base?.models ?? const [];
  }

  Future<void> _fetchModels() async {
    final candidates = <String>[];
    if (_selectedNodeId != null) {
      final explicit = _nodeOptions
          .where((item) => item.id == _selectedNodeId)
          .firstOrNull;
      if (explicit != null) candidates.add(explicit.effectiveApiUrl);
    }
    for (final node in _nodeOptions) {
      if (!candidates.contains(node.effectiveApiUrl)) {
        candidates.add(node.effectiveApiUrl);
      }
    }
    final defaultVideoConfig = ref
        .read(apiConfigsProvider)
        .where((c) => c.type == 'video' && c.isDefault)
        .firstOrNull;
    if (defaultVideoConfig != null) {
      if (!candidates.contains(defaultVideoConfig.url)) {
        candidates.add(defaultVideoConfig.url);
      }
    }

    ModelCatalog? catalog;
    for (final url in candidates.where((item) => item.trim().isNotEmpty)) {
      catalog = await VideoApiService(baseUrl: url).fetchModelCatalog();
      if (catalog != null) break;
    }
    if (!mounted) return;
    final hiddenModelIds = ref
        .read(videoSettingsProvider)
        .hiddenModelIds
        .toSet();
    final filtered = catalog?.filterHiddenModels(hiddenModelIds);
    setState(() {
      _families = filtered != null
          ? _resolveWan2gpFamilies(filtered, preferredType: 'i2v')
          : (defaultVideoConfig != null &&
                    defaultVideoConfig.model.trim().isNotEmpty
                ? _buildFallbackFamilies(
                    [
                      ModelInfo(
                        id: defaultVideoConfig.model.trim(),
                        name: defaultVideoConfig.model.trim(),
                        type: 'i2v',
                      ),
                    ],
                    'i2v',
                  )
                : const []);
      _applyModelHierarchySelection(_params.modelName);
    });
  }

  List<ModelFamilyInfo> _buildFallbackFamilies(
    List<ModelInfo> models,
    String targetType,
  ) {
    final choices = models
        .where((model) => model.type == targetType)
        .map(
          (model) => ModelChoiceInfo(
            id: model.id,
            label: model.name,
            name: model.name,
            type: model.type,
            description: model.description,
            loaded: model.loaded,
          ),
        )
        .toList();
    if (choices.isEmpty) {
      return [];
    }
    return [
      ModelFamilyInfo(
        id: 'fallback',
        label: targetType == 't2v' ? '文生视频' : '图生视频',
        bases: [ModelBaseInfo(id: 'all', label: '全部模型', models: choices)],
      ),
    ];
  }

  void _ensureDialogModelSelection({
    required String? familyId,
    required String? baseId,
    required String? modelId,
    required void Function(String familyId, String baseId, String modelId)
    onReady,
  }) {
    if (_families.isEmpty) return;

    String resolvedFamilyId = familyId ?? _families.first.id;
    final family =
        _families.where((item) => item.id == resolvedFamilyId).firstOrNull ??
        _families.first;
    resolvedFamilyId = family.id;

    String resolvedBaseId = baseId ?? family.bases.first.id;
    final base =
        family.bases.where((item) => item.id == resolvedBaseId).firstOrNull ??
        family.bases.first;
    resolvedBaseId = base.id;

    String resolvedModelId = modelId ?? base.models.first.id;
    final model =
        base.models.where((item) => item.id == resolvedModelId).firstOrNull ??
        base.models.first;
    resolvedModelId = model.id;

    onReady(resolvedFamilyId, resolvedBaseId, resolvedModelId);
  }

  void _applyModelHierarchySelection(String preferredModelId) {
    if (_families.isEmpty) {
      _selectedFamilyId = null;
      _selectedBaseId = null;
      return;
    }

    for (final family in _families) {
      for (final base in family.bases) {
        for (final model in base.models) {
          if (model.id == preferredModelId) {
            _selectedFamilyId = family.id;
            _selectedBaseId = base.id;
            _params = _params.copyWith(modelName: model.id, taskType: model.id);
            return;
          }
        }
      }
    }

    final firstFamily = _families.first;
    final firstBase = firstFamily.bases.first;
    final firstModel = firstBase.models.first;
    _selectedFamilyId = firstFamily.id;
    _selectedBaseId = firstBase.id;
    _params = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
  }

  Future<void> _handleFamilyChanged(String? familyId) async {
    if (familyId == null) return;
    final family = _families.where((item) => item.id == familyId).firstOrNull;
    if (family == null || family.bases.isEmpty) return;
    final firstBase = family.bases.first;
    if (firstBase.models.isEmpty) return;
    final firstModel = firstBase.models.first;
    final next = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
    setState(() {
      _selectedFamilyId = familyId;
      _selectedBaseId = firstBase.id;
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _handleBaseChanged(String? baseId) async {
    if (baseId == null) return;
    final base = _currentBases.where((item) => item.id == baseId).firstOrNull;
    if (base == null || base.models.isEmpty) return;
    final firstModel = base.models.first;
    final next = _params.copyWith(
      modelName: firstModel.id,
      taskType: firstModel.id,
    );
    setState(() {
      _selectedBaseId = baseId;
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _handleModelChanged(String? modelId) async {
    if (modelId == null) return;
    final next = _params.copyWith(modelName: modelId, taskType: modelId);
    setState(() {
      _params = next;
    });
    await ref.read(videoSettingsProvider.notifier).updateDefaults(next);
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _imagePath = result.files.single.path);
    }
  }

  Future<void> _polishPrompt() async {
    if (_imagePath == null || _isPolishing) return;
    setState(() => _isPolishing = true);
    final vlm = ref.read(videoSettingsProvider).vlm;
    final service = VideoVlmService(
      apiUrl: vlm.apiUrl,
      apiKey: vlm.apiKey,
      model: vlm.model,
    );
    final result = await service.polishI2VPrompt(
      _imagePath!,
      _promptController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isPolishing = false);
    if (!result.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage ?? 'VLM解析失败')));
      return;
    }
    _promptController.text = result.polishedPrompt;
  }

  Future<void> _submit() async {
    if (_imagePath == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(videoTaskProvider.notifier)
          .submitI2V(
            _params.copyWith(
              prompt: _promptController.text.trim(),
              negativePrompt: _negativePromptController.text.trim(),
              modelName: _params.modelName,
              taskType: _params.modelName,
            ),
            _imagePath!,
            targetNodeId: _selectedNodeId,
            writeToCurrentSession: widget.embedded,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图生视频任务已提交')));
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('提交失败: ${_formatVideoSubmitError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _restoreFromVideo(VideoItem video) {
    final snapshot = video.paramsSnapshot;
    if (snapshot == null) return;
    setState(() {
      _params = snapshot;
      _imagePath = video.sourceImagePath ?? _imagePath;
      _selectedRecentIndex = _recentVideos.indexOf(video);
      _applyModelHierarchySelection(snapshot.modelName);
    });
    _promptController.text = snapshot.prompt;
    _negativePromptController.text = snapshot.negativePrompt;
  }

  Future<void> _downloadVideo(VideoItem video) async {
    final savedPath = await FileService().saveGeneratedFileWithDialog(
      video.localPath,
      dialogTitle: '导出视频文件',
      allowedExtensions: [video.fileName.split('.').last.toLowerCase()],
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存到: $savedPath')));
  }

  Future<void> _deleteVideo(VideoItem video) async {
    await ref.read(videoGalleryProvider.notifier).deleteVideo(video.id);
    if (!mounted) return;
    setState(() {
      if (_selectedRecentIndex > 0) {
        _selectedRecentIndex--;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除视频')));
  }

  Future<void> _showPreviewContextMenu(
    TapDownDetails details,
    VideoItem video,
  ) async {
    final action = await showMenu<String>(
      context: context,
      color: AppColors.sidebar,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('删除')),
        PopupMenuItem(value: 'download', child: Text('下载')),
        PopupMenuItem(value: 'copy_prompt', child: Text('复制提示词')),
        PopupMenuItem(value: 're_edit', child: Text('重新编辑')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'delete':
        await _deleteVideo(video);
        break;
      case 'download':
        await _downloadVideo(video);
        break;
      case 'copy_prompt':
        await Clipboard.setData(ClipboardData(text: video.prompt));
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已复制提示词')));
        break;
      case 're_edit':
        _restoreFromVideo(video);
        break;
    }
  }

  Future<void> _showParamsDialog() async {
    if (_families.isEmpty) {
      await _fetchModels();
    }

    final resolutionController = TextEditingController(
      text: _params.resolution,
    );
    final frameController = TextEditingController(
      text: _params.frameNum.toString(),
    );
    final stepsController = TextEditingController(
      text: _params.sampleSteps.toString(),
    );
    final cfgController = TextEditingController(
      text: _params.guideScale.toString(),
    );
    final shiftController = TextEditingController(
      text: _params.shiftScale.toString(),
    );
    final seedController = TextEditingController(text: _params.seed.toString());
    String resolutionPreset = _resolvePresetSelection(
      resolutionController.text.trim(),
      _resolutionPresetOptions,
    );
    String framePreset = _resolvePresetSelection(
      frameController.text.trim(),
      _framePresetOptions,
    );
    String stepsPreset = _resolvePresetSelection(
      stepsController.text.trim(),
      _sampleStepsPresetOptions,
    );
    String solver = _params.sampleSolver;
    String? familyId = _selectedFamilyId;
    String? baseId = _selectedBaseId;
    String modelId = _params.modelName;
    bool advancedMode = _params.advancedSettings.isNotEmpty;
    final advancedControllers = _createAdvancedControllers(
      _params.advancedSettings,
    );

    _ensureDialogModelSelection(
      familyId: familyId,
      baseId: baseId,
      modelId: modelId,
      onReady: (resolvedFamilyId, resolvedBaseId, resolvedModelId) {
        familyId = resolvedFamilyId;
        baseId = resolvedBaseId;
        modelId = resolvedModelId;
      },
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final family = _families
              .where((item) => item.id == familyId)
              .firstOrNull;
          final bases = family?.bases ?? const <ModelBaseInfo>[];
          final base = bases.where((item) => item.id == baseId).firstOrNull;
          final models = base?.models ?? const <ModelChoiceInfo>[];
          return AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: const Text('生成参数', style: TextStyle(color: AppColors.text)),
            content: SizedBox(
              width: 820,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildDialogPresetField(
                      label: '分辨率',
                      controller: resolutionController,
                      presets: _resolutionPresetOptions,
                      selectedPreset: resolutionPreset,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          resolutionPreset = value;
                          final option = _findPresetOption(
                            _resolutionPresetOptions,
                            value,
                          );
                          if (option != null) {
                            resolutionController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          resolutionPreset = _resolvePresetSelection(
                            value.trim(),
                            _resolutionPresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogPresetField(
                      label: '帧数 / 时长',
                      controller: frameController,
                      presets: _framePresetOptions,
                      selectedPreset: framePreset,
                      isNumber: true,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          framePreset = value;
                          final option = _findPresetOption(
                            _framePresetOptions,
                            value,
                          );
                          if (option != null) {
                            frameController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          framePreset = _resolvePresetSelection(
                            value.trim(),
                            _framePresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogPresetField(
                      label: '采样步数',
                      controller: stepsController,
                      presets: _sampleStepsPresetOptions,
                      selectedPreset: stepsPreset,
                      isNumber: true,
                      onPresetChanged: (value) {
                        setDialogState(() {
                          stepsPreset = value;
                          final option = _findPresetOption(
                            _sampleStepsPresetOptions,
                            value,
                          );
                          if (option != null) {
                            stepsController.text = option.value;
                          }
                        });
                      },
                      onTextChanged: (value) {
                        setDialogState(() {
                          stepsPreset = _resolvePresetSelection(
                            value.trim(),
                            _sampleStepsPresetOptions,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField('引导系数', cfgController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogField('偏移量', shiftController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogField('种子', seedController, isNumber: true),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '采样器',
                      value: solver,
                      items: const ['unipc', 'dpm++', 'euler'],
                      onChanged: (value) =>
                          setDialogState(() => solver = value!),
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型家族',
                      value: familyId,
                      items: _families.map((item) => item.id).toList(),
                      labels: {
                        for (final item in _families) item.id: item.label,
                      },
                      onChanged: (value) {
                        final selected = _families
                            .where((item) => item.id == value)
                            .first;
                        setDialogState(() {
                          familyId = value;
                          baseId = selected.bases.first.id;
                          modelId = selected.bases.first.models.first.id;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型基座',
                      value: baseId,
                      items: bases.map((item) => item.id).toList(),
                      labels: {for (final item in bases) item.id: item.label},
                      onChanged: (value) {
                        final selected = bases
                            .where((item) => item.id == value)
                            .first;
                        setDialogState(() {
                          baseId = value;
                          modelId = selected.models.first.id;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDialogSelect<String>(
                      label: '模型',
                      value: modelId,
                      items: models.map((item) => item.id).toList(),
                      labels: {for (final item in models) item.id: item.label},
                      onChanged: (value) =>
                          setDialogState(() => modelId = value!),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setDialogState(() => advancedMode = !advancedMode),
                        icon: Icon(
                          advancedMode ? Icons.expand_less : Icons.tune,
                        ),
                        label: Text(advancedMode ? '收起高级模式' : '高级模式'),
                      ),
                    ),
                    if (advancedMode) ...[
                      const SizedBox(height: 8),
                      _buildAdvancedModePanel(
                        controllers: advancedControllers,
                        dialogSetState: setDialogState,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () async {
                  final next = _params.copyWith(
                    resolution: resolutionController.text.trim(),
                    frameNum:
                        int.tryParse(frameController.text) ?? _params.frameNum,
                    sampleSteps:
                        int.tryParse(stepsController.text) ??
                        _params.sampleSteps,
                    guideScale:
                        double.tryParse(cfgController.text) ??
                        _params.guideScale,
                    shiftScale:
                        double.tryParse(shiftController.text) ??
                        _params.shiftScale,
                    seed: int.tryParse(seedController.text) ?? _params.seed,
                    sampleSolver: solver,
                    modelName: modelId,
                    taskType: modelId,
                    advancedSettings: _collectAdvancedSettings(
                      advancedControllers,
                    ),
                  );
                  await ref
                      .read(videoSettingsProvider.notifier)
                      .updateDefaults(next);
                  if (!mounted) return;
                  setState(() {
                    _params = next;
                    _selectedFamilyId = familyId;
                    _selectedBaseId = baseId;
                  });
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<VideoItem> get _recentVideos => ref
      .watch(videoGalleryProvider)
      .where((item) => item.type == VideoTaskType.i2v)
      .take(10)
      .toList();

  @override
  Widget build(BuildContext context) {
    final videos = _recentVideos;
    final selectedVideo = videos.isEmpty
        ? null
        : videos[_selectedRecentIndex.clamp(0, videos.length - 1)];

    return Column(
      children: [
        Expanded(child: _buildPreviewPanel(selectedVideo)),
        if (videos.isNotEmpty && !widget.embedded) ...[
          const SizedBox(height: 10),
          _buildRecentStrip(videos),
        ],
        const SizedBox(height: 12),
        _buildInputPanel(),
      ],
    );
  }

  Widget _buildPreviewPanel(VideoItem? selectedVideo) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: _imagePath == null && selectedVideo == null
          ? const Center(
              child: Text(
                '上传参考图后即可开始图生视频',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: _imagePath == null
                      ? const SizedBox.shrink()
                      : ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(14),
                          ),
                          child: Image.file(
                            File(_imagePath!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: selectedVideo == null
                      ? Container(
                          color: Colors.black,
                          alignment: Alignment.center,
                          child: const Text(
                            '提交后在这里预览生成视频',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : GestureDetector(
                          onSecondaryTapDown: (details) =>
                              _showPreviewContextMenu(details, selectedVideo),
                          child: VideoPlayerWidget(
                            filePath: selectedVideo.localPath,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildRecentStrip(List<VideoItem> videos) {
    return SizedBox(
      height: 82,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, index) {
          final video = videos[index];
          final selected = index == _selectedRecentIndex;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedRecentIndex = index);
              _restoreFromVideo(video);
            },
            child: Container(
              width: 132,
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border2,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child:
                    video.thumbnailPath != null &&
                        File(video.thumbnailPath!).existsSync()
                    ? Image.file(File(video.thumbnailPath!), fit: BoxFit.cover)
                    : Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.movie_creation_outlined,
                          color: Colors.white70,
                        ),
                      ),
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: videos.length,
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTinyButton('参数', Icons.settings, _showParamsDialog),
              const SizedBox(width: 8),
              _buildTinyButton(
                _isPolishing ? '解析中' : 'VLM解析',
                Icons.auto_awesome,
                _polishPrompt,
              ),
              const SizedBox(width: 8),
              _buildTinyButton(
                _negativeExpanded ? '收起负面词' : '负面提示词',
                Icons.expand_more,
                () => setState(() => _negativeExpanded = !_negativeExpanded),
              ),
              const SizedBox(width: 8),
              _buildTinyButton('上传图片', Icons.image, _pickImage),
              const SizedBox(width: 8),
              Expanded(child: _buildNodeSelector()),
            ],
          ),
          if (_negativeExpanded) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _negativePromptController,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                hintText: '输入负面提示词',
                hintStyle: TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.inputBg,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border2),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  minLines: 2,
                  maxLines: widget.embedded ? 4 : 5,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    hintText: '描述希望从这张图延展出的动作、镜头、节奏和氛围...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
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
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isSubmitting
                      ? AppColors.primary.withValues(alpha: 0.75)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  onPressed: _isSubmitting ? null : _submit,
                  tooltip: '发送',
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNodeSelector() {
    final nodes = _nodeOptions;
    final currentValue = _selectedNodeId ?? nodes.first.id;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: AppColors.sidebar,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
          items: nodes
              .map(
                (node) => DropdownMenuItem(
                  value: node.id,
                  child: Text(
                    '${node.name}${node.isOnline ? " · 在线" : " · 离线"}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() => _selectedNodeId = value);
            _fetchModels();
          },
        ),
      ),
    );
  }

  Widget _buildTinyButton(String text, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 15),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildDialogField(
  String label,
  TextEditingController controller, {
  bool isNumber = false,
  int maxLines = 1,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.multiline,
        minLines: maxLines > 1 ? maxLines : 1,
        maxLines: maxLines,
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
        ),
      ),
    ],
  );
}

Widget _buildDialogPresetField({
  required String label,
  required TextEditingController controller,
  required List<_PresetOption> presets,
  required String selectedPreset,
  required ValueChanged<String> onPresetChanged,
  required ValueChanged<String> onTextChanged,
  bool isNumber = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selectedPreset,
            isExpanded: true,
            dropdownColor: AppColors.sidebar,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            items: [
              ...presets.map(
                (preset) => DropdownMenuItem(
                  value: preset.value,
                  child: Text(preset.label),
                ),
              ),
              const DropdownMenuItem(
                value: _customPresetValue,
                child: Text('手动输入'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onPresetChanged(value);
              }
            },
          ),
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: AppColors.text),
        onChanged: onTextChanged,
        decoration: const InputDecoration(
          filled: true,
          fillColor: AppColors.inputBg,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border2),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.border2),
          ),
        ),
      ),
    ],
  );
}

const String _customPresetValue = '__custom__';

const List<_PresetOption> _resolutionPresetOptions = [
  _PresetOption('1280*720', '1280×720 (横屏720P)'),
  _PresetOption('720*1280', '720×1280 (竖屏720P)'),
  _PresetOption('1024*1024', '1024×1024 (方图)'),
  _PresetOption('1920*1080', '1920×1080 (横屏1080P)'),
  _PresetOption('1080*1920', '1080×1920 (竖屏1080P)'),
];

const List<_PresetOption> _framePresetOptions = [
  _PresetOption('49', '49 帧 (短镜头)'),
  _PresetOption('81', '81 帧 (常用默认)'),
  _PresetOption('121', '121 帧 (中等时长)'),
  _PresetOption('161', '161 帧 (长一点)'),
  _PresetOption('241', '241 帧 (长视频)'),
];

const List<_PresetOption> _sampleStepsPresetOptions = [
  _PresetOption('20', '20 步 (快速)'),
  _PresetOption('30', '30 步'),
  _PresetOption('40', '40 步'),
  _PresetOption('50', '50 步 (常用默认)'),
  _PresetOption('60', '60 步 (高质量)'),
];

String _resolvePresetSelection(String value, List<_PresetOption> presets) {
  return presets.any((preset) => preset.value == value)
      ? value
      : _customPresetValue;
}

_PresetOption? _findPresetOption(List<_PresetOption> presets, String value) {
  return presets.where((preset) => preset.value == value).firstOrNull;
}

class _PresetOption {
  final String value;
  final String label;

  const _PresetOption(this.value, this.label);
}

const List<_AdvancedFieldSpec> _generalAdvancedFields = [
  _AdvancedFieldSpec('guidance_scale', 'Guidance (CFG)'),
  _AdvancedFieldSpec('guidance2_scale', 'Guidance2 (CFG)'),
  _AdvancedFieldSpec('guidance3_scale', 'Guidance3 (CFG)'),
  _AdvancedFieldSpec('switch_threshold', 'Switch Threshold', isInteger: true),
  _AdvancedFieldSpec(
    'switch_threshold2',
    'Switch Threshold 2',
    isInteger: true,
  ),
  _AdvancedFieldSpec('flow_shift', 'Shift Scale'),
  _AdvancedFieldSpec('denoising_strength', 'Denoising Strength'),
  _AdvancedFieldSpec('masking_strength', 'Masking Strength'),
  _AdvancedFieldSpec('input_video_strength', 'Input Video Strength'),
  _AdvancedFieldSpec(
    'image_refs_relative_size',
    'Image Ref Relative Size',
    isInteger: true,
  ),
];

const List<_AdvancedFieldSpec> _lorasAdvancedFields = [
  _AdvancedFieldSpec('activated_loras', 'Activated Loras', multiline: true),
  _AdvancedFieldSpec('loras_multipliers', 'Loras Multipliers'),
];

const List<_AdvancedFieldSpec> _postProcessingAdvancedFields = [
  _AdvancedFieldSpec('spatial_upsampling', 'Spatial Upsampling'),
  _AdvancedFieldSpec('temporal_upsampling', 'Temporal Upsampling'),
  _AdvancedFieldSpec(
    'film_grain_intensity',
    'Film Grain Intensity',
    isInteger: true,
  ),
  _AdvancedFieldSpec('film_grain_saturation', 'Film Grain Saturation'),
];

const List<_AdvancedFieldSpec> _audioAdvancedFields = [
  _AdvancedFieldSpec('audio_prompt_type', 'Audio Prompt Type'),
  _AdvancedFieldSpec('audio_guide', 'Audio Guide Path'),
  _AdvancedFieldSpec('audio_guide2', 'Audio Guide 2 Path'),
  _AdvancedFieldSpec('audio_source', 'Custom Audio Path'),
  _AdvancedFieldSpec('audio_guidance_scale', 'Audio Guidance Scale'),
  _AdvancedFieldSpec('audio_scale', 'Audio Scale'),
  _AdvancedFieldSpec('temperature', 'Temperature'),
  _AdvancedFieldSpec('top_p', 'Top-p'),
  _AdvancedFieldSpec('top_k', 'Top-k', isInteger: true),
];

const List<_AdvancedFieldSpec> _qualityAdvancedFields = [
  _AdvancedFieldSpec('embedded_guidance_scale', 'Embedded Guidance Scale'),
  _AdvancedFieldSpec('alt_guidance_scale', 'Alt Guidance Scale'),
  _AdvancedFieldSpec('alt_scale', 'Alt Scale'),
  _AdvancedFieldSpec('control_net_weight', 'Control Net Weight'),
  _AdvancedFieldSpec('control_net_weight2', 'Control Net Weight 2'),
  _AdvancedFieldSpec('control_net_weight_alt', 'Control Net Weight Alt'),
  _AdvancedFieldSpec('NAG_scale', 'NAG Scale'),
  _AdvancedFieldSpec('NAG_tau', 'NAG Tau'),
  _AdvancedFieldSpec('NAG_alpha', 'NAG Alpha'),
];

const List<_AdvancedFieldSpec> _slidingWindowAdvancedFields = [
  _AdvancedFieldSpec(
    'sliding_window_size',
    'Sliding Window Size',
    isInteger: true,
  ),
  _AdvancedFieldSpec(
    'sliding_window_overlap',
    'Sliding Window Overlap',
    isInteger: true,
  ),
  _AdvancedFieldSpec(
    'sliding_window_color_correction_strength',
    'Color Correction Strength',
  ),
  _AdvancedFieldSpec(
    'sliding_window_overlap_noise',
    'Overlap Noise',
    isInteger: true,
  ),
  _AdvancedFieldSpec(
    'sliding_window_discard_last_frames',
    'Discard Last Frames',
    isInteger: true,
  ),
];

const List<_AdvancedFieldSpec> _miscAdvancedFields = [
  _AdvancedFieldSpec('mask_expand', 'Mask Expand', isInteger: true),
  _AdvancedFieldSpec('pace', 'Pace'),
  _AdvancedFieldSpec('exaggeration', 'Exaggeration'),
];

Map<String, TextEditingController> _createAdvancedControllers(
  Map<String, dynamic> settings,
) {
  const specs = [
    ..._generalAdvancedFields,
    ..._lorasAdvancedFields,
    ..._postProcessingAdvancedFields,
    ..._audioAdvancedFields,
    ..._qualityAdvancedFields,
    ..._slidingWindowAdvancedFields,
    ..._miscAdvancedFields,
  ];

  final controllers = <String, TextEditingController>{};
  for (final spec in specs) {
    final rawValue = settings[spec.key];
    final text = rawValue is List
        ? rawValue.join('\n')
        : rawValue?.toString() ?? '';
    controllers[spec.key] = TextEditingController(text: text);
  }
  return controllers;
}

Map<String, dynamic> _collectAdvancedSettings(
  Map<String, TextEditingController> controllers,
) {
  final result = <String, dynamic>{};
  const specs = [
    ..._generalAdvancedFields,
    ..._lorasAdvancedFields,
    ..._postProcessingAdvancedFields,
    ..._audioAdvancedFields,
    ..._qualityAdvancedFields,
    ..._slidingWindowAdvancedFields,
    ..._miscAdvancedFields,
  ];

  for (final spec in specs) {
    final controller = controllers[spec.key];
    if (controller == null) continue;
    final raw = controller.text.trim();
    if (raw.isEmpty) continue;

    if (spec.key == 'activated_loras') {
      final values = raw
          .split(RegExp(r'[\r\n,]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) {
        result[spec.key] = values;
      }
      continue;
    }

    if (spec.isInteger) {
      final parsed = int.tryParse(raw);
      if (parsed != null) {
        result[spec.key] = parsed;
        continue;
      }
    } else {
      final parsed = double.tryParse(raw);
      if (parsed != null) {
        result[spec.key] = parsed;
        continue;
      }
    }

    result[spec.key] = raw;
  }
  return result;
}

Widget _buildAdvancedModePanel({
  required Map<String, TextEditingController> controllers,
  required StateSetter dialogSetState,
}) {
  return DefaultTabController(
    length: 7,
    child: SizedBox(
      height: 380,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'General'),
              Tab(text: 'Loras'),
              Tab(text: 'Post Processing'),
              Tab(text: 'Audio'),
              Tab(text: 'Quality'),
              Tab(text: 'Sliding Window'),
              Tab(text: 'Misc.'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _buildAdvancedSection(_generalAdvancedFields, controllers),
                _buildAdvancedSection(_lorasAdvancedFields, controllers),
                _buildAdvancedSection(
                  _postProcessingAdvancedFields,
                  controllers,
                ),
                _buildAdvancedSection(_audioAdvancedFields, controllers),
                _buildAdvancedSection(_qualityAdvancedFields, controllers),
                _buildAdvancedSection(
                  _slidingWindowAdvancedFields,
                  controllers,
                ),
                _buildAdvancedSection(_miscAdvancedFields, controllers),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildAdvancedSection(
  List<_AdvancedFieldSpec> specs,
  Map<String, TextEditingController> controllers,
) {
  return SingleChildScrollView(
    child: Column(
      children: specs
          .map(
            (spec) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildDialogField(
                spec.label,
                controllers[spec.key]!,
                isNumber: !spec.multiline,
                maxLines: spec.multiline ? 4 : 1,
              ),
            ),
          )
          .toList(),
    ),
  );
}

Widget _buildDialogSelect<T>({
  required String label,
  required T? value,
  required List<T> items,
  required ValueChanged<T?> onChanged,
  Map<T, String>? labels,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.contains(value)
                ? value
                : (items.isNotEmpty ? items.first : null),
            dropdownColor: AppColors.sidebar,
            isExpanded: true,
            style: const TextStyle(color: AppColors.text),
            items: items
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labels?[item] ?? item.toString()),
                  ),
                )
                .toList(),
            onChanged: items.isEmpty ? null : onChanged,
          ),
        ),
      ),
    ],
  );
}

String _formatVideoSubmitError(Object error) {
  var text = error.toString().trim();
  const prefixes = ['Exception: ', 'Bad state: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }
  return text;
}

class _AdvancedFieldSpec {
  final String key;
  final String label;
  final bool isInteger;
  final bool multiline;

  const _AdvancedFieldSpec(
    this.key,
    this.label, {
    this.isInteger = false,
    this.multiline = false,
  });
}

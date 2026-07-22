import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../constants/app_colors.dart';
import '../services/film_workshop_service.dart';
import '../services/film_workshop_storage_service.dart';
import '../services/storyboard_service.dart';
import '../services/config_file_service.dart';
import '../services/generate_logic_service.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';
import '../providers/generate_params_provider.dart';
import '../providers/film_workshop_provider.dart';
import '../providers/film_project_provider.dart';
import '../providers/asset_provider.dart';
import '../models/api_config.dart';
import '../models/asset.dart';
import '../models/film_scene_asset.dart';
import '../controllers/film_workshop_controller.dart';
import '../models/shot.dart';
import '../widgets/film_tabs_bar.dart';
import '../providers/background_task_provider.dart';
import '../providers/matching_task_provider.dart';
import '../utils/gpt_image_generation_preset.dart';
import '../utils/z_image_base_generation_preset.dart';

typedef _FilmWorkshopImageParamsChanged =
    void Function({
      required String selectedModel,
      required String selectedAspectRatio,
      required String selectedImageSize,
      required String selectedImageQuality,
      required int sampleSteps,
    });

class _FilmWorkshopImageParamSupport {
  static const Map<String, String> imageModelLabels = {
    'gemini-3-pro-image-preview': 'Gemini 3 Pro Image Preview',
    'gemini-3.1-flash-image-preview': 'Gemini 3.1 Flash Image Preview',
    'nano-banana': 'Nano Banana',
    'nano-banana-2': 'Nano Banana 2',
    'nano-banana-fast': 'Nano Banana Fast',
    'nano-banana-pro': 'Nano Banana Pro',
    'nano-banana-pro-4k-vip': 'Nano Banana Pro 4K VIP',
    'nano-banana-pro-cl': 'Nano Banana Pro CL',
    'nano-banana-pro-vip': 'Nano Banana Pro VIP',
    'nano-banana-pro-vt': 'Nano Banana Pro VT',
    'gpt-image-2': 'GPT Image 2',
    'gpt-image-2-vip': 'GPT Image 2 VIP',
    'z_image_base': 'Z-Image Base 6B',
  };

  static const List<String> imageModelItems = [
    'gemini-3-pro-image-preview',
    'gemini-3.1-flash-image-preview',
    'divider',
    'z_image_base',
    'divider',
    'nano-banana',
    'nano-banana-2',
    'nano-banana-fast',
    'nano-banana-pro',
    'nano-banana-pro-4k-vip',
    'nano-banana-pro-cl',
    'nano-banana-pro-vip',
    'nano-banana-pro-vt',
    'divider',
    'gpt-image-2',
    'gpt-image-2-vip',
  ];

  static const List<String> defaultAspectRatioItems = [
    'auto',
    '16:9',
    '9:16',
    '1:1',
    '4:5',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];

  static bool isZImageBaseModel(String model) {
    return ZImageBaseGenerationPreset.isModel(model);
  }

  static List<String> resolveAspectRatioItems(String model) {
    if (isZImageBaseModel(model)) {
      return ZImageBaseGenerationPreset.aspectRatios;
    }
    if (GptImageGenerationPreset.isModel(model)) {
      return GptImageGenerationPreset.getAspectRatioOptions(model);
    }
    return defaultAspectRatioItems;
  }

  static List<String> resolveImageSizeItems(String model, String aspectRatio) {
    if (GptImageGenerationPreset.usesResolutionDropdown(model)) {
      return GptImageGenerationPreset.getImageSizeOptions(model, aspectRatio);
    }
    return const ['1K', '2K', '4K'];
  }

  static Map<String, String>? resolveImageSizeLabels(
    String model,
    String aspectRatio,
  ) {
    if (isZImageBaseModel(model)) {
      return ZImageBaseGenerationPreset.imageSizeLabels;
    }
    if (GptImageGenerationPreset.usesResolutionDropdown(model)) {
      return GptImageGenerationPreset.getResolutionLabels(model, aspectRatio);
    }
    return null;
  }

  static bool showImageQualitySelect(String model) {
    return GptImageGenerationPreset.supportsQuality(model);
  }

  static Map<String, dynamic> normalizeParams({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
    int? sampleSteps,
  }) {
    final normalizedImageQuality = GptImageGenerationPreset.normalizeQuality(
      imageQuality,
    );

    if (isZImageBaseModel(model)) {
      final normalizedImageSize = ZImageBaseGenerationPreset.normalizeImageSize(
        imageSize,
      );
      return {
        'aspectRatio': ZImageBaseGenerationPreset.normalizeAspectRatio(
          aspectRatio,
        ),
        'imageSize': normalizedImageSize,
        'imageQuality': normalizedImageQuality,
        'sampleSteps': ZImageBaseGenerationPreset.normalizeSampleSteps(
          sampleSteps,
          imageSize: normalizedImageSize,
        ),
      };
    }

    final isGptModel = GptImageGenerationPreset.isModel(model);
    final normalizedAspectRatio = isGptModel
        ? GptImageGenerationPreset.normalizeAspectRatio(aspectRatio)
        : defaultAspectRatioItems.contains(aspectRatio)
        ? aspectRatio
        : 'auto';
    final normalizedImageSize = isGptModel
        ? GptImageGenerationPreset.normalizeImageSize(
            model: model,
            aspectRatio: normalizedAspectRatio,
            value: imageSize,
          )
        : GptImageGenerationPreset.normalizeImageSize(
            model: GptImageGenerationPreset.standardModel,
            aspectRatio: normalizedAspectRatio,
            value: imageSize,
          );
    return {
      'aspectRatio': normalizedAspectRatio,
      'imageSize': normalizedImageSize,
      'imageQuality': normalizedImageQuality,
      'sampleSteps': ZImageBaseGenerationPreset.normalizeSampleSteps(
        sampleSteps,
        imageSize: normalizedImageSize,
      ),
    };
  }
}

class FilmWorkshopScreen extends ConsumerStatefulWidget {
  const FilmWorkshopScreen({super.key});

  @override
  ConsumerState<FilmWorkshopScreen> createState() => _FilmWorkshopScreenState();
}

class _FilmWorkshopScreenState extends ConsumerState<FilmWorkshopScreen> {
  late final FilmWorkshopService _service;
  final FilmWorkshopStorageService _storageService =
      FilmWorkshopStorageService();
  final List<String> _referenceImages = List.generate(14, (_) => '');
  final Map<int, String> _imageRemarks = {};
  String? _selectedStoryboard;
  String _selectedModel = 'nano-banana-fast';
  String _selectedAspectRatio = 'auto';
  String _selectedImageSize = '1K';
  String _selectedImageQuality = 'auto';
  int _zImageBaseSampleSteps = 30;
  final _zImageSampleStepsController = TextEditingController();
  int? _currentBatchNumber; // 当前批次号，批量生成时共享
  String _lastScriptContent = ''; // 记录上次的剧本内容

  int? _editingIndex;
  final _editController = TextEditingController();
  final _titleController = TextEditingController(text: 'A001');
  final _systemPromptController = TextEditingController();
  final _fullScriptController = TextEditingController();
  bool _isEditingTitle = false;
  final Set<int> _selectedShotIndices = {};
  bool _matchOnlyUnmatched = true; // 默认只匹配未匹配的镜头
  bool _splitMinimized = false; // 拆解分镜最小化
  final _centerScrollController = ScrollController();

  String _getCircledNumber(int number) {
    const circledNumbers = [
      '①',
      '②',
      '③',
      '④',
      '⑤',
      '⑥',
      '⑦',
      '⑧',
      '⑨',
      '⑩',
      '⑪',
      '⑫',
      '⑬',
      '⑭',
      '⑮',
      '⑯',
      '⑰',
      '⑱',
      '⑲',
      '⑳',
    ];
    if (number >= 1 && number <= 20) {
      return circledNumbers[number - 1];
    }
    return number.toString();
  }

  bool get _isZImageBaseSelected =>
      _FilmWorkshopImageParamSupport.isZImageBaseModel(_selectedModel);

  List<String> get _activeAspectRatioItems =>
      _FilmWorkshopImageParamSupport.resolveAspectRatioItems(_selectedModel);

  List<String> get _activeImageSizeItems =>
      _FilmWorkshopImageParamSupport.resolveImageSizeItems(
        _selectedModel,
        _selectedAspectRatio,
      );

  Map<String, String>? get _activeImageSizeLabels =>
      _FilmWorkshopImageParamSupport.resolveImageSizeLabels(
        _selectedModel,
        _selectedAspectRatio,
      );

  bool get _showImageQualitySelect =>
      _FilmWorkshopImageParamSupport.showImageQualitySelect(_selectedModel);

  @override
  void initState() {
    super.initState();
    _service = FilmWorkshopService(ref.read(apiServiceProvider));
    _syncZImageSampleStepsController();
    _loadGenerateParams();
    _loadState();
    _loadSystemPrompt();
  }

  @override
  void dispose() {
    _editController.dispose();
    _titleController.dispose();
    _systemPromptController.dispose();
    _fullScriptController.dispose();
    _centerScrollController.dispose();
    _zImageSampleStepsController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _normalizeWorkshopImageParams({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
    int? sampleSteps,
  }) {
    return _FilmWorkshopImageParamSupport.normalizeParams(
      model: model,
      aspectRatio: aspectRatio,
      imageSize: imageSize,
      imageQuality: imageQuality,
      sampleSteps: sampleSteps,
    );
  }

  Future<void> _loadGenerateParams() async {
    final configService = ConfigFileService();
    final params = await configService.loadGenerateParams();
    if (!mounted) return;

    final normalized = _normalizeWorkshopImageParams(
      model: params['model'] as String,
      aspectRatio: params['aspectRatio'] as String,
      imageSize: params['imageSize'] as String,
      imageQuality: params['imageQuality'] as String? ?? 'auto',
      sampleSteps: (params['sampleSteps'] as num?)?.toInt(),
    );
    setState(() {
      _selectedModel = params['model'] as String;
      _selectedAspectRatio = normalized['aspectRatio'] as String;
      _selectedImageSize = normalized['imageSize'] as String;
      _selectedImageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    });
    _syncZImageSampleStepsController();
    ref
        .read(generateParamsProvider.notifier)
        .setAll(
          _selectedModel,
          _selectedAspectRatio,
          _selectedImageSize,
          _selectedImageQuality,
          _zImageBaseSampleSteps,
        );
    unawaited(
      ref
          .read(apiConfigsProvider.notifier)
          .autoSwitchImageConfigForModel(_selectedModel),
    );
    unawaited(_saveGenerateParams());
  }

  Future<void> _saveGenerateParams() async {
    final configService = ConfigFileService();
    await configService.saveGenerateParams(
      _selectedModel,
      _selectedAspectRatio,
      _selectedImageSize,
      _selectedImageQuality,
      _zImageBaseSampleSteps,
    );
    ref
        .read(generateParamsProvider.notifier)
        .setAll(
          _selectedModel,
          _selectedAspectRatio,
          _selectedImageSize,
          _selectedImageQuality,
          _zImageBaseSampleSteps,
        );
  }

  void _syncZImageSampleStepsController() {
    final text = _zImageBaseSampleSteps.toString();
    if (_zImageSampleStepsController.text != text) {
      _zImageSampleStepsController.text = text;
      _zImageSampleStepsController.selection = TextSelection.collapsed(
        offset: text.length,
      );
    }
  }

  int _commitZImageBaseSampleSteps() {
    final normalized = ZImageBaseGenerationPreset.parseSampleSteps(
      _zImageSampleStepsController.text,
      imageSize: _selectedImageSize,
    );
    if (_zImageBaseSampleSteps != normalized) {
      setState(() {
        _zImageBaseSampleSteps = normalized;
      });
    }
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
    return normalized;
  }

  int? _resolveSampleStepsForCurrentModel() {
    if (!_isZImageBaseSelected) return null;
    return _commitZImageBaseSampleSteps();
  }

  void _applyWorkshopModelSelection(String model) {
    final wasZImageSelected = _isZImageBaseSelected;
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      _selectedImageSize,
    );
    final wasUsingDefaultSteps =
        _zImageBaseSampleSteps == previousDefaultSteps ||
        _zImageBaseSampleSteps < ZImageBaseGenerationPreset.minSampleSteps;
    final normalized = _normalizeWorkshopImageParams(
      model: model,
      aspectRatio: _selectedAspectRatio,
      imageSize: _selectedImageSize,
      imageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );
    setState(() {
      _selectedModel = model;
      _selectedAspectRatio = normalized['aspectRatio'] as String;
      _selectedImageSize = normalized['imageSize'] as String;
      _selectedImageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
      if (_isZImageBaseSelected &&
          (!wasZImageSelected || wasUsingDefaultSteps)) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          _selectedImageSize,
        );
      }
    });
    _syncZImageSampleStepsController();
    unawaited(
      ref
          .read(apiConfigsProvider.notifier)
          .autoSwitchImageConfigForModel(model),
    );
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
  }

  void _applyWorkshopAspectRatioSelection(String aspectRatio) {
    final normalized = _normalizeWorkshopImageParams(
      model: _selectedModel,
      aspectRatio: aspectRatio,
      imageSize: _selectedImageSize,
      imageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );
    setState(() {
      _selectedAspectRatio = normalized['aspectRatio'] as String;
      _selectedImageSize = normalized['imageSize'] as String;
      _selectedImageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    });
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
  }

  void _applyWorkshopImageSizeSelection(String imageSize) {
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      _selectedImageSize,
    );
    final shouldFollowDefault =
        _zImageBaseSampleSteps == previousDefaultSteps ||
        _zImageBaseSampleSteps < ZImageBaseGenerationPreset.minSampleSteps;
    setState(() {
      _selectedImageSize = imageSize;
      if (_isZImageBaseSelected && shouldFollowDefault) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          imageSize,
        );
      }
    });
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
  }

  void _applyWorkshopImageQualitySelection(String imageQuality) {
    setState(() {
      _selectedImageQuality = GptImageGenerationPreset.normalizeQuality(
        imageQuality,
      );
    });
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
  }

  void _applyAssetDialogImageParams({
    required String selectedModel,
    required String selectedAspectRatio,
    required String selectedImageSize,
    required String selectedImageQuality,
    required int sampleSteps,
  }) {
    final normalized = _normalizeWorkshopImageParams(
      model: selectedModel,
      aspectRatio: selectedAspectRatio,
      imageSize: selectedImageSize,
      imageQuality: selectedImageQuality,
      sampleSteps: sampleSteps,
    );
    final nextAspectRatio = normalized['aspectRatio'] as String;
    final nextImageSize = normalized['imageSize'] as String;
    final nextImageQuality = normalized['imageQuality'] as String;
    final nextSampleSteps = normalized['sampleSteps'] as int;
    final hasChanged =
        _selectedModel != selectedModel ||
        _selectedAspectRatio != nextAspectRatio ||
        _selectedImageSize != nextImageSize ||
        _selectedImageQuality != nextImageQuality ||
        _zImageBaseSampleSteps != nextSampleSteps;
    if (!hasChanged) {
      return;
    }

    setState(() {
      _selectedModel = selectedModel;
      _selectedAspectRatio = nextAspectRatio;
      _selectedImageSize = nextImageSize;
      _selectedImageQuality = nextImageQuality;
      _zImageBaseSampleSteps = nextSampleSteps;
    });
    _syncZImageSampleStepsController();
    unawaited(
      ref
          .read(apiConfigsProvider.notifier)
          .autoSwitchImageConfigForModel(selectedModel),
    );
    unawaited(_saveGenerateParams());
    unawaited(_saveState());
  }

  Future<void> _loadSystemPrompt() async {
    final storyboardService = StoryboardService(ref.read(apiServiceProvider));
    final content = await _storageService.loadSystemPrompt(
      storyboardService.getDefaultSystemPrompt(),
    );
    if (mounted) setState(() => _systemPromptController.text = content);
  }

  Future<void> _loadState() async {
    final currentProviderState = ref.read(filmProjectProvider);
    if (currentProviderState.isGenerating) {
      final state = await _storageService.loadWorkshopState();
      if (state != null && mounted) {
        setState(() {
          if (state['selectedStoryboard'] != null) {
            _selectedStoryboard = state['selectedStoryboard'] as String;
          }
          if (state['selectedModel'] != null) {
            _selectedModel = state['selectedModel'] as String;
          }
          if (state['selectedAspectRatio'] != null) {
            _selectedAspectRatio = state['selectedAspectRatio'] as String;
          }
          if (state['selectedImageSize'] != null) {
            _selectedImageSize = state['selectedImageSize'] as String;
          }
          if (state['selectedImageQuality'] != null) {
            _selectedImageQuality = state['selectedImageQuality'] as String;
          }
          if (state['sampleSteps'] != null) {
            _zImageBaseSampleSteps = (state['sampleSteps'] as num).toInt();
          }
          if (state['lastScriptContent'] != null) {
            _lastScriptContent = state['lastScriptContent'] as String;
          }
          if (state['fullScript'] != null) {
            _fullScriptController.text = state['fullScript'] as String;
          }
          final normalized = _normalizeWorkshopImageParams(
            model: _selectedModel,
            aspectRatio: _selectedAspectRatio,
            imageSize: _selectedImageSize,
            imageQuality: _selectedImageQuality,
            sampleSteps: _zImageBaseSampleSteps,
          );
          _selectedAspectRatio = normalized['aspectRatio'] as String;
          _selectedImageSize = normalized['imageSize'] as String;
          _selectedImageQuality = normalized['imageQuality'] as String;
          _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
        });
        _syncZImageSampleStepsController();
        unawaited(_saveGenerateParams());

        // 同步参考图片到当前标签页
        if (state['referenceImages'] != null) {
          final imagesData = state['referenceImages'] as Map<String, dynamic>;
          if (imagesData['images'] != null) {
            final images = List<String>.from(imagesData['images'] as List);
            for (int i = 0; i < images.length && i < 14; i++) {
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabReferenceImage(i, images[i]);
            }
          }
        }
        if (state['imageRemarks'] != null) {
          final remarks = state['imageRemarks'] as Map<String, dynamic>;
          remarks.forEach((key, value) {
            ref
                .read(filmProjectProvider.notifier)
                .updateCurrentTabImageRemark(int.parse(key), value as String);
          });
        }
        if (state['sceneAssets'] != null) {
          final sceneAssets = (state['sceneAssets'] as List)
              .whereType<Map>()
              .map(
                (asset) =>
                    FilmSceneAsset.fromJson(Map<String, dynamic>.from(asset)),
              )
              .toList();
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabSceneAssets(sceneAssets);
        }
      }
      return;
    }

    final state = await _storageService.loadWorkshopState();
    if (state != null && mounted) {
      setState(() {
        if (state['selectedStoryboard'] != null) {
          _selectedStoryboard = state['selectedStoryboard'] as String;
        }
        if (state['selectedModel'] != null) {
          _selectedModel = state['selectedModel'] as String;
        }
        if (state['selectedAspectRatio'] != null) {
          _selectedAspectRatio = state['selectedAspectRatio'] as String;
        }
        if (state['selectedImageSize'] != null) {
          _selectedImageSize = state['selectedImageSize'] as String;
        }
        if (state['selectedImageQuality'] != null) {
          _selectedImageQuality = state['selectedImageQuality'] as String;
        }
        if (state['sampleSteps'] != null) {
          _zImageBaseSampleSteps = (state['sampleSteps'] as num).toInt();
        }
        if (state['lastScriptContent'] != null) {
          _lastScriptContent = state['lastScriptContent'] as String;
        }
        if (state['fullScript'] != null) {
          _fullScriptController.text = state['fullScript'] as String;
        }
        final normalized = _normalizeWorkshopImageParams(
          model: _selectedModel,
          aspectRatio: _selectedAspectRatio,
          imageSize: _selectedImageSize,
          imageQuality: _selectedImageQuality,
          sampleSteps: _zImageBaseSampleSteps,
        );
        _selectedAspectRatio = normalized['aspectRatio'] as String;
        _selectedImageSize = normalized['imageSize'] as String;
        _selectedImageQuality = normalized['imageQuality'] as String;
        _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
      });
      _syncZImageSampleStepsController();
      unawaited(_saveGenerateParams());

      // 同步参考图片到当前标签页
      if (state['referenceImages'] != null) {
        final imagesData = state['referenceImages'] as Map<String, dynamic>;
        if (imagesData['images'] != null) {
          final images = List<String>.from(imagesData['images'] as List);
          for (int i = 0; i < images.length && i < 14; i++) {
            ref
                .read(filmProjectProvider.notifier)
                .updateCurrentTabReferenceImage(i, images[i]);
          }
        }
      }
      if (state['imageRemarks'] != null) {
        final remarks = state['imageRemarks'] as Map<String, dynamic>;
        remarks.forEach((key, value) {
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabImageRemark(int.parse(key), value as String);
        });
      }

      List<Shot> loadedShots = [];
      if (state['shots'] != null) {
        loadedShots = (state['shots'] as List)
            .map((s) => Shot.fromJson(s))
            .toList();
      } else if (_selectedStoryboard != null) {
        _loadStoryboard(_selectedStoryboard);
        return;
      }

      final statusMap = <int, String>{};
      if (state['shotStatus'] != null) {
        (state['shotStatus'] as Map<String, dynamic>).forEach((key, value) {
          statusMap[int.parse(key)] = value as String;
        });
      }

      final imagesMap = <int, String?>{};
      if (state['shotImages'] != null) {
        (state['shotImages'] as Map<String, dynamic>).forEach((key, value) {
          imagesMap[int.parse(key)] = value as String;
        });
      }

      final timerMap = <int, int>{};
      if (state['shotTimer'] != null) {
        (state['shotTimer'] as Map<String, dynamic>).forEach((key, value) {
          timerMap[int.parse(key)] = value as int;
        });
      }

      ref.read(filmProjectProvider.notifier).updateCurrentTabShots(loadedShots);
      for (var entry in statusMap.entries) {
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotStatus(entry.key, entry.value);
      }
      for (var entry in imagesMap.entries) {
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotImage(entry.key, entry.value);
      }
      if (state['sceneAssets'] != null) {
        final sceneAssets = (state['sceneAssets'] as List)
            .whereType<Map>()
            .map(
              (asset) =>
                  FilmSceneAsset.fromJson(Map<String, dynamic>.from(asset)),
            )
            .toList();
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabSceneAssets(sceneAssets);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听匹配任务状态变化，当从最小化恢复时自动弹出对话框
    ref.listen<MatchingTaskState?>(matchingTaskProvider, (prev, next) {
      if (next != null &&
          next.isRunning &&
          !next.isMinimized &&
          prev != null &&
          prev.isMinimized) {
        // 从最小化恢复 → 弹出恢复对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const _MatchingProgressRestoredDialog(),
        );
      }
    });

    return GestureDetector(
      onTap: () {
        if (_isEditingTitle) setState(() => _isEditingTitle = false);
      },
      child: Container(
        color: AppColors.background,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.navbar,
                border: Border(bottom: BorderSide(color: AppColors.border1)),
              ),
              child: Row(
                children: [
                  _isEditingTitle
                      ? SizedBox(
                          width: 150,
                          child: TextField(
                            controller: _titleController,
                            autofocus: true,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (_) =>
                                setState(() => _isEditingTitle = false),
                          ),
                        )
                      : GestureDetector(
                          onDoubleTap: () =>
                              setState(() => _isEditingTitle = true),
                          child: SizedBox(
                            width: 150,
                            child: Text(
                              _titleController.text,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showNewProjectDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: const Text(
                        '新建项目',
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _saveProject,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '保存项目',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _showSplitRulesDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: const Text(
                        '拆解规则',
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Consumer(
                    builder: (context, ref, child) {
                      final projectState = ref.watch(filmProjectProvider);
                      final currentTab = projectState.currentTab;
                      final isSplitting = currentTab?.isSplitting ?? false;
                      return InkWell(
                        onTap: isSplitting ? null : _showSplitScriptDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSplitting
                                ? AppColors.border2
                                : AppColors.inputBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.border2),
                          ),
                          child: Text(
                            isSplitting ? '拆解中...' : '拆解分镜',
                            style: TextStyle(
                              color: isSplitting
                                  ? AppColors.textSecondary
                                  : AppColors.text,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (_lastScriptContent.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _reSplitScript,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.inputBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.border2),
                        ),
                        child: const Text(
                          '重新拆分',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedStoryboard,
                      dropdownColor: AppColors.sidebar,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        isDense: true,
                      ),
                      items: _getStoryboardFiles()
                          .map(
                            (file) => DropdownMenuItem(
                              value: file,
                              child: Text(
                                file,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => _loadStoryboard(value),
                      hint: const Text(
                        '选择分镜脚本',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildSelect(
                    _selectedModel,
                    _FilmWorkshopImageParamSupport.imageModelItems,
                    (v) => _applyWorkshopModelSelection(v!),
                    labels: _FilmWorkshopImageParamSupport.imageModelLabels,
                  ),
                  const SizedBox(width: 4),
                  _buildSelect(
                    _selectedAspectRatio,
                    _activeAspectRatioItems,
                    (v) => _applyWorkshopAspectRatioSelection(v!),
                  ),
                  const SizedBox(width: 4),
                  _buildSelect(
                    _selectedImageSize,
                    _activeImageSizeItems,
                    (v) => _applyWorkshopImageSizeSelection(v!),
                    labels: _activeImageSizeLabels,
                  ),
                  if (_showImageQualitySelect) ...[
                    const SizedBox(width: 4),
                    _buildSelect(
                      _selectedImageQuality,
                      GptImageGenerationPreset.qualityOptions,
                      (v) => _applyWorkshopImageQualitySelection(v!),
                      labels: GptImageGenerationPreset.qualityLabels,
                    ),
                  ],
                  if (_isZImageBaseSelected) ...[
                    const SizedBox(width: 4),
                    _buildZImageSampleStepsInput(),
                  ],
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _showGeneratedImagesDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: const Text(
                        '分镜头图片',
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _showFullScriptDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border2),
                      ),
                      child: const Text(
                        '完整剧本',
                        style: TextStyle(color: AppColors.text, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _buildLeftPanel(),
                  Expanded(child: _buildCenterPanel()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    final projectState = ref.watch(filmProjectProvider);
    final currentTab = projectState.currentTab;
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border1)),
            ),
            child: const Text(
              '参考图片 (最多14张)',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 14,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildImageSlot(index),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border1)),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (currentTab?.shots.isEmpty ?? true)
                        ? null
                        : _matchAssetsToShots,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF424242),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '匹配资产到分镜头',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: _matchOnlyUnmatched,
                      onChanged: (v) =>
                          setState(() => _matchOnlyUnmatched = v ?? true),
                      activeColor: AppColors.primary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const Expanded(
                      child: Text(
                        '只匹配未匹配的镜头',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _clearAllImages,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      '清空所有参考图',
                      style: TextStyle(color: AppColors.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditShotDialog(int index) {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    final isNewShot = index == -1;
    final shot = isNewShot ? null : currentTab?.shots[index];
    final promptController = TextEditingController(text: shot?.prompt ?? '');
    String? selectedAiConfig;

    final apiConfigs = ref.read(apiConfigsProvider);
    final chatConfigs = apiConfigs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isNotEmpty) {
      final defaultConfig = chatConfigs.firstWhere(
        (c) => c.isDefault,
        orElse: () => chatConfigs.first,
      );
      selectedAiConfig = defaultConfig.id;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: Row(
            children: [
              Text(
                isNewShot ? '添加镜头' : '编辑镜头 ${shot!.shotNumber}',
                style: const TextStyle(color: AppColors.text),
              ),
              const Spacer(),
              if (chatConfigs.isNotEmpty)
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3a3a3a),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: selectedAiConfig,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.sidebar,
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                    items: chatConfigs
                        .map(
                          (config) => DropdownMenuItem(
                            value: config.id,
                            child: Text(config.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedAiConfig = value),
                  ),
                ),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '画面描述',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: promptController,
                    maxLines: null,
                    expands: true,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.text),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '输入画面描述',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (chatConfigs.isEmpty || promptController.text.trim().isEmpty)
                  return;

                final configService = ConfigFileService();
                final systemPrompt = await configService.loadSystemPrompt();
                final selectedConfig = chatConfigs.firstWhere(
                  (c) => c.id == selectedAiConfig,
                  orElse: () => chatConfigs.first,
                );

                try {
                  final apiService = ref.read(apiServiceProvider);
                  final results = await apiService.polishPrompt(
                    apiUrl: selectedConfig.url,
                    apiKey: selectedConfig.key,
                    model: selectedConfig.model,
                    prompt: promptController.text,
                    systemPrompt: systemPrompt,
                  );

                  if (results.isNotEmpty && mounted) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.sidebar,
                        title: const Text(
                          '选择润色结果',
                          style: TextStyle(color: AppColors.text),
                        ),
                        content: SizedBox(
                          width: 500,
                          height: 300,
                          child: ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (ctx, idx) => ListTile(
                              title: Text(
                                results[idx],
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  promptController.text = results[idx];
                                  Navigator.pop(ctx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF424242),
                                ),
                                child: const Text(
                                  '使用',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('润色失败: $e')));
                  }
                }
              },
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF3a3a3a),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              child: const Text('AI润色', style: TextStyle(color: Colors.white)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                if (promptController.text.trim().isEmpty) return;

                if (isNewShot) {
                  final newShotNumber = ((currentTab?.shots.length ?? 0) + 1)
                      .toString();
                  final newShot = Shot(
                    shotNumber: newShotNumber,
                    shotName: '镜头$newShotNumber',
                    shotType: '中景',
                    prompt: promptController.text,
                    movement: '固定镜头',
                  );
                  final newShots = List<Shot>.from(currentTab?.shots ?? [])
                    ..add(newShot);
                  ref
                      .read(filmProjectProvider.notifier)
                      .updateCurrentTabShots(newShots);
                  ref
                      .read(filmProjectProvider.notifier)
                      .updateCurrentTabShotStatus(newShots.length - 1, '待生成');
                } else {
                  final updatedShot = shot!.copyWith(
                    prompt: promptController.text,
                  );
                  final newShots = List<Shot>.from(currentTab!.shots);
                  newShots[index] = updatedShot;
                  ref
                      .read(filmProjectProvider.notifier)
                      .updateCurrentTabShots(newShots);
                }
                _saveState();
                Navigator.pop(context);
              },
              child: Text(
                isNewShot ? '添加' : '保存',
                style: const TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(
    File file, {
    List<File>? allImages,
    int initialIndex = 0,
  }) {
    if (allImages == null || allImages.isEmpty) {
      allImages = [file];
      initialIndex = 0;
    }

    showDialog(
      context: context,
      builder: (context) => _FullScreenImagePreview(
        images: allImages!,
        initialIndex: initialIndex,
      ),
    );
  }

  void _showAssetSelectionDialog(int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => _AssetSelectionWithViewsDialog(
        slotIndex: index,
        onSelect: (String imagePath, String remark, {String? assetId}) {
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabReferenceImage(index, imagePath);
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabImageRemark(index, remark);
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabSlotAssetId(index, assetId);
          _saveState();
        },
      ),
    );
  }

  Widget _buildImageSlot(int index) {
    final projectState = ref.watch(filmProjectProvider);
    final currentTab = projectState.currentTab;
    final imagePath = currentTab?.referenceImages[index] ?? '';
    final isEmpty = imagePath.isEmpty;
    final remark = currentTab?.imageRemarks[index] ?? '';
    final remarkController = TextEditingController(text: remark);
    final slotAssetId = currentTab?.slotAssetIds[index];
    final hasAsset = slotAssetId != null && slotAssetId.isNotEmpty;
    // 获取关联资产的图片数量
    int assetImageCount = 0;
    if (hasAsset) {
      final assets = ref.read(assetProvider);
      final asset = assets.where((a) => a.id == slotAssetId).firstOrNull;
      if (asset != null) assetImageCount = asset.allImages.length;
    }

    return DropTarget(
      onDragDone: (details) => _handleSlotDrop(index, details),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.border2),
            ),
            child: isEmpty
                ? GestureDetector(
                    onTap: () => _addImageToSlot(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Icon(
                          Icons.add_photo_alternate,
                          color: AppColors.textSecondary,
                          size: 32,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '插槽${index + 1}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : LongPressDraggable<Map<String, String>>(
                    data: {'imagePath': imagePath, 'remark': remark},
                    delay: const Duration(milliseconds: 300),
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(
                        opacity: 0.7,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                            ),
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              cacheWidth: 200,
                              File(imagePath),
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            cacheWidth: 200,
                            File(imagePath),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.inputBg,
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: AppColors.textSecondary,
                                    size: 32,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (hasAsset && assetImageCount > 1)
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.collections,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$assetImageCount张',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeImageFromSlot(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: remarkController,
                  style: const TextStyle(color: AppColors.text, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '名称',
                    hintStyle: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: AppColors.inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    setState(() {
                      if (value.isEmpty) {
                        _imageRemarks.remove(index);
                      } else {
                        _imageRemarks[index] = value;
                      }
                    });
                    ref
                        .read(filmProjectProvider.notifier)
                        .updateCurrentTabImageRemark(index, value);
                    _saveState();
                  },
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _showAssetSelectionDialog(index),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: const Icon(
                    Icons.arrow_drop_down_circle,
                    color: Color(0xFF424242),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _clearAllShots() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认清空', style: TextStyle(color: AppColors.text)),
        content: const Text(
          '确定要清空所有分镜内容吗？此操作无法撤销。',
          style: TextStyle(color: AppColors.text),
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
              final projectState = ref.read(filmProjectProvider);
              final currentTab = projectState.currentTab;
              final newShots = List<Shot>.from(currentTab?.shots ?? []);
              newShots.clear();
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabShots(newShots);
              setState(() {
                _selectedStoryboard = null;
              });
              _saveState();
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('所有分镜已清空')));
              }
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel() {
    final projectState = ref.watch(filmProjectProvider);
    final currentTab = projectState.currentTab;
    final shots = currentTab?.shots ?? [];
    final isSplitting = currentTab?.isSplitting ?? false;
    final thoughtProcess = currentTab?.thoughtProcess ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: isSplitting
                ? _splitMinimized
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.hourglass_top,
                                color: AppColors.primary,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '拆解分镜正在后台进行...',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _splitMinimized = false),
                                icon: const Icon(Icons.open_in_full, size: 14),
                                label: const Text(
                                  '展开详情',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 16),
                                  const Text(
                                    '拆解中，请等待...',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  IconButton(
                                    onPressed: () =>
                                        setState(() => _splitMinimized = true),
                                    icon: const Icon(
                                      Icons.minimize,
                                      color: AppColors.textSecondary,
                                      size: 20,
                                    ),
                                    tooltip: '最小化到后台',
                                    style: IconButton.styleFrom(
                                      backgroundColor: const Color(0xFF3a3a3a),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (thoughtProcess.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Container(
                                  width: 600,
                                  constraints: const BoxConstraints(
                                    maxHeight: 400,
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.border1.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        '思考过程:',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Flexible(
                                        child: SingleChildScrollView(
                                          reverse: true,
                                          child: Text(
                                            thoughtProcess,
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                              height: 1.5,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                : shots.isEmpty
                ? const Center(
                    child: Text(
                      '请选择分镜脚本',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          _centerScrollController.hasClients) {
                        final offset =
                            (_centerScrollController.offset +
                                    event.scrollDelta.dy * 3)
                                .clamp(
                                  0.0,
                                  _centerScrollController
                                      .position
                                      .maxScrollExtent,
                                );
                        _centerScrollController.jumpTo(offset);
                      }
                    },
                    child: ReorderableListView.builder(
                      scrollController: _centerScrollController,
                      itemCount: shots.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        final newShots = List<Shot>.from(shots);
                        final shot = newShots.removeAt(oldIndex);
                        newShots.insert(newIndex, shot);
                        for (int i = 0; i < newShots.length; i++) {
                          newShots[i] = newShots[i].copyWith(
                            shotNumber: (i + 1).toString().padLeft(2, '0'),
                          );
                        }
                        ref
                            .read(filmProjectProvider.notifier)
                            .updateCurrentTabShots(newShots);
                      },
                      itemBuilder: (context, index) {
                        final shot = shots[index];
                        final status = currentTab?.shotStatus[index] ?? '待生成';
                        final imagePath = currentTab?.shotImages[index];
                        final timerValue = currentTab?.shotTimer[index];
                        final isEditing = _editingIndex == index;

                        return Container(
                          key: ValueKey(
                            '${shot.shotNumber}_${shot.shotName}_$index',
                          ),
                          child: DragTarget<Map<String, String>>(
                            onWillAccept: (data) =>
                                data != null && data['imagePath'] != null,
                            onAccept: (data) =>
                                _handleShotInternalDrop(index, data),
                            builder: (context, candidateData, rejectedData) {
                              final isHovering = candidateData.isNotEmpty;
                              return DropTarget(
                                onDragDone: (details) =>
                                    _handleShotDrop(index, details),
                                onDragEntered: (details) => setState(() {}),
                                onDragExited: (details) => setState(() {}),
                                child: GestureDetector(
                                  onDoubleTap: () => _showEditShotDialog(index),
                                  child: _GlowContainer(
                                    isActive: isHovering,
                                    isEditing: isEditing,
                                    child: Row(
                                      children: [
                                        Checkbox(
                                          value: _selectedShotIndices.contains(
                                            index,
                                          ),
                                          onChanged: (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedShotIndices.add(index);
                                              } else {
                                                _selectedShotIndices.remove(
                                                  index,
                                                );
                                              }
                                            });
                                          },
                                          activeColor: AppColors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            _getCircledNumber(index + 1),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        if (imagePath != null)
                                          GestureDetector(
                                            onTap: () => _showImagePreview(
                                              File(imagePath),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: Image.file(
                                                cacheWidth: 200,
                                                File(imagePath),
                                                width: 80,
                                                height: 80,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      return Container(
                                                        width: 80,
                                                        height: 80,
                                                        color:
                                                            AppColors.inputBg,
                                                        child: const Icon(
                                                          Icons.broken_image,
                                                          color: AppColors
                                                              .textSecondary,
                                                          size: 32,
                                                        ),
                                                      );
                                                    },
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            width: 80,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              color: AppColors.inputBg,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    status,
                                                    style: TextStyle(
                                                      color: status == '失败'
                                                          ? Colors.red
                                                          : AppColors
                                                                .textSecondary,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  if (status == '生成中' &&
                                                      timerValue != null)
                                                    Text(
                                                      '${timerValue}s',
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .textSecondary,
                                                        fontSize: 9,
                                                      ),
                                                    ),
                                                  if (status == '失败')
                                                    GestureDetector(
                                                      onTap: () =>
                                                          _retrySingleShot(
                                                            index,
                                                          ),
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              AppColors.primary,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                        child: const Text(
                                                          '重试',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 9,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: isEditing
                                              ? TextField(
                                                  controller: _editController,
                                                  maxLines: 3,
                                                  style: const TextStyle(
                                                    color: AppColors.text,
                                                    fontSize: 12,
                                                  ),
                                                  decoration:
                                                      const InputDecoration(
                                                        border:
                                                            OutlineInputBorder(),
                                                        isDense: true,
                                                      ),
                                                )
                                              : Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        if (shot
                                                                .manualReferenceImages
                                                                .isNotEmpty ||
                                                            shot
                                                                .referenceImagePaths
                                                                .isNotEmpty) ...[
                                                          Text(
                                                            shot
                                                                    .manualReferenceImages
                                                                    .isNotEmpty
                                                                ? '参考图: '
                                                                : 'AI匹配: ',
                                                            style: TextStyle(
                                                              color:
                                                                  shot
                                                                      .manualReferenceImages
                                                                      .isNotEmpty
                                                                  ? AppColors
                                                                        .text
                                                                  : AppColors
                                                                        .primary,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                          ...List.generate(
                                                            (shot
                                                                        .manualReferenceImages
                                                                        .isNotEmpty
                                                                    ? shot.manualReferenceImages
                                                                    : shot.referenceImagePaths)
                                                                .length,
                                                            (i) {
                                                              final images =
                                                                  shot
                                                                      .manualReferenceImages
                                                                      .isNotEmpty
                                                                  ? shot.manualReferenceImages
                                                                  : shot.referenceImagePaths;
                                                              return Padding(
                                                                padding:
                                                                    const EdgeInsets.only(
                                                                      right: 4,
                                                                    ),
                                                                child: Stack(
                                                                  children: [
                                                                    GestureDetector(
                                                                      onTap: () =>
                                                                          _showAssetDropdownForShot(
                                                                            index,
                                                                            i,
                                                                          ),
                                                                      child: Container(
                                                                        width:
                                                                            40,
                                                                        height:
                                                                            40,
                                                                        decoration: BoxDecoration(
                                                                          border: Border.all(
                                                                            color:
                                                                                AppColors.border2,
                                                                          ),
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                4,
                                                                              ),
                                                                        ),
                                                                        child: ClipRRect(
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                4,
                                                                              ),
                                                                          child: Image.file(
                                                                            cacheWidth:
                                                                                200,
                                                                            File(
                                                                              images[i],
                                                                            ),
                                                                            fit:
                                                                                BoxFit.cover,
                                                                            errorBuilder:
                                                                                (
                                                                                  _,
                                                                                  __,
                                                                                  ___,
                                                                                ) => const Icon(
                                                                                  Icons.image,
                                                                                  size: 20,
                                                                                  color: AppColors.textSecondary,
                                                                                ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    Positioned(
                                                                      top: -4,
                                                                      right: -4,
                                                                      child: GestureDetector(
                                                                        onTap: () =>
                                                                            _removeAssetFromShot(
                                                                              index,
                                                                              i,
                                                                            ),
                                                                        child: Container(
                                                                          padding:
                                                                              const EdgeInsets.all(
                                                                                2,
                                                                              ),
                                                                          decoration: const BoxDecoration(
                                                                            color:
                                                                                Colors.red,
                                                                            shape:
                                                                                BoxShape.circle,
                                                                          ),
                                                                          child: const Icon(
                                                                            Icons.close,
                                                                            color:
                                                                                Colors.white,
                                                                            size:
                                                                                12,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons
                                                                .add_circle_outline,
                                                            size: 20,
                                                            color: AppColors
                                                                .primary,
                                                          ),
                                                          onPressed: () =>
                                                              _showAssetDropdownForShot(
                                                                index,
                                                                -1,
                                                              ),
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    if (shot
                                                            .referenceImagePaths
                                                            .isNotEmpty &&
                                                        shot
                                                            .manualReferenceImages
                                                            .isEmpty) ...[
                                                      Consumer(
                                                        builder: (context, ref, child) {
                                                          final projectState =
                                                              ref.watch(
                                                                filmProjectProvider,
                                                              );
                                                          final currentTab =
                                                              projectState
                                                                  .currentTab;
                                                          return Text(
                                                            '${shot.referenceImagePaths.map((p) {
                                                              // 1. Try to get from persisted asset remarks in the shot
                                                              if (shot.assetRemarks != null && shot.assetRemarks!.containsKey(p)) {
                                                                return shot.assetRemarks![p]!;
                                                              }

                                                              // 2. Fallback to dynamic lookup from left panel (for backward compatibility or if updated)
                                                              int originalIndex = -1;
                                                              for (int i = 0; i < 14; i++) {
                                                                if ((currentTab?.referenceImages[i] ?? '') == p) {
                                                                  originalIndex = i;
                                                                  break;
                                                                }
                                                              }
                                                              if (originalIndex != -1 && (currentTab?.imageRemarks.containsKey(originalIndex) ?? false)) {
                                                                return currentTab!.imageRemarks[originalIndex]!;
                                                              }

                                                              // 3. Fallback to filename
                                                              return path.basename(p);
                                                            }).join(", ")}',
                                                            style: const TextStyle(
                                                              color: AppColors
                                                                  .textSecondary,
                                                              fontSize: 10,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      const SizedBox(height: 4),
                                                    ],
                                                    Text(
                                                      '${shot.shotNumber}. ${shot.shotName}',
                                                      style: const TextStyle(
                                                        color: AppColors.text,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    if (shot
                                                        .shotType
                                                        .isNotEmpty)
                                                      Text(
                                                        '景别: ${shot.shotType}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    if (shot
                                                        .cameraAngle
                                                        .isNotEmpty)
                                                      Text(
                                                        '视角: ${shot.cameraAngle}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    if (shot
                                                        .lighting
                                                        .isNotEmpty)
                                                      Text(
                                                        '光影: ${shot.lighting}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    if (shot.characterName !=
                                                            '无' &&
                                                        shot
                                                            .characterName
                                                            .isNotEmpty)
                                                      Text(
                                                        '角色: ${shot.characterName}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    if (shot.action != '无' &&
                                                        shot.action.isNotEmpty)
                                                      Text(
                                                        '动作: ${shot.action}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    if (shot.movement !=
                                                            '固定镜头' &&
                                                        shot
                                                            .movement
                                                            .isNotEmpty)
                                                      Text(
                                                        '运镜: ${shot.movement}',
                                                        style: const TextStyle(
                                                          color: AppColors
                                                              .textSecondary,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      shot.prompt,
                                                      style: const TextStyle(
                                                        color: AppColors
                                                            .textSecondary,
                                                        fontSize: 11,
                                                      ),
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                        ),
                                        if (isEditing)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.save,
                                              color: AppColors.primary,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              final updatedShot = Shot(
                                                shotNumber: shot.shotNumber,
                                                shotName: shot.shotName,
                                                shotType: shot.shotType,
                                                prompt: _editController.text,
                                                movement: shot.movement,
                                              );
                                              final newShots = List<Shot>.from(
                                                shots,
                                              );
                                              newShots[index] = updatedShot;
                                              ref
                                                  .read(
                                                    filmProjectProvider
                                                        .notifier,
                                                  )
                                                  .updateCurrentTabShots(
                                                    newShots,
                                                  );
                                              setState(() {
                                                _editingIndex = null;
                                              });
                                            },
                                          )
                                        else
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.refresh,
                                                  color: AppColors.text,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _generateSingleShot(index),
                                                tooltip: '重新生成',
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  color:
                                                      AppColors.textSecondary,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    _deleteShot(index),
                                                tooltip: '删除镜头',
                                              ),
                                              const SizedBox(width: 8),
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: const Icon(
                                                  Icons.drag_handle,
                                                  color:
                                                      AppColors.textSecondary,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          if (projectState.isGenerating) ...[
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '进度 ${projectState.successCount + projectState.failedCount}/${_selectedShotIndices.isEmpty ? shots.length : _selectedShotIndices.length}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Row(
                      children: [
                        if (projectState.successCount > 0)
                          Text(
                            '成功 ${projectState.successCount}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                            ),
                          ),
                        if (projectState.successCount > 0 &&
                            projectState.failedCount > 0)
                          const Text('  ', style: TextStyle(fontSize: 11)),
                        if (projectState.failedCount > 0)
                          Text(
                            '失败 ${projectState.failedCount}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: shots.isEmpty
                        ? 0
                        : (projectState.successCount +
                                  projectState.failedCount) /
                              (_selectedShotIndices.isEmpty
                                  ? shots.length
                                  : _selectedShotIndices.length),
                    backgroundColor: AppColors.inputBg,
                    color: projectState.failedCount > 0
                        ? Colors.orange
                        : AppColors.primary,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                flex: 1,
                child: OutlinedButton(
                  onPressed: shots.isEmpty
                      ? null
                      : (_selectedShotIndices.isEmpty
                            ? _clearAllShots
                            : _deleteSelectedShots),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border2),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _selectedShotIndices.isEmpty ? '清空分镜' : '删除所选',
                    style: const TextStyle(fontSize: 16, color: AppColors.text),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: ElevatedButton(
                  onPressed: projectState.isGenerating ? null : _generateImages,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.sidebar,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    projectState.isGenerating
                        ? '生成中 ${projectState.successCount + projectState.failedCount}/${_selectedShotIndices.isEmpty ? shots.length : _selectedShotIndices.length}'
                        : (_selectedShotIndices.isEmpty ? '生成分镜图' : '生成所选分镜'),
                    style: const TextStyle(fontSize: 16, color: AppColors.text),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 50,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => _showEditShotDialog(-1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3a3a3a),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    final projectState = ref.watch(filmProjectProvider);
    final currentTab = projectState.currentTab;
    final generatedImages =
        currentTab?.shotImages.values.where((p) => p != null).toList() ?? [];

    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border1)),
            ),
            child: const Text(
              '预览区',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: generatedImages.isEmpty
                ? const Center(
                    child: Text(
                      '暂无生成图片',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: generatedImages.length,
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(generatedImages[index]!),
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addImageToSlot(int index) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final imagePath = result.files.single.path!;
      ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabReferenceImage(index, imagePath);
      ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabImageRemark(
            index,
            path.basenameWithoutExtension(imagePath),
          );
      ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabSlotAssetId(index, null);
      _saveState();
    }
  }

  void _handleSlotDrop(int index, DropDoneDetails details) {
    if (details.files.isNotEmpty) {
      final file = details.files.first;
      final filePath = file.path;
      if (filePath.toLowerCase().endsWith('.png') ||
          filePath.toLowerCase().endsWith('.jpg') ||
          filePath.toLowerCase().endsWith('.jpeg') ||
          filePath.toLowerCase().endsWith('.webp')) {
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabReferenceImage(index, filePath);
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabImageRemark(
              index,
              path.basenameWithoutExtension(filePath),
            );
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabSlotAssetId(index, null);
        _saveState();
      }
    }
  }

  void _removeImageFromSlot(int index) {
    ref
        .read(filmProjectProvider.notifier)
        .updateCurrentTabReferenceImage(index, '');
    ref
        .read(filmProjectProvider.notifier)
        .updateCurrentTabImageRemark(index, '');
    ref
        .read(filmProjectProvider.notifier)
        .updateCurrentTabSlotAssetId(index, null);
    _saveState();
  }

  void _clearAllImages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认清空', style: TextStyle(color: AppColors.text)),
        content: const Text(
          '确定要清空所有参考图吗？',
          style: TextStyle(color: AppColors.text),
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
              for (int i = 0; i < 14; i++) {
                ref
                    .read(filmProjectProvider.notifier)
                    .updateCurrentTabReferenceImage(i, '');
                ref
                    .read(filmProjectProvider.notifier)
                    .updateCurrentTabImageRemark(i, '');
              }
              _saveState();
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _deleteShot(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text(
          '确定要删除镜头${index + 1}吗？',
          style: const TextStyle(color: AppColors.text),
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
              final projectState = ref.read(filmProjectProvider);
              final currentTab = projectState.currentTab;
              final newShots = List<Shot>.from(currentTab?.shots ?? []);
              newShots.removeAt(index);
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabShots(newShots);
              setState(() => _selectedShotIndices.remove(index));
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedShots() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text(
          '确定要删除选中的${_selectedShotIndices.length}个镜头吗？',
          style: const TextStyle(color: AppColors.text),
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
              final projectState = ref.read(filmProjectProvider);
              final currentTab = projectState.currentTab;
              final newShots = List<Shot>.from(currentTab?.shots ?? []);
              final sortedIndices = _selectedShotIndices.toList()
                ..sort((a, b) => b.compareTo(a));
              for (final index in sortedIndices) {
                newShots.removeAt(index);
              }
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabShots(newShots);
              setState(() => _selectedShotIndices.clear());
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _handleShotInternalDrop(int shotIndex, Map<String, String> data) {
    final imagePath = data['imagePath'];
    final remark = data['remark'];

    if (imagePath == null || imagePath.isEmpty) return;

    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || shotIndex >= currentTab.shots.length) return;

    final shot = currentTab.shots[shotIndex];

    if (shot.manualReferenceImages.contains(imagePath)) return;

    final newManualImages = List<String>.from(shot.manualReferenceImages);
    newManualImages.add(imagePath);

    final newAssetRemarks = Map<String, String>.from(shot.assetRemarks ?? {});
    if (remark != null && remark.isNotEmpty) {
      newAssetRemarks[imagePath] = remark;
    } else {
      newAssetRemarks[imagePath] = path.basenameWithoutExtension(imagePath);
    }

    final updatedShot = shot.copyWith(
      manualReferenceImages: newManualImages,
      assetRemarks: newAssetRemarks,
    );

    final newShots = List<Shot>.from(currentTab.shots);
    newShots[shotIndex] = updatedShot;

    ref.read(filmProjectProvider.notifier).updateCurrentTabShots(newShots);
    _saveState();
  }

  void _handleShotDrop(int shotIndex, DropDoneDetails details) {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || shotIndex >= currentTab.shots.length) return;

    String? imagePath;
    String? remark;

    for (int i = 0; i < 14; i++) {
      final refImage = currentTab.referenceImages[i] ?? '';
      if (refImage.isNotEmpty) {
        imagePath = refImage;
        remark = currentTab.imageRemarks[i] ?? '';
        break;
      }
    }

    if (imagePath == null || imagePath.isEmpty) return;

    final shot = currentTab.shots[shotIndex];
    final manualImages = List<String>.from(shot.manualReferenceImages);

    if (remark == null || remark.isEmpty) {
      remark = path.basenameWithoutExtension(imagePath);
    }

    manualImages.add(imagePath);

    final assetRemarks = Map<String, String>.from(shot.assetRemarks ?? {});
    assetRemarks[imagePath] = remark;

    String updatedPrompt = shot.prompt;
    final mappingRegex = RegExp(r'.*?是第\d+张提供的图片\[Image\d+\].*?[,，。]?\s*');
    while (mappingRegex.hasMatch(updatedPrompt)) {
      updatedPrompt = updatedPrompt.replaceFirst(mappingRegex, '');
    }
    updatedPrompt = updatedPrompt
        .replaceAll(',,', ',')
        .replaceAll('。。', '。')
        .trim();
    if (updatedPrompt.startsWith(','))
      updatedPrompt = updatedPrompt.substring(1);
    if (updatedPrompt.startsWith('。'))
      updatedPrompt = updatedPrompt.substring(1);

    final newReferences = <String>[];
    for (int i = 0; i < manualImages.length; i++) {
      final imgPath = manualImages[i];
      final imgRemark = assetRemarks[imgPath] ?? '';
      newReferences.add('${imgRemark}是第${i + 1}张提供的图片[Image${i + 1}]');
    }

    if (newReferences.isNotEmpty) {
      updatedPrompt = '${newReferences.join(", ")}。$updatedPrompt';
    }

    final updatedShot = shot.copyWith(
      manualReferenceImages: manualImages,
      assetRemarks: assetRemarks,
      prompt: updatedPrompt,
    );

    final newShots = List<Shot>.from(currentTab.shots);
    newShots[shotIndex] = updatedShot;
    ref.read(filmProjectProvider.notifier).updateCurrentTabShots(newShots);
    _saveState();
  }

  void _removeAssetFromShot(int shotIndex, int slotIndex) {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || shotIndex >= currentTab.shots.length) return;
    final shot = currentTab.shots[shotIndex];
    final manualImages = List<String>.from(
      shot.manualReferenceImages.isNotEmpty
          ? shot.manualReferenceImages
          : shot.referenceImagePaths,
    );

    if (slotIndex < manualImages.length) {
      manualImages.removeAt(slotIndex);
      final assetRemarks = Map<String, String>.from(shot.assetRemarks ?? {});

      String updatedPrompt = shot.prompt;
      final mappingRegex = RegExp(r'.*?是第\d+张提供的图片\[Image\d+\].*?[,，。]?\s*');
      while (mappingRegex.hasMatch(updatedPrompt)) {
        updatedPrompt = updatedPrompt.replaceFirst(mappingRegex, '');
      }
      updatedPrompt = updatedPrompt
          .replaceAll(',,', ',')
          .replaceAll('。。', '。')
          .trim();
      if (updatedPrompt.startsWith(','))
        updatedPrompt = updatedPrompt.substring(1);
      if (updatedPrompt.startsWith('。'))
        updatedPrompt = updatedPrompt.substring(1);

      if (manualImages.isNotEmpty) {
        final newReferences = <String>[];
        for (int i = 0; i < manualImages.length; i++) {
          final imgPath = manualImages[i];
          String remark = assetRemarks[imgPath] ?? '';
          if (remark.isEmpty) {
            final tabImages =
                ref.read(filmProjectProvider).currentTab?.referenceImages ?? [];
            final tabRemarks =
                ref.read(filmProjectProvider).currentTab?.imageRemarks ?? {};
            int refIndex = tabImages.indexOf(imgPath);
            if (refIndex != -1) remark = tabRemarks[refIndex] ?? '';
          }
          if (remark.isEmpty ||
              remark.startsWith('参考图') ||
              RegExp(r'^参考图\d+$').hasMatch(remark)) {
            remark = '参考图';
          }
          newReferences.add('$remark是第${i + 1}张提供的图片[Image${i + 1}]');
        }
        updatedPrompt = '${newReferences.join('，')}。$updatedPrompt';
      }

      final updatedShot = shot.copyWith(
        manualReferenceImages: manualImages,
        referenceImagePaths: manualImages,
        assetRemarks: assetRemarks,
        prompt: updatedPrompt,
      );
      final newShots = List<Shot>.from(currentTab!.shots);
      newShots[shotIndex] = updatedShot;
      ref.read(filmProjectProvider.notifier).updateCurrentTabShots(newShots);
      _saveState();
    }
  }

  void _showAssetDropdownForShot(int shotIndex, int slotIndex) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('选择参考图', style: TextStyle(color: AppColors.text)),
        content: SizedBox(
          width: 600,
          height: 400,
          child: Consumer(
            builder: (context, ref, child) {
              final assets = ref.watch(assetProvider);
              final projectState = ref.watch(filmProjectProvider);
              final currentTab = projectState.currentTab;
              final availableImages = <String, String>{};

              for (int i = 0; i < 14; i++) {
                final imagePath = currentTab?.referenceImages[i] ?? '';
                if (imagePath.isNotEmpty) {
                  availableImages[imagePath] =
                      currentTab?.imageRemarks[i] ?? '参考图${i + 1}';
                }
              }

              for (final asset in assets) {
                availableImages[asset.imagePath] = asset.description.isNotEmpty
                    ? '${asset.name} (${asset.description})'
                    : asset.name;
              }

              if (availableImages.isEmpty) {
                return const Center(
                  child: Text(
                    '暂无可用参考图',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.8,
                ),
                itemCount: availableImages.length,
                itemBuilder: (context, idx) {
                  final imagePath = availableImages.keys.elementAt(idx);
                  final imageName = availableImages[imagePath]!;

                  return InkWell(
                    onTap: () {
                      final projectState = ref.read(filmProjectProvider);
                      final currentTab = projectState.currentTab;
                      if (currentTab == null ||
                          shotIndex >= currentTab.shots.length)
                        return;
                      final shot = currentTab.shots[shotIndex];

                      // Handle manual reference images list
                      final manualImages = shot.manualReferenceImages.isNotEmpty
                          ? List<String>.from(shot.manualReferenceImages)
                          : List<String>.from(shot.referenceImagePaths);

                      if (slotIndex == -1) {
                        manualImages.add(imagePath);
                      } else {
                        if (slotIndex < manualImages.length) {
                          manualImages[slotIndex] = imagePath;
                        } else {
                          while (manualImages.length < slotIndex) {
                            manualImages.add('');
                          }
                          manualImages.add(imagePath);
                        }
                      }

                      // Update asset remarks map
                      final assetRemarks = Map<String, String>.from(
                        shot.assetRemarks ?? {},
                      );
                      assetRemarks[imagePath] = imageName;

                      // Also update referenceImagePaths if it's an AI matched slot (though manual usually overrides)
                      // If we are replacing an existing image in referenceImagePaths (for AI matched shots),
                      // we need to find which index it corresponds to.
                      // However, the current UI logic separates manual vs AI matched display.
                      // If user clicks on an AI matched image (which are in referenceImagePaths),
                      // we should probably update that specific entry in referenceImagePaths too to keep UI consistent.

                      List<String> referenceImagePaths = List<String>.from(
                        shot.referenceImagePaths,
                      );
                      if (shot.manualReferenceImages.isEmpty &&
                          slotIndex != -1 &&
                          slotIndex < referenceImagePaths.length) {
                        referenceImagePaths[slotIndex] = imagePath;
                      }

                      // Bug fix: Clean up the prompt to remove duplicate image references
                      String updatedPrompt = shot.prompt;

                      // 1. Remove ALL existing image references to avoid duplication and conflicts
                      // Pattern: "xx是第x张提供的图片[Imagex]" or ".*?是第\d+张提供的图片\[Image\d+\].*?[,，。]?\s*"
                      // We need to be careful not to remove other content, but the references are usually at the beginning or end
                      // Let's use the same regex as in controller to clean up all old references first
                      final mappingRegex = RegExp(
                        r'.*?是第\d+张提供的图片\[Image\d+\].*?[,，。]?\s*',
                      );
                      while (mappingRegex.hasMatch(updatedPrompt)) {
                        updatedPrompt = updatedPrompt.replaceFirst(
                          mappingRegex,
                          '',
                        );
                      }

                      // Clean up any double punctuation left behind
                      updatedPrompt = updatedPrompt
                          .replaceAll(',,', ',')
                          .replaceAll('。。', '。');
                      if (updatedPrompt.startsWith(','))
                        updatedPrompt = updatedPrompt.substring(1);
                      if (updatedPrompt.startsWith('。'))
                        updatedPrompt = updatedPrompt.substring(1);
                      updatedPrompt = updatedPrompt.trim();

                      // 2. Re-generate references for ALL current images (both manual and AI matched)
                      // This ensures the prompt reflects the current state of all slots, not just the one changed

                      final allImages = shot.manualReferenceImages.isNotEmpty
                          ? manualImages
                          : referenceImagePaths;
                      final newReferences = <String>[];

                      // We need remarks for all images.
                      // For manualImages, we can try to look up in currentTab.referenceImages or use assetRemarks or just filename/default
                      // For referenceImagePaths (AI matched), we should have assetRemarks or original remarks

                      final tabImages =
                          ref
                              .read(filmProjectProvider)
                              .currentTab
                              ?.referenceImages ??
                          [];
                      final tabRemarks =
                          ref
                              .read(filmProjectProvider)
                              .currentTab
                              ?.imageRemarks ??
                          {};

                      for (int i = 0; i < allImages.length; i++) {
                        final imgPath = allImages[i];
                        String remark = assetRemarks[imgPath] ?? '';

                        // Fallback lookup if not in assetRemarks
                        if (remark.isEmpty) {
                          // Try looking up in currentTab.referenceImages
                          int refIndex = tabImages.indexOf(imgPath);
                          if (refIndex != -1) {
                            remark = tabRemarks[refIndex] ?? '';
                          }
                        }

                        if (remark.isEmpty ||
                            remark.startsWith('参考图') ||
                            RegExp(r'^参考图\d+$').hasMatch(remark)) {
                          remark = '参考图';
                        }

                        newReferences.add(
                          '$remark是第${i + 1}张提供的图片[Image${i + 1}]',
                        );
                      }

                      // 3. Prepend the new references
                      if (newReferences.isNotEmpty) {
                        updatedPrompt =
                            '${newReferences.join('，')}。$updatedPrompt';
                      }

                      final updatedShot = shot.copyWith(
                        manualReferenceImages: manualImages,
                        assetRemarks: assetRemarks,
                        referenceImagePaths: referenceImagePaths,
                        prompt: updatedPrompt,
                      );

                      final newShots = List<Shot>.from(currentTab!.shots);
                      newShots[shotIndex] = updatedShot;
                      ref
                          .read(filmProjectProvider.notifier)
                          .updateCurrentTabShots(newShots);
                      _saveState();
                      Navigator.pop(context);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              cacheWidth: 200,
                              File(imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey,
                                child: const Icon(Icons.error),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          imageName,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
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
        ],
      ),
    );
  }

  Future<void> _editImageRemark(int index) async {
    final currentRemark =
        ref.read(filmProjectProvider).currentTab?.imageRemarks[index] ??
        _imageRemarks[index] ??
        '';
    final controller = TextEditingController(text: currentRemark);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('编辑图片备注', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            hintText: '输入图片描述信息',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(context);
            },
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text;
              controller.dispose();
              Navigator.pop(context, text);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        if (result.isEmpty) {
          _imageRemarks.remove(index);
        } else {
          _imageRemarks[index] = result;
        }
      });
      ref
          .read(filmProjectProvider.notifier)
          .updateCurrentTabImageRemark(index, result);
      _saveState();
    }
  }

  void _insertImageReference(int imageIndex) {
    if (_editingIndex == null) return;
    final currentText = _editController.text;
    final selection = _editController.selection;
    final cursorPos = selection.baseOffset;

    final insertText = '是第$imageIndex张提供的图片[Image$imageIndex]';
    final newText =
        currentText.substring(0, cursorPos) +
        insertText +
        currentText.substring(cursorPos);

    setState(() {
      _editController.text = newText;
      _editController.selection = TextSelection.collapsed(
        offset: cursorPos + insertText.length,
      );
    });
  }

  Future<void> _saveState() async {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null) return;

    await _storageService.saveWorkshopState(
      referenceImages: {
        'images': currentTab.referenceImages
            .where((p) => p.isNotEmpty)
            .toList(),
      },
      selectedStoryboard: _selectedStoryboard,
      imageRemarks: currentTab.imageRemarks.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      shots: currentTab.shots.map((s) => s.toJson()).toList(),
      shotStatus: currentTab.shotStatus.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      shotImages: currentTab.shotImages.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      shotTimer: currentTab.shotTimer.map((k, v) => MapEntry(k.toString(), v)),
      sceneAssets: currentTab.sceneAssets
          .map((asset) => asset.toJson())
          .toList(),
      selectedModel: _selectedModel,
      selectedAspectRatio: _selectedAspectRatio,
      selectedImageSize: _selectedImageSize,
      selectedImageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
      lastScriptContent: _lastScriptContent,
      fullScript: _fullScriptController.text,
    );
  }

  Future<void> _matchAssetsToShots() async {
    // 防止重复匹配
    if (ref.read(backgroundTaskProvider.notifier).hasActiveTask('match_')) {
      // 如果已有匹配任务在运行，尝试恢复对话框
      final matchState = ref.read(matchingTaskProvider);
      if (matchState != null &&
          matchState.isRunning &&
          matchState.isMinimized) {
        _showRestoredMatchingDialog();
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已有匹配任务在运行中')));
      }
      return;
    }

    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || currentTab.shots.isEmpty) return;

    final apiConfigs = ref.read(apiConfigsProvider);
    if (apiConfigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先配置聊天模型和视觉模型API')));
      }
      return;
    }

    final chatConfigs = apiConfigs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先配置聊天模型API，用于资产匹配')));
      }
      return;
    }

    final visionConfigs = apiConfigs.where((c) => c.type == 'vision').toList();
    if (visionConfigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先配置并默认启用视觉模型API，用于解析参考图内容')),
        );
      }
      return;
    }

    final defaultConfig = chatConfigs.firstWhere(
      (c) => c.isDefault && c.type == 'chat',
      orElse: () => chatConfigs.first,
    );
    final visionConfig = visionConfigs.firstWhere(
      (c) => c.isDefault,
      orElse: () => visionConfigs.first,
    );

    final allAssets = ref.read(assetProvider);
    final referenceImages = FilmWorkshopService.buildMatchingReferenceImages(
      slotReferenceImages: currentTab.referenceImages,
      slotRemarks: currentTab.imageRemarks,
      slotAssetIds: currentTab.slotAssetIds,
      globalAssets: allAssets,
      sceneAssets: currentTab.sceneAssets,
    );

    if (referenceImages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先添加参考图片')));
      }
      return;
    }

    final shotsToMatch = _matchOnlyUnmatched
        ? currentTab.shots
              .where(
                (s) =>
                    s.referenceImagePaths.isEmpty &&
                    s.manualReferenceImages.isEmpty,
              )
              .toList()
        : currentTab.shots;
    final originalIndicesForMatch = _matchOnlyUnmatched
        ? currentTab.shots
              .asMap()
              .entries
              .where(
                (e) =>
                    e.value.referenceImagePaths.isEmpty &&
                    e.value.manualReferenceImages.isEmpty,
              )
              .map((e) => e.key)
              .toList()
        : null;

    if (shotsToMatch.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有需要匹配的分镜头')));
      }
      return;
    }

    final imagePathList = referenceImages
        .map((item) => item.imagePath)
        .toList();
    final imageRemarkList = referenceImages
        .map((item) => item.effectiveName)
        .toList();

    ref.read(filmProjectProvider.notifier).startGeneration();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MatchingProgressDialog(
        service: _service,
        apiUrl: defaultConfig.url,
        apiKey: defaultConfig.key,
        model: defaultConfig.model,
        visionApiUrl: visionConfig.url,
        visionApiKey: visionConfig.key,
        visionModel: visionConfig.model,
        shots: shotsToMatch,
        originalIndices: originalIndicesForMatch,
        referenceImages: referenceImages,
        fullScript: _fullScriptController.text,
        onComplete: (results, {List<int>? originalIndices}) {
          final newShots = List<Shot>.from(currentTab.shots);
          for (int i = 0; i < results.length; i++) {
            final result = results[i];
            final shotIndex =
                originalIndices != null && i < originalIndices.length
                ? originalIndices[i]
                : i;
            if (result.isNotEmpty && shotIndex < newShots.length) {
              final shot = newShots[shotIndex];
              final mappings = <String>[];
              final usedImagePaths = <String>[];
              final assetRemarks = <String, String>{};

              int newIndex = 1;
              for (final idx in result) {
                if (idx > 0 && idx <= imagePathList.length) {
                  final imagePath = imagePathList[idx - 1];
                  final remark = imageRemarkList[idx - 1];
                  mappings.add('$remark是第$newIndex张提供的图片[Image$newIndex]');
                  usedImagePaths.add(imagePath);
                  assetRemarks[imagePath] = remark;
                  newIndex++;
                }
              }

              if (mappings.isNotEmpty) {
                String cleanedPrompt = shot.prompt.replaceAll(
                  RegExp(r'[^。]*是第\d+张提供的图片\[Image\d+\][,、。]*\s*'),
                  '',
                );
                final updatedShot = shot.copyWith(
                  prompt: '${mappings.join(', ')}。${cleanedPrompt.trim()}',
                  referenceImagePaths: usedImagePaths,
                  manualReferenceImages: const [],
                  assetRemarks: assetRemarks,
                );
                newShots[shotIndex] = updatedShot;
              }
            }
          }
          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabShots(newShots);
          ref.read(filmProjectProvider.notifier).finishGeneration();
          ref.read(matchingTaskProvider.notifier).clear();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('资产匹配完成')));
          }
        },
      ),
    );
  }

  /// 恢复已最小化的匹配进度对话框
  void _showRestoredMatchingDialog() {
    ref.read(matchingTaskProvider.notifier).restore();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _MatchingProgressRestoredDialog(),
    );
  }

  Future<void> _saveProject() async {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || currentTab.shots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前没有分镜内容可保存')));
      }
      return;
    }

    final projectName = _titleController.text.trim();
    if (projectName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入项目名称')));
      }
      return;
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final storyboardDir = Directory(
        path.join(appDir.path, 'data', 'storyboard'),
      );
      if (!await storyboardDir.exists()) {
        await storyboardDir.create(recursive: true);
      }

      final file = File(path.join(storyboardDir.path, '$projectName.json'));

      final projectData = {
        'version': 1,
        'title': projectName,
        'selectedModel': _selectedModel,
        'selectedAspectRatio': _selectedAspectRatio,
        'selectedImageSize': _selectedImageSize,
        'selectedImageQuality': _selectedImageQuality,
        'sampleSteps': _zImageBaseSampleSteps,
        'shots': currentTab.shots.map((s) => s.toJson()).toList(),
        'referenceImages': currentTab.referenceImages,
        'imageRemarks': currentTab.imageRemarks.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
        'shotStatus': currentTab.shotStatus.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
        'shotImages': currentTab.shotImages.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
        'shotTimer': currentTab.shotTimer.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      };

      await file.writeAsString(jsonEncode(projectData));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('项目已保存: ${file.path}')));
        setState(() {
          _selectedStoryboard = '$projectName.json';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  List<String> _getStoryboardFiles() {
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final storyboardDir = Directory(
        path.join(appDir.path, 'data', 'storyboard'),
      );
      if (!storyboardDir.existsSync()) return [];
      return storyboardDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.txt') || f.path.endsWith('.json'))
          .map((f) => path.basename(f.path))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _loadStoryboard(String? filename) async {
    if (filename == null) return;
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final filePath = path.join(appDir.path, 'data', 'storyboard', filename);
      final file = File(filePath);
      if (!await file.exists()) return;

      if (filename.toLowerCase().endsWith('.json')) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        setState(() {
          _selectedStoryboard = filename;
          _titleController.text =
              data['title'] ?? path.basenameWithoutExtension(filename);
          if (data['selectedModel'] != null)
            _selectedModel = data['selectedModel'];
          if (data['selectedAspectRatio'] != null)
            _selectedAspectRatio = data['selectedAspectRatio'];
          if (data['selectedImageSize'] != null)
            _selectedImageSize = data['selectedImageSize'];
          if (data['selectedImageQuality'] != null)
            _selectedImageQuality = data['selectedImageQuality'];
          if (data['sampleSteps'] != null) {
            _zImageBaseSampleSteps = (data['sampleSteps'] as num).toInt();
          }
          final normalized = _normalizeWorkshopImageParams(
            model: _selectedModel,
            aspectRatio: _selectedAspectRatio,
            imageSize: _selectedImageSize,
            imageQuality: _selectedImageQuality,
            sampleSteps: _zImageBaseSampleSteps,
          );
          _selectedAspectRatio = normalized['aspectRatio'] as String;
          _selectedImageSize = normalized['imageSize'] as String;
          _selectedImageQuality = normalized['imageQuality'] as String;
          _zImageBaseSampleSteps = normalized['sampleSteps'] as int;

          List<Shot> loadedShots = [];
          if (data['shots'] != null) {
            loadedShots = (data['shots'] as List)
                .map((s) => Shot.fromJson(s))
                .toList();
          }

          if (data['referenceImages'] != null) {
            final imgs = List<String>.from(data['referenceImages']);
            for (int i = 0; i < imgs.length && i < 14; i++) {
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabReferenceImage(i, imgs[i]);
            }
          }

          if (data['imageRemarks'] != null) {
            (data['imageRemarks'] as Map<String, dynamic>).forEach((k, v) {
              ref
                  .read(filmProjectProvider.notifier)
                  .updateCurrentTabImageRemark(int.parse(k), v as String);
            });
          }

          final statusMap = <int, String>{};
          if (data['shotStatus'] != null) {
            (data['shotStatus'] as Map<String, dynamic>).forEach((k, v) {
              statusMap[int.parse(k)] = v as String;
            });
          }

          final imagesMap = <int, String?>{};
          if (data['shotImages'] != null) {
            (data['shotImages'] as Map<String, dynamic>).forEach((k, v) {
              if (v != null) imagesMap[int.parse(k)] = v as String;
            });
          }

          final timerMap = <int, int>{};
          if (data['shotTimer'] != null) {
            (data['shotTimer'] as Map<String, dynamic>).forEach((k, v) {
              timerMap[int.parse(k)] = v as int;
            });
          }

          ref
              .read(filmProjectProvider.notifier)
              .updateCurrentTabShots(loadedShots);
          for (var entry in statusMap.entries) {
            ref
                .read(filmProjectProvider.notifier)
                .updateCurrentTabShotStatus(entry.key, entry.value);
          }
          for (var entry in imagesMap.entries) {
            ref
                .read(filmProjectProvider.notifier)
                .updateCurrentTabShotImage(entry.key, entry.value);
          }
        });
        _syncZImageSampleStepsController();
        unawaited(_saveGenerateParams());
      } else {
        final content = await file.readAsString();
        final shots = _service.parseStoryboardFile(content);

        setState(() {
          _selectedStoryboard = filename;
          final statusMap = <int, String>{};
          for (int i = 0; i < shots.length; i++) {
            statusMap[i] = '待生成';
          }

          ref.read(filmProjectProvider.notifier).updateCurrentTabShots(shots);
          for (var entry in statusMap.entries) {
            ref
                .read(filmProjectProvider.notifier)
                .updateCurrentTabShotStatus(entry.key, entry.value);
          }
        });
      }
      _saveState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _generateImages() async {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || currentTab.shots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请选择分镜脚本')));
      }
      return;
    }

    final tasks = <int>[];
    if (_selectedShotIndices.isNotEmpty) {
      tasks.addAll(_selectedShotIndices);
    } else {
      for (int i = 0; i < currentTab.shots.length; i++) {
        final status = currentTab.shotStatus[i];
        if (status != '生成中') {
          tasks.add(i);
        }
      }
    }

    if (tasks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有可生成的镜头')));
      }
      return;
    }

    await ref
        .read(filmWorkshopControllerProvider)
        .generateShots(
          taskIndices: tasks,
          selectedStoryboard: _selectedStoryboard ?? 'untitled',
          selectedModel: _selectedModel,
          selectedAspectRatio: _selectedAspectRatio,
          selectedImageSize: _selectedImageSize,
          selectedImageQuality: _selectedImageQuality,
          sampleSteps: _resolveSampleStepsForCurrentModel(),
          referenceImages: currentTab.referenceImages,
          imageRemarks: currentTab.imageRemarks,
        );

    final failedCount = currentTab.shotStatus.values
        .where((s) => s == '失败')
        .length;
    if (failedCount > 0 && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text('生成完成', style: TextStyle(color: AppColors.text)),
          content: Text(
            '共${failedCount}个镜头生成失败',
            style: const TextStyle(color: AppColors.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                '关闭',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _retryFailedShots();
              },
              child: const Text(
                '重新生成失败项',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _retryFailedShots() async {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null) return;

    final failedIndices = <int>[];

    for (int i = 0; i < currentTab.shots.length; i++) {
      if (currentTab.shotStatus[i] == '失败') {
        failedIndices.add(i);
      }
    }

    if (failedIndices.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有失败的镜头')));
      }
      return;
    }

    await ref
        .read(filmWorkshopControllerProvider)
        .generateShots(
          taskIndices: failedIndices,
          selectedStoryboard: _selectedStoryboard ?? 'untitled',
          selectedModel: _selectedModel,
          selectedAspectRatio: _selectedAspectRatio,
          selectedImageSize: _selectedImageSize,
          selectedImageQuality: _selectedImageQuality,
          sampleSteps: _resolveSampleStepsForCurrentModel(),
          referenceImages: currentTab.referenceImages,
          imageRemarks: currentTab.imageRemarks,
        );
  }

  Future<void> _retrySingleShot(int index) async {
    await ref
        .read(filmWorkshopControllerProvider)
        .generateShots(
          taskIndices: [index],
          selectedStoryboard: _selectedStoryboard ?? 'untitled',
          selectedModel: _selectedModel,
          selectedAspectRatio: _selectedAspectRatio,
          selectedImageSize: _selectedImageSize,
          selectedImageQuality: _selectedImageQuality,
          sampleSteps: _resolveSampleStepsForCurrentModel(),
          referenceImages:
              ref.read(filmProjectProvider).currentTab?.referenceImages ??
              List.generate(14, (_) => ''),
          imageRemarks:
              ref.read(filmProjectProvider).currentTab?.imageRemarks ?? {},
        );
  }

  Future<void> _generateSingleShot(int index) async {
    // Manually start generation mode to trigger global timer in provider
    // ref.read(filmWorkshopProvider.notifier).startGeneration([index]);
    // generateShots calls startGeneration internally.

    await ref
        .read(filmWorkshopControllerProvider)
        .generateShots(
          taskIndices: [index],
          selectedStoryboard: _selectedStoryboard ?? 'untitled',
          selectedModel: _selectedModel,
          selectedAspectRatio: _selectedAspectRatio,
          selectedImageSize: _selectedImageSize,
          selectedImageQuality: _selectedImageQuality,
          sampleSteps: _resolveSampleStepsForCurrentModel(),
          referenceImages:
              ref.read(filmProjectProvider).currentTab?.referenceImages ??
              List.generate(14, (_) => ''),
          imageRemarks:
              ref.read(filmProjectProvider).currentTab?.imageRemarks ?? {},
        );
  }

  Widget _buildSelect(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    Map<String, String>? labels,
  }) {
    final normalizedItems = items.contains(value) ? items : [value, ...items];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.sidebar,
        style: const TextStyle(color: AppColors.text, fontSize: 13),
        items: normalizedItems.map((e) {
          if (e == 'divider') {
            return DropdownMenuItem<String>(
              enabled: false,
              value: e,
              child: Container(height: 1, color: AppColors.border2),
            );
          }
          return DropdownMenuItem<String>(
            value: e,
            child: Text(labels?[e] ?? e),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildZImageSampleStepsInput() {
    return Container(
      width: 88,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: _zImageSampleStepsController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.text, fontSize: 12),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: '步数',
          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        onSubmitted: (_) => _commitZImageBaseSampleSteps(),
        onEditingComplete: _commitZImageBaseSampleSteps,
      ),
    );
  }

  void _showSplitRulesDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('拆解规则', style: TextStyle(color: AppColors.text)),
        content: SizedBox(
          width: 600,
          height: 400,
          child: TextField(
            controller: _systemPromptController,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: AppColors.text, fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入拆解规则',
              hintStyle: TextStyle(color: AppColors.textSecondary),
            ),
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
            onPressed: () async {
              try {
                final appDir = File(Platform.resolvedExecutable).parent;
                final promptPath = path.join(
                  appDir.path,
                  'data',
                  'Settings',
                  'storyboard_system_prompt.txt',
                );
                final file = File(promptPath);
                await file.parent.create(recursive: true);
                await file.writeAsString(_systemPromptController.text);
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('拆解规则已保存')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
                }
              }
            },
            child: const Text('保存', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showNewProjectDialog() {
    final projectNameController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('新建项目', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: projectNameController,
          autofocus: true,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            labelText: '项目名称',
            labelStyle: TextStyle(color: AppColors.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
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
            onPressed: () async {
              final projectName = projectNameController.text.trim();
              if (projectName.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请输入项目名称')));
                }
                return;
              }
              await _saveProject();
              ref.read(filmWorkshopProvider.notifier).clearShots();
              setState(() {
                _titleController.text = projectName;
                _selectedStoryboard = null;
              });
              for (int i = 0; i < 14; i++) {
                ref
                    .read(filmProjectProvider.notifier)
                    .updateCurrentTabReferenceImage(i, '');
                ref
                    .read(filmProjectProvider.notifier)
                    .updateCurrentTabImageRemark(i, '');
              }
              await _saveState();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('已创建新项目: $projectName')));
              }
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showFullScriptDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: Row(
          children: [
            const Text('完整剧本', style: TextStyle(color: AppColors.text)),
            const Spacer(),
            TextButton(
              onPressed: () => _analyzeScript(),
              child: const Text(
                '通读全文',
                style: TextStyle(color: AppColors.primary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => _showScriptAnalysisDialog(),
              child: const Text(
                '剧情详解',
                style: TextStyle(color: AppColors.primary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['txt'],
                );
                if (result != null && result.files.single.path != null) {
                  final file = File(result.files.single.path!);
                  final content = await file.readAsString();
                  setState(() => _fullScriptController.text = content);
                  _saveState();
                }
              },
              child: const Text(
                '导入TXT',
                style: TextStyle(color: AppColors.primary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.sidebar,
                    title: const Text(
                      '确认清空',
                      style: TextStyle(color: AppColors.text),
                    ),
                    content: const Text(
                      '确定要清空完整剧本吗？',
                      style: TextStyle(color: AppColors.text),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _fullScriptController.clear());
                          _saveState();
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          '确定',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: const Text(
                '清空',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 600,
          height: 400,
          child: TextField(
            controller: _fullScriptController,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: AppColors.text),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入完整剧本内容，AI将基于此剧本理解故事基调并拆解分镜',
              hintStyle: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _saveState();
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showSplitScriptDialog() {
    final scriptController = TextEditingController(text: _lastScriptContent);
    String selectedAssistant = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final apiConfigs = ref.read(apiConfigsProvider);
          final chatConfigs = apiConfigs
              .where((c) => c.type == 'chat')
              .toList();

          if (selectedAssistant.isEmpty && chatConfigs.isNotEmpty) {
            selectedAssistant = chatConfigs
                .firstWhere((c) => c.isDefault, orElse: () => chatConfigs.first)
                .id;
          }

          return AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: Row(
              children: [
                const Text('拆解分镜', style: TextStyle(color: AppColors.text)),
                const Spacer(),
                if (scriptController.text.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      scriptController.clear();
                      setState(() {});
                    },
                    child: const Text(
                      '清空内容',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg,
                    border: Border.all(color: AppColors.border2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<String>(
                    value: selectedAssistant,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.sidebar,
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                    items: chatConfigs
                        .map(
                          (config) => DropdownMenuItem(
                            value: config.id,
                            child: Text(config.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedAssistant = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: TextField(
                controller: scriptController,
                maxLines: null,
                expands: true,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '输入剧本内容',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  scriptController.dispose();
                  Navigator.pop(context);
                },
                child: const Text(
                  '取消',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final script = scriptController.text;
                  // Update state and persist even if user cancels later?
                  // No, usually only on confirm.
                  // But user requirement says: "Input script will be persisted until manually cleared"
                  // So we should update it here.
                  this.setState(() {
                    _lastScriptContent = script;
                  });
                  _saveState();

                  scriptController.dispose();
                  Navigator.pop(context);
                  await _splitScriptAndDisplay(script, selectedAssistant);
                },
                child: const Text(
                  '拆解为分镜头',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reSplitScript() async {
    if (_lastScriptContent.isEmpty) return;

    // Use default assistant
    final apiConfigs = ref.read(apiConfigsProvider);
    final chatConfigs = apiConfigs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先配置聊天API')));
      }
      return;
    }

    final defaultAssistant = chatConfigs.firstWhere(
      (c) => c.isDefault,
      orElse: () => chatConfigs.first,
    );

    // Confirm dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('重新拆分', style: TextStyle(color: AppColors.text)),
        content: const Text(
          '确定要使用上次的剧本重新拆分吗？这将覆盖当前的分镜内容。',
          style: TextStyle(color: AppColors.text),
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
              Navigator.pop(context);
              _splitScriptAndDisplay(_lastScriptContent, defaultAssistant.id);
            },
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _splitScriptAndDisplay(String script, String assistantId) async {
    if (script.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入剧本内容')));
      }
      return;
    }

    final apiConfigs = ref.read(apiConfigsProvider);
    final selectedConfig = apiConfigs.firstWhere(
      (c) => c.id == assistantId,
      orElse: () => apiConfigs.firstWhere(
        (c) => c.isDefault && c.type == 'chat',
        orElse: () => apiConfigs.firstWhere(
          (c) => c.type == 'chat',
          orElse: () => apiConfigs.first,
        ),
      ),
    );

    String scriptAnalysis = '';
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final projectName = _titleController.text.trim().isEmpty
          ? '未命名项目'
          : _titleController.text.trim();
      final analysisFile = File(
        path.join(appDir.path, 'data', '剧本', '$projectName-阅读理解.md'),
      );
      if (await analysisFile.exists()) {
        scriptAnalysis = await analysisFile.readAsString();
      }
    } catch (e) {
      // 忽略错误，继续拆解
    }

    ref.read(filmProjectProvider.notifier).startSplitting();

    try {
      final storyboardService = StoryboardService(ref.read(apiServiceProvider));
      final shots = await storyboardService.splitScript(
        apiUrl: selectedConfig.url,
        apiKey: selectedConfig.key,
        model: selectedConfig.model,
        script: script,
        artStyle: '',
        worldView: '',
        aspectRatio: _selectedAspectRatio,
        assets: [],
        fullScript: _fullScriptController.text,
        scriptAnalysis: scriptAnalysis,
        onProgress: (chunk) {
          ref.read(filmProjectProvider.notifier).updateThoughtProcess(chunk);
        },
      );

      final statusMap = <int, String>{};
      for (int i = 0; i < shots.length; i++) {
        statusMap[i] = '待生成';
      }

      ref.read(filmProjectProvider.notifier).updateCurrentTabShots(shots);
      for (var entry in statusMap.entries) {
        ref
            .read(filmProjectProvider.notifier)
            .updateCurrentTabShotStatus(entry.key, entry.value);
      }

      ref.read(filmProjectProvider.notifier).finishSplitting();

      if (mounted) {
        setState(() => _splitMinimized = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拆解完成，共${shots.length}个镜头')));
      }
      _saveState();
    } catch (e) {
      ref.read(filmProjectProvider.notifier).finishSplitting();
      if (mounted) {
        setState(() => _splitMinimized = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拆解失败: $e')));
      }
    }
  }

  void _showGeneratedImagesDialog() {
    final projectState = ref.read(filmProjectProvider);
    final currentTab = projectState.currentTab;
    if (currentTab == null || currentTab.shots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先拆解分镜后再生成资产图')));
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SceneAssetGenerationDialog(
        projectName: _titleController.text.trim().isEmpty
            ? '未命名项目'
            : _titleController.text.trim(),
        service: _service,
        selectedModel: _selectedModel,
        selectedAspectRatio: _selectedAspectRatio,
        selectedImageSize: _selectedImageSize,
        selectedImageQuality: _selectedImageQuality,
        sampleSteps: _resolveSampleStepsForCurrentModel(),
        fullScript: _fullScriptController.text,
        onImageParamsChanged: _applyAssetDialogImageParams,
        onChanged: _saveState,
      ),
    );
  }

  Future<void> _analyzeScript() async {
    if (_fullScriptController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先输入完整剧本')));
      }
      return;
    }

    // 防止重复执行
    if (ref.read(backgroundTaskProvider.notifier).hasActiveTask('analyze_')) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已有通读全文任务在运行中')));
      }
      return;
    }

    final configs = ref.read(apiConfigsProvider);
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();
    final selectedConfig =
        chatConfigs.where((c) => c.isDefault).firstOrNull ??
        chatConfigs.firstOrNull ??
        configs.first;
    final apiService = ref.read(apiServiceProvider);
    final storyboardService = StoryboardService(apiService);
    final projectName = _titleController.text.trim();

    final analysisBuffer = StringBuffer();
    final analysisController = TextEditingController();
    void Function(void Function())? dialogSetState;
    bool isMinimized = false;
    String? bgTaskId;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          return AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: Row(
              children: [
                const Expanded(
                  child: Text(
                    '正在阅读理解剧本...',
                    style: TextStyle(color: AppColors.text),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    if (bgTaskId != null) {
                      // 已经有后台任务了，直接关闭
                      isMinimized = true;
                      Navigator.pop(context);
                      return;
                    }
                    bgTaskId =
                        'analyze_${DateTime.now().millisecondsSinceEpoch}';
                    ref
                        .read(backgroundTaskProvider.notifier)
                        .addTask(
                          BackgroundTask(
                            id: bgTaskId!,
                            title: '通读全文',
                            description: '正在阅读理解剧本...',
                            targetPageIndex: 1, // 影视工坊
                          ),
                        );
                    isMinimized = true;
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.minimize,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  tooltip: '最小化到后台',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF3a3a3a),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: Column(
                children: [
                  const LinearProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          analysisController.text,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    try {
      final analysis = await storyboardService.analyzeScript(
        apiUrl: selectedConfig.url,
        apiKey: selectedConfig.key,
        model: selectedConfig.model,
        script: _fullScriptController.text,
        onProgress: (chunk) {
          analysisBuffer.write(chunk);
          analysisController.text = analysisBuffer.toString();
          dialogSetState?.call(() {});
        },
      );

      final appDir = File(Platform.resolvedExecutable).parent;
      final scriptDir = Directory(path.join(appDir.path, 'data', '剧本'));
      await scriptDir.create(recursive: true);
      final analysisFile = File(
        path.join(scriptDir.path, '$projectName-阅读理解.md'),
      );
      await analysisFile.writeAsString(analysis);

      if (mounted) {
        if (bgTaskId != null) {
          ref
              .read(backgroundTaskProvider.notifier)
              .updateTask(
                bgTaskId!,
                description: '阅读理解完成',
                progress: 1.0,
                isComplete: true,
              );
        }
        if (!isMinimized) Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: const Text('阅读完成', style: TextStyle(color: AppColors.text)),
            content: const Text(
              '已经阅读全文，点击查看阅读理解的结果',
              style: TextStyle(color: AppColors.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '关闭',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Process.run('notepad', [analysisFile.path]);
                },
                child: const Text(
                  '打开剧情详解',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (bgTaskId != null) {
        ref
            .read(backgroundTaskProvider.notifier)
            .updateTask(
              bgTaskId!,
              description: '阅读理解失败',
              isFailed: true,
              error: e.toString(),
            );
      }
      if (mounted) {
        if (!isMinimized) Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('阅读理解失败: $e')));
      }
    }
  }

  void _showScriptAnalysisDialog() async {
    final projectName = _titleController.text.trim();
    final appDir = File(Platform.resolvedExecutable).parent;
    final analysisFile = File(
      path.join(appDir.path, 'data', '剧本', '$projectName-阅读理解.md'),
    );

    if (!await analysisFile.exists()) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.sidebar,
            title: const Text('提示', style: TextStyle(color: AppColors.text)),
            content: const Text(
              '尚未生成剧情详解，请先点击"通读全文"按钮',
              style: TextStyle(color: AppColors.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '确定',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    final content = await analysisFile.readAsString();
    final controller = TextEditingController(text: content);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: Row(
            children: [
              const Text('剧情详解', style: TextStyle(color: AppColors.text)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Process.run('notepad', [analysisFile.path]);
                },
                child: const Text(
                  '用记事本打开',
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 800,
            height: 600,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(16),
              ),
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
              onPressed: () async {
                await analysisFile.writeAsString(controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已保存剧情详解')));
                }
              },
              child: const Text(
                '保存',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _GlowContainer extends StatefulWidget {
  final bool isActive;
  final bool isEditing;
  final Widget child;

  const _GlowContainer({
    Key? key,
    required this.isActive,
    required this.isEditing,
    required this.child,
  }) : super(key: key);

  @override
  State<_GlowContainer> createState() => _GlowContainerState();
}

class _GlowContainerState extends State<_GlowContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(_GlowContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.primary.withOpacity(0.1 + 0.1 * _animation.value)
                : AppColors.sidebar,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isActive
                  ? AppColors.primary
                  : (widget.isEditing ? AppColors.primary : AppColors.border1),
              width: widget.isActive ? 2 : 1,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(
                        0.3 + 0.3 * _animation.value,
                      ),
                      blurRadius: 8 + 8 * _animation.value,
                      spreadRadius: 2 + 2 * _animation.value,
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _FullScreenImagePreview extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const _FullScreenImagePreview({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_FullScreenImagePreview> createState() =>
      _FullScreenImagePreviewState();
}

class _FullScreenImagePreviewState extends State<_FullScreenImagePreview> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < widget.images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景点击关闭
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(color: Colors.black87),
          ),
          // 图片浏览
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(
                  widget.images[index],
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              );
            },
          ),
          // 左右切换按钮 (键盘支持)
          Focus(
            autofocus: true,
            onKey: (node, event) {
              if (event is RawKeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _previousPage();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _nextPage();
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  Navigator.pop(context);
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: const SizedBox.shrink(),
          ),
          // 左右箭头 UI
          if (_currentIndex > 0)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: Colors.white70,
                    size: 40,
                  ),
                  onPressed: _previousPage,
                ),
              ),
            ),
          if (_currentIndex < widget.images.length - 1)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 40,
                  ),
                  onPressed: _nextPage,
                ),
              ),
            ),
          // 关闭按钮
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          // 页码指示器
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SceneAssetGenerationDialog extends ConsumerStatefulWidget {
  final String projectName;
  final FilmWorkshopService service;
  final String selectedModel;
  final String selectedAspectRatio;
  final String selectedImageSize;
  final String selectedImageQuality;
  final int? sampleSteps;
  final String fullScript;
  final _FilmWorkshopImageParamsChanged onImageParamsChanged;
  final Future<void> Function() onChanged;

  const _SceneAssetGenerationDialog({
    required this.projectName,
    required this.service,
    required this.selectedModel,
    required this.selectedAspectRatio,
    required this.selectedImageSize,
    required this.selectedImageQuality,
    required this.sampleSteps,
    required this.fullScript,
    required this.onImageParamsChanged,
    required this.onChanged,
  });

  @override
  ConsumerState<_SceneAssetGenerationDialog> createState() =>
      _SceneAssetGenerationDialogState();
}

class _SceneAssetGenerationDialogState
    extends ConsumerState<_SceneAssetGenerationDialog>
    with SingleTickerProviderStateMixin {
  static const int _maxAssetGenerationConcurrency = 5;
  late final TabController _tabController;
  final _uuid = const Uuid();
  final _zImageSampleStepsController = TextEditingController();
  Future<void> _assetPersistQueue = Future.value();
  List<FilmSceneAsset> _assets = [];
  bool _isExtracting = false;
  bool _isGenerating = false;
  String _extractLog = '';
  late String _selectedModel;
  late String _selectedAspectRatio;
  late String _selectedImageSize;
  late String _selectedImageQuality;
  late int _zImageBaseSampleSteps;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _assets = List<FilmSceneAsset>.from(
      ref.read(filmProjectProvider).currentTab?.sceneAssets ?? const [],
    );
    final normalized = _FilmWorkshopImageParamSupport.normalizeParams(
      model: widget.selectedModel,
      aspectRatio: widget.selectedAspectRatio,
      imageSize: widget.selectedImageSize,
      imageQuality: widget.selectedImageQuality,
      sampleSteps: widget.sampleSteps,
    );
    _selectedModel = widget.selectedModel;
    _selectedAspectRatio = normalized['aspectRatio'] as String;
    _selectedImageSize = normalized['imageSize'] as String;
    _selectedImageQuality = normalized['imageQuality'] as String;
    _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    _syncZImageSampleStepsController();
  }

  @override
  void dispose() {
    _zImageSampleStepsController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _persistAssets() async {
    ref.read(filmProjectProvider.notifier).updateCurrentTabSceneAssets(_assets);
    await widget.onChanged();
  }

  Future<void> _queuePersistAssets() {
    _assetPersistQueue = _assetPersistQueue
        .then((_) => _persistAssets())
        .catchError((error, stackTrace) {
          debugPrint('Error persisting scene assets: $error');
        });
    return _assetPersistQueue;
  }

  void _replaceAsset(FilmSceneAsset asset, {bool persist = true}) {
    final index = _assets.indexWhere((item) => item.id == asset.id);
    if (index == -1) return;
    setState(() {
      _assets = [
        for (var i = 0; i < _assets.length; i++)
          if (i == index) asset else _assets[i],
      ];
    });
    if (persist) unawaited(_queuePersistAssets());
  }

  FilmSceneAsset? _assetById(String id) {
    for (final asset in _assets) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  String _categoryLabel(String category) {
    const labels = {
      'Person': '人物',
      'Scene': '场景',
      'Prop': '道具',
      'Costume': '服装',
      'Other': '其他',
    };
    return labels[category] ?? category;
  }

  List<ApiConfig> _orderedChatConfigs(List<ApiConfig> configs) {
    final ordered = <ApiConfig>[];

    void addConfigs(Iterable<ApiConfig> items) {
      for (final config in items) {
        final hasRequiredFields =
            config.url.trim().isNotEmpty && config.model.trim().isNotEmpty;
        final alreadyAdded = ordered.any((item) => item.id == config.id);
        if (!hasRequiredFields || alreadyAdded) {
          continue;
        }
        ordered.add(config);
      }
    }

    addConfigs(configs.where((config) => config.isDefault));
    addConfigs(
      configs.where(
        (config) => !config.isDefault && config.key.trim().isNotEmpty,
      ),
    );
    addConfigs(configs.where((config) => !config.isDefault));
    return ordered;
  }

  List<FilmSceneAssetView> _viewsForAsset(FilmSceneAsset asset) {
    return FilmSceneAssetViews.requiredForCategory(asset.category);
  }

  bool _usesSingleSceneView(FilmSceneAsset asset) {
    return asset.category == 'Scene';
  }

  bool get _isZImageBaseSelected =>
      _FilmWorkshopImageParamSupport.isZImageBaseModel(_selectedModel);

  List<String> get _activeAspectRatioItems =>
      _FilmWorkshopImageParamSupport.resolveAspectRatioItems(_selectedModel);

  List<String> get _activeImageSizeItems =>
      _FilmWorkshopImageParamSupport.resolveImageSizeItems(
        _selectedModel,
        _selectedAspectRatio,
      );

  Map<String, String>? get _activeImageSizeLabels =>
      _FilmWorkshopImageParamSupport.resolveImageSizeLabels(
        _selectedModel,
        _selectedAspectRatio,
      );

  bool get _showImageQualitySelect =>
      _FilmWorkshopImageParamSupport.showImageQualitySelect(_selectedModel);

  void _syncZImageSampleStepsController() {
    final text = _zImageBaseSampleSteps.toString();
    if (_zImageSampleStepsController.text != text) {
      _zImageSampleStepsController.text = text;
      _zImageSampleStepsController.selection = TextSelection.collapsed(
        offset: text.length,
      );
    }
  }

  void _persistImageParams() {
    widget.onImageParamsChanged(
      selectedModel: _selectedModel,
      selectedAspectRatio: _selectedAspectRatio,
      selectedImageSize: _selectedImageSize,
      selectedImageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );
  }

  int _commitZImageBaseSampleSteps() {
    final normalized = ZImageBaseGenerationPreset.parseSampleSteps(
      _zImageSampleStepsController.text,
      imageSize: _selectedImageSize,
    );
    if (_zImageBaseSampleSteps != normalized) {
      setState(() {
        _zImageBaseSampleSteps = normalized;
      });
      _persistImageParams();
    }
    _syncZImageSampleStepsController();
    return normalized;
  }

  void _applyDialogModelSelection(String model) {
    final wasZImageSelected = _isZImageBaseSelected;
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      _selectedImageSize,
    );
    final wasUsingDefaultSteps =
        _zImageBaseSampleSteps == previousDefaultSteps ||
        _zImageBaseSampleSteps < ZImageBaseGenerationPreset.minSampleSteps;
    final normalized = _FilmWorkshopImageParamSupport.normalizeParams(
      model: model,
      aspectRatio: _selectedAspectRatio,
      imageSize: _selectedImageSize,
      imageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );
    setState(() {
      _selectedModel = model;
      _selectedAspectRatio = normalized['aspectRatio'] as String;
      _selectedImageSize = normalized['imageSize'] as String;
      _selectedImageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
      if (_isZImageBaseSelected &&
          (!wasZImageSelected || wasUsingDefaultSteps)) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          _selectedImageSize,
        );
      }
    });
    _syncZImageSampleStepsController();
    _persistImageParams();
  }

  void _applyDialogAspectRatioSelection(String aspectRatio) {
    final normalized = _FilmWorkshopImageParamSupport.normalizeParams(
      model: _selectedModel,
      aspectRatio: aspectRatio,
      imageSize: _selectedImageSize,
      imageQuality: _selectedImageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );
    setState(() {
      _selectedAspectRatio = normalized['aspectRatio'] as String;
      _selectedImageSize = normalized['imageSize'] as String;
      _selectedImageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    });
    _syncZImageSampleStepsController();
    _persistImageParams();
  }

  void _applyDialogImageSizeSelection(String imageSize) {
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      _selectedImageSize,
    );
    final shouldFollowDefault =
        _zImageBaseSampleSteps == previousDefaultSteps ||
        _zImageBaseSampleSteps < ZImageBaseGenerationPreset.minSampleSteps;
    setState(() {
      _selectedImageSize = imageSize;
      if (_isZImageBaseSelected && shouldFollowDefault) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          imageSize,
        );
      }
    });
    _syncZImageSampleStepsController();
    _persistImageParams();
  }

  void _applyDialogImageQualitySelection(String imageQuality) {
    setState(() {
      _selectedImageQuality = GptImageGenerationPreset.normalizeQuality(
        imageQuality,
      );
    });
    _persistImageParams();
  }

  Widget _buildSelect(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    Map<String, String>? labels,
  }) {
    final normalizedItems = items.contains(value) ? items : [value, ...items];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        dropdownColor: AppColors.sidebar,
        style: const TextStyle(color: AppColors.text, fontSize: 13),
        items: normalizedItems.map((item) {
          if (item == 'divider') {
            return DropdownMenuItem<String>(
              enabled: false,
              value: item,
              child: Container(height: 1, color: AppColors.border2),
            );
          }
          return DropdownMenuItem<String>(
            value: item,
            child: Text(labels?[item] ?? item),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildZImageSampleStepsInput() {
    return Container(
      width: 88,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: _zImageSampleStepsController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.text, fontSize: 12),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: '步数',
          hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        onSubmitted: (_) => _commitZImageBaseSampleSteps(),
        onEditingComplete: _commitZImageBaseSampleSteps,
      ),
    );
  }

  Widget _buildImageParamsToolbar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '资产图片生成参数',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSelect(
                _selectedModel,
                _FilmWorkshopImageParamSupport.imageModelItems,
                (value) {
                  if (value != null) {
                    _applyDialogModelSelection(value);
                  }
                },
                labels: _FilmWorkshopImageParamSupport.imageModelLabels,
              ),
              _buildSelect(_selectedAspectRatio, _activeAspectRatioItems, (
                value,
              ) {
                if (value != null) {
                  _applyDialogAspectRatioSelection(value);
                }
              }),
              _buildSelect(
                _selectedImageSize,
                _activeImageSizeItems,
                (value) {
                  if (value != null) {
                    _applyDialogImageSizeSelection(value);
                  }
                },
                labels: _activeImageSizeLabels,
              ),
              if (_showImageQualitySelect)
                _buildSelect(
                  _selectedImageQuality,
                  GptImageGenerationPreset.qualityOptions,
                  (value) {
                    if (value != null) {
                      _applyDialogImageQualitySelection(value);
                    }
                  },
                  labels: GptImageGenerationPreset.qualityLabels,
                ),
              if (_isZImageBaseSelected) _buildZImageSampleStepsInput(),
            ],
          ),
        ],
      ),
    );
  }

  Future<List<ApiConfig>> _loadChatConfigs() async {
    await ref.read(apiConfigsProvider.notifier).ensureLoaded();
    return ref
        .read(apiConfigsProvider)
        .whereType<ApiConfig>()
        .where((config) => config.type == 'chat')
        .toList();
  }

  Future<void> _extractAssets() async {
    final currentTab = ref.read(filmProjectProvider).currentTab;
    if (currentTab == null || currentTab.shots.isEmpty) return;

    final chatConfigs = await _loadChatConfigs();
    if (!mounted) return;
    if (chatConfigs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先配置聊天模型API')));
      return;
    }
    setState(() {
      _isExtracting = true;
      _extractLog = '';
    });

    try {
      final triedErrors = <String>[];
      List<FilmSceneAsset>? extracted;
      for (final config in _orderedChatConfigs(chatConfigs)) {
        try {
          if (mounted) {
            setState(() {
              _extractLog = '正在尝试 ${config.name} 提取资产...\n';
            });
          }
          extracted = await widget.service.extractSceneAssets(
            apiUrl: config.url,
            apiKey: config.key,
            model: config.model,
            shots: currentTab.shots,
            fullScript: widget.fullScript,
            onProgress: (chunk) {
              if (!mounted) return;
              setState(() => _extractLog += chunk);
            },
          );
          break;
        } catch (e) {
          triedErrors.add('${config.name}: $e');
        }
      }
      if (extracted == null) {
        throw Exception(
          triedErrors.isEmpty ? '未找到可用聊天模型配置' : triedErrors.join('；'),
        );
      }
      final existingByKey = {
        for (final asset in _assets)
          '${asset.category}|${asset.name.toLowerCase()}': asset,
      };
      final merged = extracted.map((asset) {
        final existing =
            existingByKey['${asset.category}|${asset.name.toLowerCase()}'];
        if (existing == null) return asset;
        return asset.copyWith(
          id: existing.id,
          selected: existing.selected,
          status: existing.status,
          viewImages: existing.viewImages,
          viewStatus: existing.viewStatus,
          viewErrors: existing.viewErrors,
          assetId: existing.assetId,
        );
      }).toList();
      setState(() => _assets = merged);
      await _persistAssets();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已提取 ${merged.length} 个资产元素')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('资产提取失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  String _buildViewPrompt(FilmSceneAsset asset, FilmSceneAssetView view) {
    if (_usesSingleSceneView(asset)) {
      return '''
请生成影视场景资产参考图：${asset.name}。
资产类别：场景。
场景设定：${asset.description}
画面要求：这是用于后续分镜统一场景的环境设定图，请完整表现空间结构、主要建筑或地形布局、材质、天气和氛围。不要人物三视图，不要物体转面展示，不要多视图排版，不要文字水印。
''';
    }
    final viewName = view.name;
    final category = _categoryLabel(asset.category);
    final consistencyLine = view.name == FilmSceneAssetViews.front
        ? '基准要求：这张正面图会作为该资产后续所有视角的统一母版，请输出最稳定、最完整、最清晰的主体设定，避免遮挡、裁切、夸张透视和风格漂移。'
        : '一致性要求：必须与提供的正面参考图保持同一主体，严格锁定身份/结构/比例/材质/颜色/服装/零件布局，只允许改变观察视角，不得改脸、改造型、改配色或新增缺失元素。';
    return '''
请生成影视资产参考图：${asset.name}-$viewName。
资产类别：$category。
资产设定：${asset.description}
视图要求：${view.description}，${view.prompt}。
$consistencyLine
画面要求：单一主体，造型清晰，细节完整，电影美术设定图质感，背景简洁，不要拼贴，不要多视图排版，不要文字水印。
''';
  }

  Future<String> _generateAndSaveView({
    required FilmSceneAsset asset,
    required FilmSceneAssetView view,
    required String? frontPath,
  }) async {
    final referencePaths =
        _usesSingleSceneView(asset) || view.name == FilmSceneAssetViews.front
        ? const <String>[]
        : <String>[if (frontPath != null && frontPath.isNotEmpty) frontPath];
    final results = await ref
        .read(generateLogicServiceProvider)
        .runImageTask(
          GenerateImageTaskRequest(
            prompt: _buildViewPrompt(asset, view),
            model: _selectedModel,
            aspectRatio: _selectedAspectRatio,
            imageSize: _selectedImageSize,
            imageQuality: _selectedImageQuality,
            sampleSteps: _isZImageBaseSelected
                ? _commitZImageBaseSampleSteps()
                : _zImageBaseSampleSteps,
            referenceImagePaths: referencePaths,
          ),
        );
    if (results.isEmpty) {
      throw Exception('生成结果为空');
    }
    return widget.service.saveSceneAssetImage(
      imageUrl: results.first,
      projectName: widget.projectName,
      assetName: asset.name,
      viewName: view.name,
    );
  }

  Future<FilmSceneAsset> _upsertGlobalAsset(FilmSceneAsset asset) async {
    final frontPath = asset.viewImages[FilmSceneAssetViews.front] ?? '';
    if (frontPath.isEmpty) return asset;

    final globalAssets = ref.read(assetProvider);
    final existing = asset.assetId == null
        ? null
        : globalAssets.where((item) => item.id == asset.assetId).firstOrNull;
    final id = existing?.id ?? asset.assetId ?? _uuid.v4();
    final nextAsset = FilmWorkshopService.buildGlobalAssetFromSceneAsset(
      sceneAsset: asset,
      assetId: id,
    );
    if (existing == null) {
      await ref.read(assetProvider.notifier).addAsset(nextAsset);
    } else {
      await ref.read(assetProvider.notifier).updateAsset(nextAsset);
    }
    return asset.copyWith(assetId: id);
  }

  Future<FilmSceneAsset?> _generateAssetPipeline(
    String assetId, {
    String? onlyViewName,
  }) async {
    final initialAsset = _assetById(assetId);
    if (initialAsset == null) return null;
    var currentAsset = initialAsset;

    final targetViews = FilmSceneAssetViews.buildGenerationSequence(
      currentAsset.category,
      onlyViewName: onlyViewName,
      hasFrontImage:
          (currentAsset.viewImages[FilmSceneAssetViews.front] ?? '').isNotEmpty,
    );

    for (final view in targetViews) {
      currentAsset = _assetById(assetId) ?? currentAsset;
      final nextStatus = Map<String, String>.from(currentAsset.viewStatus);
      final nextErrors = Map<String, String>.from(currentAsset.viewErrors)
        ..remove(view.name);
      nextStatus[view.name] = '生成中';
      currentAsset = currentAsset.copyWith(
        status: '生成中',
        viewStatus: nextStatus,
        viewErrors: nextErrors,
      );
      _replaceAsset(currentAsset);

      try {
        final frontPath = currentAsset.viewImages[FilmSceneAssetViews.front];
        final savedPath = await _generateAndSaveView(
          asset: currentAsset,
          view: view,
          frontPath: frontPath,
        );
        final nextImages = Map<String, String>.from(currentAsset.viewImages);
        nextImages[view.name] = savedPath;
        nextStatus[view.name] = '已完成';
        currentAsset = currentAsset.copyWith(
          viewImages: nextImages,
          viewStatus: nextStatus,
          status: '生成中',
        );
        _replaceAsset(currentAsset);
      } catch (e) {
        nextStatus[view.name] = '失败';
        nextErrors[view.name] = e.toString();
        currentAsset = currentAsset.copyWith(
          viewStatus: nextStatus,
          viewErrors: nextErrors,
          status: '部分失败',
        );
        _replaceAsset(currentAsset);
        if (view.name == FilmSceneAssetViews.front) break;
      }
    }
    currentAsset = _assetById(assetId) ?? currentAsset;
    final complete = currentAsset.isComplete;
    currentAsset = currentAsset.copyWith(status: complete ? '已完成' : '部分完成');
    _replaceAsset(currentAsset);
    return currentAsset;
  }

  int _resolveAssetGenerationConcurrency(int assetCount) {
    if (assetCount <= 1) return 1;
    if (assetCount >= _maxAssetGenerationConcurrency) {
      return _maxAssetGenerationConcurrency;
    }
    return assetCount;
  }

  Future<void> _generateAsset(String assetId, {String? onlyViewName}) async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);
    try {
      final generatedAsset = await _generateAssetPipeline(
        assetId,
        onlyViewName: onlyViewName,
      );
      if (generatedAsset == null) return;
      final syncedAsset = await _upsertGlobalAsset(generatedAsset);
      _replaceAsset(syncedAsset);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateSelectedAssets() async {
    if (_isGenerating) return;
    final selected = _assets.where((asset) => asset.selected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先勾选要生成的资产')));
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final assetIds = selected.map((asset) => asset.id).toList();
      var nextIndex = 0;
      final concurrency = _resolveAssetGenerationConcurrency(assetIds.length);

      Future<void> runWorker() async {
        while (true) {
          final index = nextIndex;
          nextIndex += 1;
          if (index >= assetIds.length) return;
          await _generateAssetPipeline(assetIds[index]);
        }
      }

      await Future.wait(List.generate(concurrency, (_) => runWorker()));

      for (final assetId in assetIds) {
        final asset = _assetById(assetId);
        if (asset == null) continue;
        final syncedAsset = await _upsertGlobalAsset(asset);
        _replaceAsset(syncedAsset);
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _editAsset(FilmSceneAsset asset) async {
    final nameController = TextEditingController(text: asset.name);
    final descriptionController = TextEditingController(
      text: asset.description,
    );
    final result = await showDialog<FilmSceneAsset>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('编辑资产元素', style: TextStyle(color: AppColors.text)),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: '元素名称',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                minLines: 5,
                maxLines: 8,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: '视觉描述',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  alignLabelWithHint: true,
                ),
              ),
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
              Navigator.pop(
                context,
                asset.copyWith(
                  name: nameController.text.trim().isEmpty
                      ? asset.name
                      : nameController.text.trim(),
                  description: descriptionController.text.trim(),
                ),
              );
            },
            child: const Text('保存', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    if (result != null) _replaceAsset(result);
  }

  void _showImagePreview(
    File file, {
    List<File>? allImages,
    int initialIndex = 0,
  }) {
    showDialog(
      context: context,
      builder: (context) => _FullScreenImagePreview(
        images: allImages == null || allImages.isEmpty ? [file] : allImages,
        initialIndex: initialIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('生成资产图', style: TextStyle(color: AppColors.text)),
      content: SizedBox(
        width: 980,
        height: 680,
        child: Column(
          children: [
            _buildImageParamsToolbar(),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: '生成资产图'),
                Tab(text: '本场所有资产'),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildGenerationTab(), _buildSceneAssetsTab()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }

  Widget _buildGenerationTab() {
    return Column(
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isExtracting || _isGenerating ? null : _extractAssets,
              icon: const Icon(
                Icons.auto_awesome,
                size: 16,
                color: Colors.white,
              ),
              label: Text(_isExtracting ? '提取中...' : 'AI提取资产'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isExtracting || _isGenerating
                  ? null
                  : _generateSelectedAssets,
              icon: const Icon(Icons.image, size: 16, color: Colors.white),
              label: Text(_isGenerating ? '生成中...' : '生成勾选资产'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF424242),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '共 ${_assets.length} 个资产，已勾选 ${_assets.where((a) => a.selected).length} 个',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (_isExtracting || _extractLog.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            height: 74,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border2),
            ),
            child: SingleChildScrollView(
              child: Text(
                _extractLog.trim().isEmpty ? '正在分析当前分镜...' : _extractLog,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _assets.isEmpty
              ? const Center(
                  child: Text(
                    '暂无资产元素，点击 AI提取资产',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: _assets.length,
                  itemBuilder: (context, index) =>
                      _buildAssetGenerationCard(_assets[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildAssetGenerationCard(FilmSceneAsset asset) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: asset.selected,
                activeColor: AppColors.primary,
                onChanged: _isGenerating
                    ? null
                    : (value) => _replaceAsset(
                        asset.copyWith(selected: value ?? true),
                      ),
              ),
              Expanded(
                child: Text(
                  '${asset.name} · ${_categoryLabel(asset.category)}',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                asset.status,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              IconButton(
                tooltip: '编辑',
                onPressed: _isGenerating ? null : () => _editAsset(asset),
                icon: const Icon(
                  Icons.edit,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
              TextButton(
                onPressed: _isGenerating
                    ? null
                    : () => _generateAsset(asset.id),
                child: const Text(
                  '重新生成',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
          if (asset.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, bottom: 10),
              child: Text(
                asset.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _viewsForAsset(
                asset,
              ).map((view) => _buildViewTile(asset, view)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTile(FilmSceneAsset asset, FilmSceneAssetView view) {
    final imagePath = asset.viewImages[view.name] ?? '';
    final status = asset.viewStatus[view.name] ?? '待生成';
    final file = imagePath.isEmpty ? null : File(imagePath);
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          GestureDetector(
            onTap: file == null || !file.existsSync()
                ? null
                : () => _showImagePreview(file),
            child: Container(
              width: 104,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.sidebar,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: status == '失败' ? Colors.redAccent : AppColors.border2,
                ),
              ),
              child: file != null && file.existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        cacheWidth: 180,
                      ),
                    )
                  : Center(
                      child: status == '生成中'
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.image_outlined,
                              color: AppColors.textSecondary,
                            ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            view.name,
            style: const TextStyle(color: AppColors.text, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    color: status == '失败'
                        ? Colors.redAccent
                        : AppColors.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: _isGenerating
                    ? null
                    : () => _generateAsset(asset.id, onlyViewName: view.name),
                child: const Icon(
                  Icons.refresh,
                  color: AppColors.primary,
                  size: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSceneAssetsTab() {
    final visibleAssets = _assets
        .where(
          (asset) => asset.viewImages.values.any((path) => path.isNotEmpty),
        )
        .toList();
    if (visibleAssets.isEmpty) {
      return const Center(
        child: Text('暂无本场资产', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: visibleAssets.length,
      itemBuilder: (context, index) {
        final asset = visibleAssets[index];
        final files = FilmSceneAssetViews.all
            .map((view) => asset.viewImages[view.name] ?? '')
            .where((path) => path.isNotEmpty && File(path).existsSync())
            .map((path) => File(path))
            .toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${asset.name} · ${_categoryLabel(asset.category)}',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isGenerating
                        ? null
                        : () => _generateAsset(asset.id),
                    child: Text(
                      asset.category == 'Scene' ? '重生成场景图' : '重生成6视图',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: FilmSceneAssetViews.all.map((view) {
                  final imagePath = asset.viewImages[view.name] ?? '';
                  final file = imagePath.isEmpty ? null : File(imagePath);
                  final index = file == null
                      ? 0
                      : files.indexWhere((f) => f.path == file.path);
                  return SizedBox(
                    width: 132,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: file == null || !file.existsSync()
                              ? null
                              : () => _showImagePreview(
                                  file,
                                  allImages: files,
                                  initialIndex: index < 0 ? 0 : index,
                                ),
                          child: Container(
                            width: 132,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.sidebar,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border2),
                            ),
                            child: file != null && file.existsSync()
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                      cacheWidth: 220,
                                    ),
                                  )
                                : const Icon(
                                    Icons.image_not_supported,
                                    color: AppColors.textSecondary,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${asset.name}-${view.name}',
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GeneratedImagesDialog extends StatefulWidget {
  final String projectName;
  final Map<int, String?> currentShotImages;
  final Function(int) onDeleteCurrent;

  const _GeneratedImagesDialog({
    required this.projectName,
    required this.currentShotImages,
    required this.onDeleteCurrent,
  });

  @override
  State<_GeneratedImagesDialog> createState() => _GeneratedImagesDialogState();
}

class _GeneratedImagesDialogState extends State<_GeneratedImagesDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<FileSystemEntity> _historyFiles = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoadingHistory = true);
    try {
      final appDir = File(Platform.resolvedExecutable).parent;
      final projectDir = Directory(
        path.join(appDir.path, 'data', '分镜图', '${widget.projectName}-分镜图'),
      );

      if (await projectDir.exists()) {
        final List<FileSystemEntity> allFiles = [];
        await for (final entity in projectDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            final ext = path.extension(entity.path).toLowerCase();
            if (ext == '.png' ||
                ext == '.jpg' ||
                ext == '.jpeg' ||
                ext == '.webp') {
              allFiles.add(entity);
            }
          }
        }
        // 按时间倒序排序
        allFiles.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

        if (mounted) {
          setState(() {
            _historyFiles = allFiles;
            _isLoadingHistory = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingHistory = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('分镜头图片管理', style: TextStyle(color: AppColors.text)),
      content: SizedBox(
        width: 800,
        height: 600,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: '当前使用'),
                Tab(text: '所有历史图片'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildCurrentImages(), _buildHistoryImages()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }

  Widget _buildCurrentImages() {
    final imageEntries = widget.currentShotImages.entries
        .where((e) => e.value != null)
        .toList();

    if (imageEntries.isEmpty) {
      return const Center(
        child: Text(
          '当前暂无关联图片',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    final allImages = imageEntries.map((e) => File(e.value!)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text(
                '共 ${imageEntries.length} 张图片',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.download,
                  color: AppColors.primary,
                  size: 20,
                ),
                onPressed: () async {
                  final result = await FilePicker.platform.getDirectoryPath();
                  if (result != null) {
                    for (var entry in imageEntries) {
                      final file = File(entry.value!);
                      final fileName = path.basename(file.path);
                      await file.copy(path.join(result, fileName));
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '已保存 ${imageEntries.length} 张图片到 $result',
                          ),
                        ),
                      );
                    }
                  }
                },
                tooltip: '下载全部',
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            itemCount: imageEntries.length,
            itemBuilder: (context, index) {
              final shotIndex = imageEntries[index].key;
              final imagePath = imageEntries[index].value!;

              return GestureDetector(
                onTap: () => _showImagePreview(
                  File(imagePath),
                  allImages: allImages,
                  initialIndex: index,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          cacheWidth: 200,
                          File(imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.broken_image,
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '镜头${shotIndex + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: AppColors.sidebar,
                                title: const Text(
                                  '移除图片',
                                  style: TextStyle(color: AppColors.text),
                                ),
                                content: const Text(
                                  '仅从当前镜头中移除引用，不删除物理文件。',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text(
                                      '取消',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      widget.onDeleteCurrent(shotIndex);
                                      Navigator.pop(context);
                                      setState(() {});
                                    },
                                    child: const Text(
                                      '确定',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryImages() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_historyFiles.isEmpty) {
      return const Center(
        child: Text('暂无历史图片', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    // Group files by batch (folder name)
    final Map<String, List<File>> groupedFiles = {};
    for (var entity in _historyFiles) {
      if (entity is File) {
        final parentDir = entity.parent.path;
        final batchName = path.basename(parentDir);
        if (!groupedFiles.containsKey(batchName)) {
          groupedFiles[batchName] = [];
        }
        groupedFiles[batchName]!.add(entity);
      }
    }

    // Sort batches by name (assuming timestamp or number in name)
    final sortedBatches = groupedFiles.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedBatches.length,
      itemBuilder: (context, batchIndex) {
        final batchName = sortedBatches[batchIndex];
        final files = groupedFiles[batchName]!;
        // Sort files by name
        files.sort(
          (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Text(
                    batchName,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.folder_open,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    onPressed: () {
                      // Open folder
                      final dir = files.first.parent.path;
                      Process.run('explorer', [dir]);
                    },
                    tooltip: '打开文件夹',
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.download,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    onPressed: () async {
                      final result = await FilePicker.platform
                          .getDirectoryPath();
                      if (result != null) {
                        for (var file in files) {
                          final fileName = path.basename(file.path);
                          final destPath = path.join(result, fileName);
                          await file.copy(destPath);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已保存 ${files.length} 张图片到 $result'),
                            ),
                          );
                        }
                      }
                    },
                    tooltip: '下载本批次图片',
                  ),
                ],
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];

                return GestureDetector(
                  onTap: () => _showImagePreview(
                    file,
                    allImages: files,
                    initialIndex: index,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.border2),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            cacheWidth: 200,
                            file,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image,
                                  color: AppColors.textSecondary,
                                ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _deletePhysicalFile(file),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            color: Colors.black54,
                            child: Text(
                              path.basename(file.path),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.border1),
          ],
        );
      },
    );
  }

  void _showImagePreview(
    File file, {
    List<File>? allImages,
    int initialIndex = 0,
  }) {
    if (allImages == null || allImages.isEmpty) {
      allImages = [file];
      initialIndex = 0;
    }

    showDialog(
      context: context,
      builder: (context) => _FullScreenImagePreview(
        images: allImages!,
        initialIndex: initialIndex,
      ),
    );
  }

  Future<void> _deletePhysicalFile(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('永久删除', style: TextStyle(color: AppColors.text)),
        content: const Text(
          '确定要从磁盘永久删除这张图片吗？',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await file.delete();
        _loadHistory();
      } catch (e) {
        // ignore error
      }
    }
  }
}

class _MatchingProgressDialog extends ConsumerStatefulWidget {
  final FilmWorkshopService service;
  final String apiUrl;
  final String apiKey;
  final String model;
  final String visionApiUrl;
  final String visionApiKey;
  final String visionModel;
  final List<Shot> shots;
  final List<int>? originalIndices;
  final List<FilmReferenceImageAnalysis> referenceImages;
  final String fullScript;
  final Function(List<List<int>>, {List<int>? originalIndices}) onComplete;

  const _MatchingProgressDialog({
    required this.service,
    required this.apiUrl,
    required this.apiKey,
    required this.model,
    required this.visionApiUrl,
    required this.visionApiKey,
    required this.visionModel,
    required this.shots,
    this.originalIndices,
    required this.referenceImages,
    required this.fullScript,
    required this.onComplete,
  });

  @override
  ConsumerState<_MatchingProgressDialog> createState() =>
      _MatchingProgressDialogState();
}

class _MatchingProgressDialogState
    extends ConsumerState<_MatchingProgressDialog> {
  int _currentIndex = 0;
  String _currentThinking = '';
  final List<List<int>> _results = [];
  final ScrollController _scrollController = ScrollController();
  bool _minimized = false;
  String? _bgTaskId;
  String _stageLabel = '准备解析参考图';
  String _currentSubject = '';

  @override
  void initState() {
    super.initState();
    // 初始化Provider状态
    final taskId = 'match_${DateTime.now().millisecondsSinceEpoch}';
    _bgTaskId = taskId;
    ref
        .read(matchingTaskProvider.notifier)
        .startTask(
          taskId: taskId,
          totalShots: widget.shots.length,
          shots: widget.shots,
          originalIndices: widget.originalIndices,
        );
    _startMatching();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _minimizeToBackground() {
    // 添加后台任务（如果还没有）
    final tasks = ref.read(backgroundTaskProvider);
    if (!tasks.any((t) => t.id == _bgTaskId)) {
      ref
          .read(backgroundTaskProvider.notifier)
          .addTask(
            BackgroundTask(
              id: _bgTaskId!,
              title: '匹配资产到分镜头',
              description: '${_currentIndex + 1}/${widget.shots.length}',
              progress: _currentIndex / widget.shots.length,
              targetPageIndex: 1, // 影视工坊页面索引
            ),
          );
    }
    ref.read(matchingTaskProvider.notifier).minimize();
    setState(() => _minimized = true);
    Navigator.pop(context);
  }

  Future<void> _startMatching() async {
    final analyzedReferences = await _analyzeReferenceImages();
    final imageDescriptions = analyzedReferences
        .map((item) => item.matchDescription)
        .toList();

    for (int i = 0; i < widget.shots.length; i++) {
      if (mounted) {
        setState(() {
          _currentIndex = i;
          _currentThinking = '';
          _stageLabel = '匹配镜头';
          _currentSubject =
              '当前镜头: ${widget.shots[i].shotNumber}. ${widget.shots[i].shotName}';
        });
      }

      // 同步更新Provider状态（无论是否最小化都更新）
      ref.read(matchingTaskProvider.notifier).updateProgress(i, '');

      // 更新后台任务进度
      if (_bgTaskId != null) {
        final tasks = ref.read(backgroundTaskProvider);
        if (tasks.any((t) => t.id == _bgTaskId)) {
          ref
              .read(backgroundTaskProvider.notifier)
              .updateTask(
                _bgTaskId!,
                description: '正在匹配 ${i + 1}/${widget.shots.length}',
                progress: i / widget.shots.length,
              );
        }
      }

      final shot = widget.shots[i];
      final buffer = StringBuffer();

      await for (final chunk in widget.service.aiMatchImagesByRemarkStream(
        apiUrl: widget.apiUrl,
        apiKey: widget.apiKey,
        model: widget.model,
        prompt: shot.prompt,
        imageRemarks: imageDescriptions,
        shotType: shot.shotType,
        sceneDescription: shot.sceneDescription,
        fullScript: widget.fullScript,
        scriptAnalysis: '',
      )) {
        buffer.write(chunk);
        // 始终更新Provider（后台恢复对话框需要读取）
        ref
            .read(matchingTaskProvider.notifier)
            .updateThinking(buffer.toString());
        if (mounted && !_minimized) {
          setState(() => _currentThinking = buffer.toString());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          });
        }
      }

      final indexes = await widget.service.parseMatchResult(buffer.toString());
      _results.add(indexes);
    }

    // 完成
    ref.read(matchingTaskProvider.notifier).complete();
    if (_bgTaskId != null) {
      ref
          .read(backgroundTaskProvider.notifier)
          .updateTask(
            _bgTaskId!,
            description: '匹配完成',
            progress: 1.0,
            isComplete: true,
          );
    }

    widget.onComplete(_results, originalIndices: widget.originalIndices);
    // 如果对话框还在显示，关闭它
    if (mounted && !_minimized) {
      Navigator.pop(context);
    }
  }

  Future<List<FilmReferenceImageAnalysis>> _analyzeReferenceImages() async {
    final analyzed = <FilmReferenceImageAnalysis>[];
    final log = StringBuffer();
    for (int i = 0; i < widget.referenceImages.length; i++) {
      final referenceImage = widget.referenceImages[i];
      final subject =
          '参考图 ${i + 1}/${widget.referenceImages.length}: ${referenceImage.effectiveName}';

      if (mounted) {
        setState(() {
          _stageLabel = '解析参考图';
          _currentSubject = subject;
          _currentThinking = '${log.toString()}正在解析 $subject ...';
        });
      }
      ref
          .read(matchingTaskProvider.notifier)
          .updateThinking('${log.toString()}正在解析 $subject ...');

      if (_bgTaskId != null) {
        final tasks = ref.read(backgroundTaskProvider);
        if (tasks.any((t) => t.id == _bgTaskId)) {
          ref
              .read(backgroundTaskProvider.notifier)
              .updateTask(
                _bgTaskId!,
                description: '解析参考图 ${i + 1}/${widget.referenceImages.length}',
                progress: i / widget.referenceImages.length,
              );
        }
      }

      try {
        final result = await widget.service.analyzeReferenceImage(
          apiUrl: widget.visionApiUrl,
          apiKey: widget.visionApiKey,
          model: widget.visionModel,
          referenceImage: referenceImage,
        );
        analyzed.add(result);
        log.writeln('已解析 $subject');
      } catch (e) {
        analyzed.add(
          referenceImage.copyWith(
            visualDescription: '视觉模型解析失败：$e。请主要依据名称/备注、文件名和资产说明进行保守匹配。',
          ),
        );
        log.writeln('解析失败 $subject：$e');
      }

      if (mounted) {
        setState(() => _currentThinking = log.toString());
      }
      ref.read(matchingTaskProvider.notifier).updateThinking(log.toString());
    }
    return analyzed;
  }

  @override
  Widget build(BuildContext context) {
    final title = _stageLabel == '匹配镜头'
        ? '匹配资产到分镜头 (${_currentIndex + 1}/${widget.shots.length})'
        : _stageLabel;

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(color: AppColors.text)),
          ),
          IconButton(
            onPressed: _minimizeToBackground,
            icon: const Icon(
              Icons.minimize,
              color: AppColors.textSecondary,
              size: 20,
            ),
            tooltip: '最小化到后台',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3a3a3a),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentSubject.isEmpty ? '准备解析参考图' : _currentSubject,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: AppColors.border1),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border2),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _currentThinking.isEmpty ? '正在分析...' : _currentThinking,
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 恢复的匹配进度对话框 — 从Provider读取实时状态
class _MatchingProgressRestoredDialog extends ConsumerStatefulWidget {
  const _MatchingProgressRestoredDialog();

  @override
  ConsumerState<_MatchingProgressRestoredDialog> createState() =>
      _MatchingProgressRestoredDialogState();
}

class _MatchingProgressRestoredDialogState
    extends ConsumerState<_MatchingProgressRestoredDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _minimizeAgain() {
    ref.read(matchingTaskProvider.notifier).minimize();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final matchState = ref.watch(matchingTaskProvider);
    if (matchState == null) {
      // 任务已完成或清除
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    // 自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });

    final currentShot = matchState.currentIndex < matchState.shots.length
        ? matchState.shots[matchState.currentIndex]
        : null;

    // 任务已完成时自动关闭
    if (!matchState.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: Row(
        children: [
          Expanded(
            child: Text(
              '匹配资产到分镜头 (${matchState.currentIndex + 1}/${matchState.totalShots})',
              style: const TextStyle(color: AppColors.text),
            ),
          ),
          IconButton(
            onPressed: _minimizeAgain,
            icon: const Icon(
              Icons.minimize,
              color: AppColors.textSecondary,
              size: 20,
            ),
            tooltip: '最小化到后台',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF3a3a3a),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentShot != null)
              Text(
                '当前镜头: ${currentShot.shotNumber}. ${currentShot.shotName}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 8),
            const Divider(color: AppColors.border1),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border2),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    matchState.currentThinking.isEmpty
                        ? '正在分析...'
                        : matchState.currentThinking,
                    style: const TextStyle(color: AppColors.text, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 资产选择弹窗（支持多视图展开）
class _AssetSelectionWithViewsDialog extends ConsumerStatefulWidget {
  final int slotIndex;
  final void Function(String imagePath, String remark, {String? assetId})
  onSelect;

  const _AssetSelectionWithViewsDialog({
    required this.slotIndex,
    required this.onSelect,
  });

  @override
  ConsumerState<_AssetSelectionWithViewsDialog> createState() =>
      _AssetSelectionWithViewsDialogState();
}

class _AssetSelectionWithViewsDialogState
    extends ConsumerState<_AssetSelectionWithViewsDialog> {
  String? _expandedAssetId; // 当前展开预览的资产ID

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetProvider);

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: Row(
        children: [
          const Text('选择资产', style: TextStyle(color: AppColors.text)),
          const Spacer(),
          if (_expandedAssetId != null)
            TextButton.icon(
              icon: const Icon(
                Icons.arrow_back,
                size: 16,
                color: AppColors.textSecondary,
              ),
              label: const Text(
                '返回列表',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onPressed: () => setState(() => _expandedAssetId = null),
            ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 450,
        child: assets.isEmpty
            ? const Center(
                child: Text(
                  '暂无预设资产，请先到资产库添加',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            : _expandedAssetId != null
            ? _buildMultiViewPreview(
                assets.firstWhere(
                  (a) => a.id == _expandedAssetId,
                  orElse: () => assets.first,
                ),
              )
            : _buildAssetGrid(assets),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            '取消',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  /// 资产网格列表
  Widget _buildAssetGrid(List<Asset> assets) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: assets.length,
      itemBuilder: (context, idx) {
        final asset = assets[idx];
        final hasMultiViews = asset.images.isNotEmpty;
        return InkWell(
          onTap: () {
            // 直接将整个资产绑定到槽位，主图做缩略图
            widget.onSelect(asset.imagePath, asset.name, assetId: asset.id);
            Navigator.pop(context);
          },
          onLongPress: hasMultiViews
              ? () {
                  // 长按预览多视图
                  setState(() => _expandedAssetId = asset.id);
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasMultiViews
                    ? AppColors.primary.withOpacity(0.5)
                    : AppColors.border2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                        child: Image.file(
                          File(asset.imagePath),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          cacheWidth: 200,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey,
                            child: const Icon(Icons.error),
                          ),
                        ),
                      ),
                      if (hasMultiViews)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${asset.images.length + 1}张',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      Text(
                        asset.name,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      if (hasMultiViews)
                        const Text(
                          '点击选择 · 长按预览',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 多视图预览面板（只读预览，不选择单张）
  Widget _buildMultiViewPreview(Asset asset) {
    final allImages = asset.allImages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Icon(Icons.collections, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '${asset.name} - 多视图预览 (${allImages.length}张)',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16, color: Colors.white),
                label: const Text(
                  '选择此资产',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  widget.onSelect(
                    asset.imagePath,
                    asset.name,
                    assetId: asset.id,
                  );
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '匹配时AI将自动从以下视图中选择最合适的图片',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.7,
            ),
            itemCount: allImages.length,
            itemBuilder: (context, idx) {
              final img = allImages[idx];
              final isMain = idx == 0;
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.inputBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isMain ? AppColors.primary : AppColors.border2,
                    width: isMain ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                            ),
                            child: Image.file(
                              File(img.path),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              cacheWidth: 200,
                              errorBuilder: (_, __, ___) => Container(
                                color: Colors.grey,
                                child: const Icon(Icons.error),
                              ),
                            ),
                          ),
                          if (isMain)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '主图',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        img.name.isNotEmpty
                            ? img.name
                            : (isMain ? asset.name : '未命名'),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

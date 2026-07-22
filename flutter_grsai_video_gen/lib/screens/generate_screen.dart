import 'dart:io';
import 'dart:async';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import '../constants/app_colors.dart';
import '../providers/image_provider.dart';
import '../providers/session_provider.dart';
import '../providers/api_config_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/credits_provider.dart';
import '../providers/model_status_provider.dart';
import '../providers/generate_provider.dart';
import '../providers/favorite_provider.dart';
import '../providers/video_gallery_provider.dart';
import '../providers/video_config_provider.dart';
import '../providers/video_task_provider.dart';
import '../widgets/session_history_dialog.dart';
import '../widgets/session_gallery_dialog.dart';
import '../widgets/polish_prompt_dialog.dart';
import '../widgets/image_viewer_dialog.dart';
import '../widgets/image_with_hover.dart';
import '../widgets/repaint_editor.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/uploaded_image.dart';
import '../models/favorite_image.dart';
import '../models/video_item.dart';
import '../models/video_generate_params.dart';
import '../services/config_file_service.dart';
import '../services/file_service.dart';
import '../services/generate_logic_service.dart';
import '../services/storyboard_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../providers/generate_params_provider.dart';
import '../providers/ai_assistant_provider.dart';
import '../models/ai_assistant_message.dart';
import '../utils/gpt_image_generation_preset.dart';
import '../utils/prompt_text_insertion.dart';
import '../utils/reference_image_file_name.dart';
import '../utils/z_image_base_generation_preset.dart';
import '../widgets/ai_assistant_bubble.dart';
import '../widgets/ai_creator_input_bar.dart';
import '../widgets/ai_skill_save_dialog.dart';
import '../widgets/skill_library_dialog.dart';
import '../widgets/video_player_widget.dart';

class GenerateScreen extends ConsumerStatefulWidget {
  final TextEditingController? promptController;
  final bool dropEnabled;

  const GenerateScreen({
    super.key,
    this.promptController,
    this.dropEnabled = true,
  });

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  static const Map<String, String> _imageModelLabels = {
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

  static const List<String> _imageModelItems = [
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
  static const List<String> _defaultAspectRatioItems = [
    'auto',
    '1:1',
    '16:9',
    '9:16',
    '4:5',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];
  static const List<String> _defaultImageSizeItems = ['1K', '2K', '4K'];

  late final TextEditingController _promptController;
  final _zImageSampleStepsController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  String _selectedModel = 'nano-banana-fast';
  String _aspectRatio = 'auto';
  String _imageSize = '1K';
  String _imageQuality = 'auto';
  int _zImageBaseSampleSteps = 30;
  int _batchCount = 1;
  OverlayEntry? _overlayEntry;
  OverlayEntry? _messageMenuEntry;
  OverlayEntry? _favoriteToast;
  ProviderSubscription<Session?>? _sessionSubscription;
  int _selectedImageIndex = 0;
  final GlobalKey _textFieldKey = GlobalKey();

  /// 多角度：从编辑器"返回输入"时暂存的角度 prompt 和原图路径
  String? _pendingAnglePrompt;
  String? _pendingAngleImagePath;
  bool _isEditingSessionName = false;
  final _sessionNameController = TextEditingController();
  final _sessionNameFocusNode = FocusNode();

  bool _showScrollToBottom = false;
  bool _pendingAutoScrollToBottom = false;
  bool _pendingAutoScrollSmooth = false;
  // AI模式状态由provider持久化管理，不再使用局部变量
  List<String> _promptHistory = [];
  bool _isMiddleButtonPressed = false;
  Offset? _middleButtonPressPosition;
  double _bubbleScale = 1.0; // 气泡缩放因子 0.5~2.0
  DateTime? _lastSubmitTime;
  String? _lastRequestFingerprint;
  String? _lastAutoExecutedAiMessageId;
  bool _isAutoExecutingAiPlan = false;

  bool get _isZImageBaseSelected =>
      ZImageBaseGenerationPreset.isModel(_selectedModel);

  List<String> get _activeAspectRatioItems => _isZImageBaseSelected
      ? ZImageBaseGenerationPreset.aspectRatios
      : GptImageGenerationPreset.isModel(_selectedModel)
      ? GptImageGenerationPreset.getAspectRatioOptions(_selectedModel)
      : _defaultAspectRatioItems;

  List<String> get _activeImageSizeItems =>
      GptImageGenerationPreset.usesResolutionDropdown(_selectedModel)
      ? GptImageGenerationPreset.getImageSizeOptions(
          _selectedModel,
          _aspectRatio,
        )
      : _defaultImageSizeItems;

  Map<String, String>? get _activeImageSizeLabels => _isZImageBaseSelected
      ? ZImageBaseGenerationPreset.imageSizeLabels
      : GptImageGenerationPreset.usesResolutionDropdown(_selectedModel)
      ? GptImageGenerationPreset.getResolutionLabels(
          _selectedModel,
          _aspectRatio,
        )
      : null;

  bool get _showImageQualitySelect =>
      GptImageGenerationPreset.supportsQuality(_selectedModel);

  @override
  void initState() {
    super.initState();
    _promptController = widget.promptController ?? TextEditingController();
    _loadGenerateParams();
    _loadPromptHistory();
    _promptController.addListener(_onTextChanged);
    _scrollController.addListener(_onScroll);
    _sessionSubscription = ref.listenManual<Session?>(currentSessionProvider, (
      previous,
      next,
    ) {
      if (!mounted || next == null || next.messages.isEmpty) return;

      final previousMessages = previous?.messages ?? const <Message>[];
      final nextMessages = next.messages;
      final countChanged = previousMessages.length != nextMessages.length;
      final previousLast = previousMessages.isNotEmpty
          ? previousMessages.last
          : null;
      final nextLast = nextMessages.last;
      final lastMessageChanged =
          previousLast?.id == nextLast.id &&
          (previousLast?.text != nextLast.text ||
              previousLast?.images.length != nextLast.images.length ||
              previousLast?.videos.length != nextLast.videos.length);

      if (!countChanged && !lastMessageChanged) return;
      if (!_pendingAutoScrollToBottom || !countChanged) return;

      final smooth = _pendingAutoScrollSmooth;
      _pendingAutoScrollToBottom = false;
      _pendingAutoScrollSmooth = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) {
            _scrollToBottom(smooth: smooth);
          }
        });
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentSessionProvider.notifier).loadLastSession();
      ref.read(creditsProvider.notifier).fetchCredits();
      _checkAllModelsStatus();
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      setState(() {
        _showScrollToBottom = maxScroll - currentScroll > 200;
      });
    }
  }

  void _scrollToBottom({bool smooth = true}) {
    if (_scrollController.hasClients) {
      if (smooth) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  void _requestScrollToBottomOnNextSessionInsert({bool smooth = false}) {
    _pendingAutoScrollToBottom = true;
    _pendingAutoScrollSmooth = smooth;
  }

  bool _isBubbleZoomModifierPressed() {
    final pressedKeys = HardwareKeyboard.instance.logicalKeysPressed;
    return pressedKeys.contains(LogicalKeyboardKey.controlLeft) ||
        pressedKeys.contains(LogicalKeyboardKey.controlRight);
  }

  void _handleBubbleScalePointerSignal(PointerScrollEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolvedEvent,
    ) {
      final scrollEvent = resolvedEvent as PointerScrollEvent;
      final nextScale =
          (scrollEvent.scrollDelta.dy < 0
                  ? _bubbleScale + 0.05
                  : _bubbleScale - 0.05)
              .clamp(0.5, 2.0)
              .toDouble();
      if (nextScale == _bubbleScale) {
        return;
      }
      setState(() {
        _bubbleScale = nextScale;
      });
    });
  }

  void _scheduleScrollToBottom({bool smooth = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted) {
          _scrollToBottom(smooth: smooth);
        }
      });
    });
  }

  Future<void> _checkAllModelsStatus() async {
    final models = _imageModelItems.where((item) => item != 'divider').toList();
    await ref.read(modelStatusProvider.notifier).checkAllModels(models);
  }

  void _onTextChanged() {
    final text = _promptController.text;
    final cursorPos = _promptController.selection.baseOffset;
    if (cursorPos > 0 && text[cursorPos - 1] == '@') {
      _showImagePicker();
    } else {
      _hideImagePicker();
    }
  }

  void _showImagePicker() {
    _hideImagePicker();
    final images = ref.read(uploadedImagesProvider);
    if (images.isEmpty) return;

    setState(() {
      _selectedImageIndex = 0;
    });

    final renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final textFieldOffset = renderBox.localToGlobal(Offset.zero);
    final textFieldSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    double left = textFieldOffset.dx + 20;
    double top = textFieldOffset.dy + textFieldSize.height + 5;

    if (left + 400 > screenSize.width) {
      left = screenSize.width - 420;
    }
    if (top + 300 > screenSize.height) {
      top = textFieldOffset.dy - 305;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideImagePicker,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: KeyboardListener(
              focusNode: FocusNode()..requestFocus(),
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    setState(() {
                      _selectedImageIndex =
                          (_selectedImageIndex + 1) % images.length;
                    });
                    _overlayEntry?.markNeedsBuild();
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    setState(() {
                      _selectedImageIndex =
                          (_selectedImageIndex - 1 + images.length) %
                          images.length;
                    });
                    _overlayEntry?.markNeedsBuild();
                  } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                    _selectImage(images[_selectedImageIndex]);
                  } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                    _hideImagePicker();
                  }
                }
              },
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 400,
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: AppColors.sidebar,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final img = images[index];
                      final isSelected = index == _selectedImageIndex;
                      return InkWell(
                        onTap: () => _selectImage(img),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : null,
                            border: Border(
                              bottom: BorderSide(
                                color: AppColors.border2,
                                width: index < images.length - 1 ? 1 : 0,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.memory(
                                  img.bytes,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  img.name,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _selectImage(UploadedImage img) {
    ref.read(selectedImagesProvider.notifier).addImage(img);
    final text = _promptController.text;
    final cursorPos = _promptController.selection.baseOffset;
    _promptController.text =
        text.substring(0, cursorPos - 1) + text.substring(cursorPos);
    _promptController.selection = TextSelection.collapsed(
      offset: cursorPos - 1,
    );
    _hideImagePicker();
  }

  void _hideImagePicker() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _hideMessageMenu() {
    _messageMenuEntry?.remove();
    _messageMenuEntry = null;
  }

  Future<void> _loadPromptHistory() async {
    final configService = ConfigFileService();
    final history = await configService.loadPromptHistory();
    if (mounted) setState(() => _promptHistory = history);
  }

  Future<void> _savePromptToHistory(String prompt) async {
    final configService = ConfigFileService();
    await configService.addPromptHistory(prompt);
    await _loadPromptHistory();
  }

  Future<void> _loadGenerateParams() async {
    final configService = ConfigFileService();
    final params = await configService.loadGenerateParams();
    final normalized = _normalizeGenerateParamsValues(
      model: params['model']!,
      aspectRatio: params['aspectRatio']!,
      imageSize: params['imageSize']!,
      imageQuality: params['imageQuality'] as String? ?? 'auto',
      sampleSteps: (params['sampleSteps'] as num?)?.toInt(),
    );
    setState(() {
      _selectedModel = params['model']!;
      _aspectRatio = normalized['aspectRatio']!;
      _imageSize = normalized['imageSize']!;
      _imageQuality = normalized['imageQuality']! as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    });
    _syncZImageSampleStepsController();
    ref
        .read(generateParamsProvider.notifier)
        .setAll(
          _selectedModel,
          _aspectRatio,
          _imageSize,
          _imageQuality,
          _zImageBaseSampleSteps,
        );
    if (_aspectRatio != params['aspectRatio']! ||
        _imageSize != params['imageSize']! ||
        _imageQuality != (params['imageQuality'] as String? ?? 'auto') ||
        _zImageBaseSampleSteps != (params['sampleSteps'] as num?)?.toInt()) {
      unawaited(_saveGenerateParams());
    }
    unawaited(
      ref
          .read(apiConfigsProvider.notifier)
          .autoSwitchImageConfigForModel(_selectedModel),
    );
  }

  Future<void> _saveGenerateParams() async {
    final configService = ConfigFileService();
    await configService.saveGenerateParams(
      _selectedModel,
      _aspectRatio,
      _imageSize,
      _imageQuality,
      _zImageBaseSampleSteps,
    );
    ref
        .read(generateParamsProvider.notifier)
        .setAll(
          _selectedModel,
          _aspectRatio,
          _imageSize,
          _imageQuality,
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

  int _commitZImageBaseSampleSteps({bool showFeedback = false}) {
    final normalized = ZImageBaseGenerationPreset.parseSampleSteps(
      _zImageSampleStepsController.text,
      imageSize: _imageSize,
    );
    setState(() {
      _zImageBaseSampleSteps = normalized;
    });
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Z-Image步数已保存：${normalized}步')));
    }
    return normalized;
  }

  Map<String, dynamic> _normalizeGenerateParamsValues({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
    int? sampleSteps,
  }) {
    final normalizedQuality = GptImageGenerationPreset.normalizeQuality(
      imageQuality,
    );

    if (!ZImageBaseGenerationPreset.isModel(model)) {
      final isGptModel = GptImageGenerationPreset.isModel(model);
      final normalizedAspectRatio = isGptModel
          ? GptImageGenerationPreset.normalizeAspectRatio(aspectRatio)
          : _defaultAspectRatioItems.contains(aspectRatio)
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
        'imageQuality': normalizedQuality,
        'sampleSteps': ZImageBaseGenerationPreset.normalizeSampleSteps(
          sampleSteps,
          imageSize: normalizedImageSize,
        ),
      };
    }

    return {
      'aspectRatio': ZImageBaseGenerationPreset.normalizeAspectRatio(
        aspectRatio,
      ),
      'imageSize': ZImageBaseGenerationPreset.normalizeImageSize(imageSize),
      'imageQuality': normalizedQuality,
      'sampleSteps': ZImageBaseGenerationPreset.normalizeSampleSteps(
        sampleSteps,
        imageSize: imageSize,
      ),
    };
  }

  Widget _buildZImageBaseHint() {
    final resolution = ZImageBaseGenerationPreset.resolveResolution(
      _aspectRatio,
      _imageSize,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Z-Image 专用参数：$resolution | ${_zImageBaseSampleSteps}步 | CFG ${ZImageBaseGenerationPreset.guidanceScale.toStringAsFixed(0)} | Flow Shift ${ZImageBaseGenerationPreset.flowShift.toStringAsFixed(0)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildGptImageHint() {
    final ratioText = _aspectRatio == 'auto' ? '自动比例' : _aspectRatio;
    final sizeText =
        GptImageGenerationPreset.usesResolutionDropdown(_selectedModel)
        ? GptImageGenerationPreset.resolutionLabel(_imageSize)
        : _imageSize;
    final qualityText =
        GptImageGenerationPreset.qualityLabels[_imageQuality] ?? _imageQuality;
    final hint = GptImageGenerationPreset.isVipModel(_selectedModel)
        ? 'GPT-Image-2-VIP：分辨率会随比例联动，可直接选择高像素尺寸。'
        : 'GPT-Image-2：当前会按比例和分辨率档位自动换算请求尺寸。';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$hint 当前参数：$ratioText | $sizeText | $qualityText',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ),
    );
  }

  void _applyModelSelection(String model) {
    final wasZImageSelected = _isZImageBaseSelected;
    final previousImageSize = _imageSize;
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      previousImageSize,
    );
    final wasUsingDefaultSteps = _zImageBaseSampleSteps == previousDefaultSteps;
    final normalized = _normalizeGenerateParamsValues(
      model: model,
      aspectRatio: _aspectRatio,
      imageSize: _imageSize,
      imageQuality: _imageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );

    setState(() {
      _selectedModel = model;
      _aspectRatio = normalized['aspectRatio'] as String;
      _imageSize = normalized['imageSize'] as String;
      _imageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
      if (_isZImageBaseSelected &&
          (!wasZImageSelected || wasUsingDefaultSteps)) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          _imageSize,
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
  }

  void _applyImageSizeSelection(String imageSize) {
    final previousDefaultSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
      _imageSize,
    );
    final shouldFollowDefault =
        _zImageBaseSampleSteps == previousDefaultSteps ||
        _zImageBaseSampleSteps < ZImageBaseGenerationPreset.minSampleSteps;

    setState(() {
      _imageSize = imageSize;
      if (_isZImageBaseSelected && shouldFollowDefault) {
        _zImageBaseSampleSteps = ZImageBaseGenerationPreset.resolveSampleSteps(
          imageSize,
        );
      }
    });
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
  }

  void _applyAspectRatioSelection(String aspectRatio) {
    final normalized = _normalizeGenerateParamsValues(
      model: _selectedModel,
      aspectRatio: aspectRatio,
      imageSize: _imageSize,
      imageQuality: _imageQuality,
      sampleSteps: _zImageBaseSampleSteps,
    );

    setState(() {
      _aspectRatio = normalized['aspectRatio'] as String;
      _imageSize = normalized['imageSize'] as String;
      _imageQuality = normalized['imageQuality'] as String;
      _zImageBaseSampleSteps = normalized['sampleSteps'] as int;
    });
    _syncZImageSampleStepsController();
    unawaited(_saveGenerateParams());
  }

  void _applyImageQualitySelection(String imageQuality) {
    setState(() {
      _imageQuality = GptImageGenerationPreset.normalizeQuality(imageQuality);
    });
    unawaited(_saveGenerateParams());
  }

  int? _resolveSampleStepsForCurrentModel() {
    if (!_isZImageBaseSelected) {
      return null;
    }
    return _commitZImageBaseSampleSteps();
  }

  int? _resolveSampleStepsForModel(String model, String imageSize) {
    if (!ZImageBaseGenerationPreset.isModel(model)) {
      return null;
    }
    if (model == _selectedModel && imageSize == _imageSize) {
      return _commitZImageBaseSampleSteps();
    }
    return ZImageBaseGenerationPreset.normalizeSampleSteps(
      _zImageBaseSampleSteps,
      imageSize: imageSize,
    );
  }

  Widget _buildZImageSampleStepsInput() {
    return Container(
      width: 120,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        border: Border.all(color: AppColors.border2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Text(
            '步数',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _zImageSampleStepsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) =>
                  _commitZImageBaseSampleSteps(showFeedback: true),
              style: const TextStyle(color: AppColors.text, fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '30',
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyImageToClipboard(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前平台不支持图片复制')));
      return;
    }
    final item = DataWriterItem();
    item.add(Formats.png(bytes));
    await clipboard.write([item]);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已复制图片到剪贴板')));
  }

  Future<void> _copyTextToClipboard(
    String text, {
    String successMessage = '已复制',
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  String _resolvePrompt({Message? message, AiAssistantMessage? aiMessage}) {
    if (message != null) {
      return message.params?['prompt']?.toString() ?? message.text;
    }
    if (aiMessage != null) {
      return aiMessage.plan?['prompt']?.toString() ??
          aiMessage.polishedPrompt ??
          aiMessage.text ??
          '';
    }
    return '';
  }

  String _resolveAbsoluteImagePath(String imagePath) {
    if (imagePath.startsWith('data/')) {
      return '${FileService().getAppDirectory()}/$imagePath';
    }
    return imagePath;
  }

  void _insertTextAtPromptCursor(String text) {
    _promptController.value = insertTextAtSelection(
      value: _promptController.value,
      insertion: text,
    );
    _focusNode.requestFocus();
  }

  Future<String?> _addImageAsReferenceFromPath(
    String imagePath, {
    String Function(String originalFileName)? insertionBuilder,
    String successMessage = '已添加到参考图',
  }) async {
    final absolutePath = _resolveAbsoluteImagePath(imagePath);
    final file = File(absolutePath);
    if (!await file.exists()) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片文件不存在，无法设为参考')));
      return null;
    }
    final bytes = await file.readAsBytes();
    final fileService = FileService();
    final appDir = fileService.getAppDirectory();
    final inputDir = Directory('$appDir/data/input');
    await inputDir.create(recursive: true);

    final originalFileName = displayFileNameFromPath(absolutePath);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newFileName = buildReferenceCopyFileName(originalFileName, timestamp);
    final newPath = '${inputDir.path}/$newFileName';
    await File(newPath).writeAsBytes(bytes);

    final image = UploadedImage(
      id: const Uuid().v4(),
      name: newFileName,
      path: newPath,
      base64: base64Encode(bytes),
      bytes: bytes,
    );
    ref.read(uploadedImagesProvider.notifier).addImage(image);
    ref.read(selectedImagesProvider.notifier).addImage(image);
    if (ref.read(aiAssistantProvider).isActive) {
      ref.read(aiAssistantProvider.notifier).registerReferenceImage(image);
    }
    if (insertionBuilder != null) {
      _insertTextAtPromptCursor(insertionBuilder(originalFileName));
    }
    if (!mounted) return null;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
    return originalFileName;
  }

  Future<void> _setImageAsReference(String imagePath) async {
    await _addImageAsReferenceFromPath(
      imagePath,
      insertionBuilder: (fileName) => '根据 $fileName，生成一组连续的分镜图',
      successMessage: '已设为参考并插入输入框',
    );
  }

  Future<void> _continueEditFromImage(String imagePath) async {
    await _addImageAsReferenceFromPath(
      imagePath,
      insertionBuilder: (fileName) => '根据 $fileName，保持主体一致，继续修改：',
      successMessage: '已加入参考图，可继续描述修改方向',
    );
  }

  Future<void> _generateSimilarFromImage(String imagePath) async {
    final fileName = await _addImageAsReferenceFromPath(
      imagePath,
      successMessage: '已加入参考图并写入同风格续创需求',
    );
    if (fileName == null) return;
    setState(() => _batchCount = 4);
    _promptController.text = '根据 $fileName，保持主体、风格、构图和画面氛围一致，再生成 4 张变化方案';
    _promptController.selection = TextSelection.collapsed(
      offset: _promptController.text.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _sendPostGenerationIntent(String intent) async {
    final normalized = intent.trim();
    if (normalized.isEmpty) return;

    final notifier = ref.read(aiAssistantProvider.notifier);
    final aiState = ref.read(aiAssistantProvider);
    if (aiState.isProcessing || aiState.phase == AssistantPhase.generating) {
      return;
    }

    if (!aiState.isActive) {
      notifier.activateAssistant();
      for (final image in ref.read(selectedImagesProvider)) {
        notifier.registerReferenceImage(image);
      }
    }

    if (normalized.contains('4')) {
      setState(() => _batchCount = 4);
    }

    await notifier.sendMessage(normalized);
    _scheduleScrollToBottom();
    await _tryAutoExecutePendingPlan();
  }

  Future<void> _pickReferenceImagesFromInput() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;

    final fileService = FileService();
    final appDir = fileService.getAppDirectory();
    final inputDir = Directory('$appDir/data/input');
    await inputDir.create(recursive: true);

    for (final picked in result.files) {
      if (picked.path == null) continue;
      final sourceFile = File(picked.path!);
      if (!await sourceFile.exists()) continue;
      final bytes = await sourceFile.readAsBytes();
      final originalFileName = picked.path!.split(Platform.pathSeparator).last;
      final targetFileName = buildReferenceCopyFileName(
        originalFileName,
        DateTime.now().millisecondsSinceEpoch,
      );
      final targetPath = '${inputDir.path}/$targetFileName';
      await File(targetPath).writeAsBytes(bytes);
      final image = UploadedImage(
        id: const Uuid().v4(),
        name: targetFileName,
        path: targetPath,
        base64: base64Encode(bytes),
        bytes: bytes,
      );
      ref.read(uploadedImagesProvider.notifier).addImage(image);
      ref.read(selectedImagesProvider.notifier).addImage(image);
      if (ref.read(aiAssistantProvider).isActive) {
        ref.read(aiAssistantProvider.notifier).registerReferenceImage(image);
        await ref
            .read(aiAssistantProvider.notifier)
            .sendImage(
              image.base64,
              image.name,
              imagePath: image.path,
              imageId: image.id,
            );
      }
    }
  }

  Future<void> _favoriteImage(String imagePath, String prompt) async {
    final favorite = FavoriteImage(
      url: imagePath,
      prompt: prompt,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(favoritesProvider.notifier).addFavorite(favorite);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已收藏图片')));
  }

  Future<void> _favoriteVideo(String videoPath, {String? videoItemId}) async {
    VideoItem? item;
    final videos = ref.read(videoGalleryProvider);
    if (videoItemId != null && videoItemId.isNotEmpty) {
      item = videos.where((video) => video.id == videoItemId).firstOrNull;
    }
    item ??= videos.where((video) => video.localPath == videoPath).firstOrNull;
    if (item == null) return;
    final current = await ref
        .read(videoGalleryProvider.notifier)
        .toggleFavorite(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(current ? '已收藏视频' : '已取消收藏视频')));
  }

  Future<void> _downloadGeneratedFile(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) return;
    final ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : '';
    final savedPath = await FileService().saveGeneratedFileWithDialog(
      sourcePath,
      dialogTitle: '导出生成文件',
      allowedExtensions: ext.isEmpty ? null : [ext],
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存到: $savedPath')));
  }

  Future<void> _deleteSessionImage(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
    await ref
        .read(currentSessionProvider.notifier)
        .removeImageFromMessages(imagePath);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除图片')));
  }

  Future<void> _deleteAiImage(String messageId, String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
    ref
        .read(aiAssistantProvider.notifier)
        .removeImageFromMessage(messageId, imagePath);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除图片')));
  }

  Future<void> _deleteVideoMessage(
    String videoPath, {
    String? videoItemId,
  }) async {
    VideoItem? item;
    final videos = ref.read(videoGalleryProvider);
    if (videoItemId != null && videoItemId.isNotEmpty) {
      item = videos.where((video) => video.id == videoItemId).firstOrNull;
    }
    item ??= videos.where((video) => video.localPath == videoPath).firstOrNull;
    if (item != null) {
      await ref.read(videoGalleryProvider.notifier).deleteVideo(item.id);
    } else {
      final file = File(videoPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await ref
        .read(currentSessionProvider.notifier)
        .removeVideoFromMessages(videoPath);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除视频')));
  }

  void _showMessageContextMenu(Offset position, _ChatContextTarget target) {
    _hideMessageMenu();
    final overlay = Overlay.of(context);

    _messageMenuEntry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideMessageMenu,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: position.dx,
            top: position.dy,
            child: Material(
              elevation: 10,
              color: AppColors.sidebar,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(minWidth: 148),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (target.imagePath != null)
                      _buildContextMenuItem(
                        '设为参考',
                        Icons.add_photo_alternate,
                        () async {
                          _hideMessageMenu();
                          await _setImageAsReference(target.imagePath!);
                        },
                      ),
                    if (target.imagePath != null || target.videoPath != null)
                      _buildContextMenuItem(
                        '收藏',
                        Icons.favorite_border,
                        () async {
                          _hideMessageMenu();
                          if (target.imagePath != null) {
                            await _favoriteImage(
                              target.imagePath!,
                              _resolvePrompt(
                                message: target.message,
                                aiMessage: target.aiMessage,
                              ),
                            );
                          } else if (target.videoPath != null) {
                            await _favoriteVideo(
                              target.videoPath!,
                              videoItemId: target.videoItemId,
                            );
                          }
                        },
                      ),
                    if (target.imagePath != null || target.videoPath != null)
                      _buildContextMenuItem('下载', Icons.download, () async {
                        _hideMessageMenu();
                        await _downloadGeneratedFile(
                          target.imagePath ?? target.videoPath!,
                        );
                      }),
                    _buildContextMenuItem('删除', Icons.delete_outline, () async {
                      _hideMessageMenu();
                      if (target.imagePath != null) {
                        if (target.aiMessage != null) {
                          await _deleteAiImage(
                            target.aiMessage!.id,
                            target.imagePath!,
                          );
                        } else {
                          await _deleteSessionImage(target.imagePath!);
                        }
                        return;
                      }
                      if (target.videoPath != null) {
                        await _deleteVideoMessage(
                          target.videoPath!,
                          videoItemId: target.videoItemId,
                        );
                        return;
                      }
                      if (target.message != null) {
                        await ref
                            .read(currentSessionProvider.notifier)
                            .deleteMessageById(target.message!.id);
                      } else if (target.aiMessage != null) {
                        ref
                            .read(aiAssistantProvider.notifier)
                            .deleteMessage(target.aiMessage!.id);
                      }
                    }),
                    _buildContextMenuItem('复制', Icons.copy, () async {
                      _hideMessageMenu();
                      if (target.imagePath != null) {
                        await _copyImageToClipboard(target.imagePath!);
                        return;
                      }
                      if (target.videoPath != null) {
                        await _copyTextToClipboard(
                          target.videoPath!,
                          successMessage: '已复制视频文件路径',
                        );
                        return;
                      }
                      await _copyTextToClipboard(
                        target.message?.text ?? target.aiMessage?.text ?? '',
                        successMessage: '已复制文本',
                      );
                    }),
                    _buildContextMenuItem('复制提示词', Icons.text_fields, () async {
                      _hideMessageMenu();
                      await _copyTextToClipboard(
                        _resolvePrompt(
                          message: target.message,
                          aiMessage: target.aiMessage,
                        ),
                        successMessage: '已复制提示词',
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_messageMenuEntry!);
  }

  Widget _buildContextMenuItem(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.text, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _favoriteToast?.remove();
    _sessionSubscription?.close();
    _promptController.removeListener(_onTextChanged);
    _zImageSampleStepsController.dispose();
    if (widget.promptController == null) {
      _promptController.dispose();
    }
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _sessionNameController.dispose();
    _sessionNameFocusNode.dispose();
    _hideImagePicker();
    _hideMessageMenu();
    super.dispose();
  }

  /// 多角度"返回输入"：把角度 prompt 暂存，显示在输入框上方
  void _handleMultiAngleReturnToInput(String anglePrompt, String imagePath) {
    setState(() {
      _pendingAnglePrompt = anglePrompt;
      _pendingAngleImagePath = imagePath;
    });
    // 把角度 prompt 追加到输入框（如果输入框已有内容则换行追加）
    final existing = _promptController.text.trim();
    _promptController.text = existing.isEmpty
        ? anglePrompt
        : '$existing\n$anglePrompt';
    _promptController.selection = TextSelection.collapsed(
      offset: _promptController.text.length,
    );
    _focusNode.requestFocus();
  }

  Future<void> _handleMultiAngleGenerate(
    String anglePrompt,
    String imagePath, {
    Uint8List? croppedBytes,
  }) async {
    final configs = ref.read(apiConfigsProvider);
    if (configs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先配置API')));
      return;
    }

    // 将原图或裁切图转为 base64 作为参考图
    String base64Str;
    if (croppedBytes != null) {
      base64Str = base64Encode(croppedBytes);
    } else {
      final file = File(imagePath);
      if (!await file.exists()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('原图文件不存在')));
        return;
      }
      final bytes = await file.readAsBytes();
      base64Str = base64Encode(bytes);
    }

    _requestScrollToBottomOnNextSessionInsert();

    final sampleSteps = _resolveSampleStepsForCurrentModel();
    ref
        .read(generateLogicServiceProvider)
        .generate(
          prompt: anglePrompt,
          model: _selectedModel,
          aspectRatio: _aspectRatio,
          imageSize: _imageSize,
          imageQuality: _imageQuality,
          sampleSteps: sampleSteps,
          referenceImages: [base64Str],
          referenceImagePaths: [imagePath],
        );
  }

  Future<void> _handleGenerate() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入提示词')));
      return;
    }

    _savePromptToHistory(prompt);
    final fingerprint =
        '$prompt|$_selectedModel|$_aspectRatio|$_imageSize|$_imageQuality|$_zImageBaseSampleSteps|$_batchCount';
    final now = DateTime.now();
    if (_lastSubmitTime != null &&
        now.difference(_lastSubmitTime!) < const Duration(milliseconds: 1000) &&
        _lastRequestFingerprint == fingerprint) {
      return;
    }
    _lastSubmitTime = now;
    _lastRequestFingerprint = fingerprint;

    final configs = ref.read(apiConfigsProvider);
    if (configs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先配置API')));
      return;
    }

    final selectedImages = ref.read(selectedImagesProvider);
    final referenceImages = selectedImages.map((img) => img.base64).toList();
    final refImagePaths = selectedImages.map((img) => img.path).toList();

    _requestScrollToBottomOnNextSessionInsert();

    final currentModel = _selectedModel;
    final currentAspectRatio = _aspectRatio;
    final currentImageSize = _imageSize;
    final currentImageQuality = _imageQuality;
    final currentSampleSteps = _resolveSampleStepsForModel(
      currentModel,
      currentImageSize,
    );
    final batchCount = _batchCount;

    String actualPrompt = prompt;
    if (ref.read(aiAssistantProvider).isActive) {
      try {
        final chatConfigs = configs.where((c) => c.type == 'chat').toList();
        if (chatConfigs.isNotEmpty) {
          final claudeConfig = chatConfigs.firstWhere(
            (c) => c.isDefault,
            orElse: () => chatConfigs.first,
          );
          final apiService = ref.read(apiServiceProvider);
          final configService = ConfigFileService();
          final systemPrompt = await configService.loadPromptRule(
            'auto_polish_prompt',
          );
          actualPrompt = await apiService.autoPolishPrompt(
            apiUrl: claudeConfig.url,
            apiKey: claudeConfig.key,
            model: claudeConfig.model,
            prompt: prompt,
            systemPrompt: systemPrompt,
          );
        }
      } catch (e) {
        actualPrompt = prompt;
      }
    }

    if (batchCount > 1) {
      final chatConfigs = configs.where((c) => c.type == 'chat').toList();
      final claudeConfig = chatConfigs.firstWhere(
        (c) => c.isDefault,
        orElse: () => chatConfigs.first,
      );

      final apiService = ref.read(apiServiceProvider);
      final polishedPrompts = await apiService.polishPromptBatch(
        apiUrl: claudeConfig.url,
        apiKey: claudeConfig.key,
        model: claudeConfig.model,
        originalPrompt: actualPrompt,
        count: batchCount,
      );

      for (int i = 0; i < batchCount; i++) {
        final polishedPrompt = i < polishedPrompts.length
            ? polishedPrompts[i]
            : actualPrompt;
        ref
            .read(generateLogicServiceProvider)
            .generateBatch(
              originalPrompt: prompt,
              polishedPrompt: polishedPrompt,
              model: currentModel,
              aspectRatio: currentAspectRatio,
              imageSize: currentImageSize,
              imageQuality: currentImageQuality,
              sampleSteps: currentSampleSteps,
              referenceImages: referenceImages,
              referenceImagePaths: refImagePaths,
              batchIndex: i,
              totalBatch: batchCount,
            );
      }
    } else {
      ref
          .read(generateLogicServiceProvider)
          .generate(
            prompt: ref.read(aiAssistantProvider).isActive
                ? actualPrompt
                : prompt,
            model: currentModel,
            aspectRatio: currentAspectRatio,
            imageSize: currentImageSize,
            imageQuality: currentImageQuality,
            sampleSteps: currentSampleSteps,
            referenceImages: referenceImages,
            referenceImagePaths: refImagePaths,
          );
    }

    _promptController.clear();
    ref.read(selectedImagesProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.dropEnabled,
      onDragDone: (details) async {
        final files = details.files
            .where(
              (file) =>
                  file.path.toLowerCase().endsWith('.png') ||
                  file.path.toLowerCase().endsWith('.jpg') ||
                  file.path.toLowerCase().endsWith('.jpeg') ||
                  file.path.toLowerCase().endsWith('.webp'),
            )
            .toList();

        for (final xFile in files) {
          final file = File(xFile.path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final fileName = file.path.split(Platform.pathSeparator).last;

            // AI助手模式下：直接发送图片给AI分析
            final aiActive = ref.read(aiAssistantProvider).isActive;
            if (aiActive) {
              final fileService = FileService();
              final appDir = fileService.getAppDirectory();
              final inputDir = Directory('$appDir/data/input');
              await inputDir.create(recursive: true);
              final targetPath = '${inputDir.path}/$fileName';
              if (file.path != targetPath) {
                await file.copy(targetPath);
              }
              final image = UploadedImage(
                id: const Uuid().v4(),
                name: fileName,
                path: targetPath,
                base64: base64Encode(bytes),
                bytes: bytes,
              );
              ref.read(uploadedImagesProvider.notifier).addImage(image);
              ref.read(selectedImagesProvider.notifier).addImage(image);
              ref
                  .read(aiAssistantProvider.notifier)
                  .registerReferenceImage(image);
              final base64Str = base64Encode(bytes);
              await ref
                  .read(aiAssistantProvider.notifier)
                  .sendImage(
                    base64Str,
                    fileName,
                    imagePath: targetPath,
                    imageId: image.id,
                  );
              continue;
            }

            // 检查是否已存在同名文件
            if (ref
                .read(uploadedImagesProvider)
                .any((img) => img.name == fileName)) {
              continue;
            }

            // 复制到data/input文件夹
            final fileService = FileService();
            final appDir = fileService.getAppDirectory();
            final inputDir = Directory('$appDir/data/input');
            await inputDir.create(recursive: true);
            final targetPath = '${inputDir.path}/$fileName';
            await file.copy(targetPath);

            final image = UploadedImage(
              id: const Uuid().v4(),
              name: fileName,
              path: targetPath,
              base64: base64Encode(bytes),
              bytes: bytes,
            );
            ref.read(uploadedImagesProvider.notifier).addImage(image);
            ref.read(selectedImagesProvider.notifier).addImage(image);
          }
        }
      },
      child: DragTarget<String>(
        onAcceptWithDetails: (details) async {
          final path = details.data;
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final fileName = file.path.split(Platform.pathSeparator).last;
            if (ref
                .read(uploadedImagesProvider)
                .any((img) => img.name == fileName)) {
              return;
            }
            final image = UploadedImage(
              id: const Uuid().v4(),
              name: fileName,
              path: path,
              base64: base64Encode(bytes),
              bytes: bytes,
            );
            ref.read(uploadedImagesProvider.notifier).addImage(image);
            ref.read(selectedImagesProvider.notifier).addImage(image);
          }
        },
        builder: (context, candidateData, rejectedData) {
          return Container(
            color: AppColors.background,
            child: Column(
              children: [
                _buildSessionHeader(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildChatHistory(),
                      if (_showScrollToBottom)
                        Positioned(
                          bottom: 20,
                          right: 20,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: AppColors.primary,
                            onPressed: _scrollToBottom,
                            child: const Icon(
                              Icons.arrow_downward,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _buildInputArea(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionHeader() {
    final session = ref.watch(currentSessionProvider);
    final credits = ref.watch(creditsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onDoubleTap: () {
              final session = ref.read(currentSessionProvider);
              if (session != null) {
                setState(() {
                  _isEditingSessionName = true;
                  _sessionNameController.text = session.name;
                });
                _sessionNameFocusNode.requestFocus();
              }
            },
            child: _isEditingSessionName
                ? SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _sessionNameController,
                      focusNode: _sessionNameFocusNode,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) async {
                        final session = ref.read(currentSessionProvider);
                        if (session != null &&
                            _sessionNameController.text.trim().isNotEmpty) {
                          await ref
                              .read(currentSessionProvider.notifier)
                              .renameSession(
                                session.name,
                                _sessionNameController.text.trim(),
                              );
                        }
                        setState(() => _isEditingSessionName = false);
                      },
                      onTapOutside: (_) async {
                        final session = ref.read(currentSessionProvider);
                        if (session != null &&
                            _sessionNameController.text.trim().isNotEmpty) {
                          await ref
                              .read(currentSessionProvider.notifier)
                              .renameSession(
                                session.name,
                                _sessionNameController.text.trim(),
                              );
                        }
                        setState(() => _isEditingSessionName = false);
                      },
                    ),
                  )
                : Text(
                    ref.watch(currentSessionProvider)?.name ?? '新会话',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          _buildTextButton(
            '清空图片',
            () => ref.read(selectedImagesProvider.notifier).clear(),
          ),
          const SizedBox(width: 8),
          _buildTextButton('新建会话', () {
            ref.read(currentSessionProvider.notifier).createNewSession();
          }),
          const SizedBox(width: 8),
          _buildTextButton('删除', () async {
            if (session != null) {
              await ref
                  .read(currentSessionProvider.notifier)
                  .deleteSession(session.name);
              ref.read(currentSessionProvider.notifier).createNewSession();
            }
          }),
          const SizedBox(width: 8),
          _buildTextButton('历史会话', () {
            showDialog(
              context: context,
              builder: (context) => const SessionHistoryDialog(),
            );
          }),
          const SizedBox(width: 8),
          _buildTextButton('会话图片管理', () {
            showDialog(
              context: context,
              builder: (context) => const SessionGalleryDialog(),
            );
          }),
          const Spacer(),
          InkWell(
            onTap: () {
              final isActive = ref.read(aiAssistantProvider).isActive;
              if (isActive) {
                ref.read(aiAssistantProvider.notifier).deactivateAssistant();
              } else {
                ref.read(aiAssistantProvider.notifier).activateAssistant();
                final selectedImages = ref.read(selectedImagesProvider);
                for (final image in selectedImages) {
                  ref
                      .read(aiAssistantProvider.notifier)
                      .registerReferenceImage(image);
                }
              }
              setState(() {});
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: ref.watch(aiAssistantProvider).isActive
                    ? AppColors.primary
                    : AppColors.inputBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: ref.watch(aiAssistantProvider).isActive
                      ? AppColors.primary
                      : AppColors.border2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.smart_toy_outlined,
                    color: ref.watch(aiAssistantProvider).isActive
                        ? Colors.white
                        : AppColors.text,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ref.watch(aiAssistantProvider).isActive ? '智能体助手' : '开启智能体',
                    style: TextStyle(
                      color: ref.watch(aiAssistantProvider).isActive
                          ? Colors.white
                          : AppColors.text,
                      fontSize: 14,
                      fontWeight: ref.watch(aiAssistantProvider).isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (credits != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border2),
              ),
              child: Text(
                '积分: $credits',
                style: const TextStyle(color: AppColors.text, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border2),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.text, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildChatHistory() {
    final session = ref.watch(currentSessionProvider);
    final aiState = ref.watch(aiAssistantProvider);
    final sessionMessages = session?.messages ?? const <Message>[];
    final aiMessages = aiState.isActive
        ? aiState.messages
        : const <AiAssistantMessage>[];

    if (sessionMessages.isEmpty && aiMessages.isEmpty) {
      return _buildCreatorEmptyState(aiState.isActive);
    }

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 4) {
          setState(() {
            _isMiddleButtonPressed = true;
            _middleButtonPressPosition = event.position;
          });
        }
      },
      onPointerMove: (event) {
        if (_isMiddleButtonPressed && _middleButtonPressPosition != null) {
          final delta = event.position.dy - _middleButtonPressPosition!.dy;
          if (delta.abs() > 5) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                (_scrollController.offset - delta * 2).clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                ),
              );
            }
            _middleButtonPressPosition = event.position;
          }
        }
      },
      onPointerUp: (event) {
        if (_isMiddleButtonPressed) {
          setState(() {
            _isMiddleButtonPressed = false;
            _middleButtonPressPosition = null;
          });
        }
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && _isBubbleZoomModifierPressed()) {
          _handleBubbleScalePointerSignal(event);
        }
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: sessionMessages.length + aiMessages.length,
        itemBuilder: (context, index) {
          if (index < sessionMessages.length) {
            final message = sessionMessages[index];
            return _buildMessageItem(message);
          }

          final aiMessage = aiMessages[index - sessionMessages.length];
          return AiAssistantBubble(
            message: aiMessage,
            onOptionTap: (option) => _handleAiOption(option),
            onSetReference: (imagePath) => _setImageAsReference(imagePath),
            onContinueEdit: (imagePath) => _continueEditFromImage(imagePath),
            onGenerateSimilar: (imagePath) =>
                _generateSimilarFromImage(imagePath),
            onImageTap: () {
              if (aiMessage.images != null && aiMessage.images!.isNotEmpty) {
                showDialog(
                  context: context,
                  builder: (context) => ImageViewerDialog(
                    imageUrl: aiMessage.images!.first,
                    imageUrls: aiMessage.images!,
                  ),
                );
              }
            },
            onSecondaryTapDown: (details) {
              _showMessageContextMenu(
                details.globalPosition,
                _ChatContextTarget(aiMessage: aiMessage),
              );
            },
            onImageSecondaryTapDown: (details, imagePath) {
              _showMessageContextMenu(
                details.globalPosition,
                _ChatContextTarget(aiMessage: aiMessage, imagePath: imagePath),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCreatorEmptyState(bool aiActive) {
    final hasReference = ref.watch(selectedImagesProvider).isNotEmpty;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF202020),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.smart_toy_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '智能体创作工作台',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasReference
                              ? '参考图已就绪，可以直接描述续创方向。'
                              : '上传参考图，或直接输入画面描述开始生成。',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!aiActive)
                    InkWell(
                      onTap: () {
                        ref
                            .read(aiAssistantProvider.notifier)
                            .activateAssistant();
                        for (final image in ref.read(selectedImagesProvider)) {
                          ref
                              .read(aiAssistantProvider.notifier)
                              .registerReferenceImage(image);
                        }
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '开启智能体',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(Message message) {
    final isUser = message.type == 'user';
    final settings = ref.watch(settingsProvider);
    final avatar = isUser
        ? settings.userNickname.substring(0, 1)
        : settings.aiNickname.substring(0, 1);
    final params = message.params;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  avatar,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onSecondaryTapDown: (details) {
                  _showMessageContextMenu(
                    details.globalPosition,
                    _ChatContextTarget(message: message),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.7 * _bubbleScale,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF3a3a3a)
                            : const Color(0xFF2a2a2a),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.text,
                            style: const TextStyle(color: Color(0xFFe0e0e0)),
                          ),
                          if (isUser &&
                              message.params != null &&
                              message.params!['referenceImages'] != null) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children:
                                  (message.params!['referenceImages']
                                          as List<dynamic>)
                                      .map((imgPath) {
                                        return InkWell(
                                          onTap: () {
                                            final refImages =
                                                message.params!['referenceImages']
                                                    as List<dynamic>;
                                            final idx = refImages.indexOf(
                                              imgPath,
                                            );
                                            showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  ImageViewerDialog(
                                                    imageUrl: imgPath,
                                                    imageUrls: refImages
                                                        .cast<String>(),
                                                    initialIndex: idx >= 0
                                                        ? idx
                                                        : 0,
                                                  ),
                                            );
                                          },
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: Image.file(
                                              File(imgPath),
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    width: 40,
                                                    height: 40,
                                                    color: Colors.grey,
                                                  ),
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                            ),
                          ],
                          if (isUser) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    _promptController.text = message.text;
                                    ref
                                        .read(selectedImagesProvider.notifier)
                                        .clear();

                                    if (message.params != null &&
                                        message.params!['referenceImages'] !=
                                            null) {
                                      final refImages =
                                          message.params!['referenceImages']
                                              as List<dynamic>;
                                      for (var imgPath in refImages) {
                                        final file = File(imgPath);
                                        if (await file.exists()) {
                                          final bytes = await file
                                              .readAsBytes();
                                          final image = UploadedImage(
                                            id: const Uuid().v4(),
                                            name: file.path
                                                .split(Platform.pathSeparator)
                                                .last,
                                            path: file.path,
                                            base64: base64Encode(bytes),
                                            bytes: bytes,
                                          );
                                          ref
                                              .read(
                                                selectedImagesProvider.notifier,
                                              )
                                              .addImage(image);
                                        }
                                      }
                                    }
                                  },
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
                                      '重新编辑',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: message.text),
                                    );
                                  },
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
                                      '复制提示词',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () async {
                                    final session = ref.read(
                                      currentSessionProvider,
                                    );
                                    if (session != null) {
                                      final msgIndex = session.messages.indexOf(
                                        message,
                                      );
                                      if (msgIndex >= 0) {
                                        await ref
                                            .read(
                                              currentSessionProvider.notifier,
                                            )
                                            .deleteMessage(msgIndex);
                                      }
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '删除',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (message.images.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: message.images.map((path) {
                                return _buildGeneratedImage(path, message);
                              }).toList(),
                            ),
                          ],
                          if (message.videos.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: message.videos.map((path) {
                                return _buildGeneratedVideo(path, message);
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (params != null && params['time'] != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${params['model']} | ${params['aspectRatio']} | ${params['imageSize']}${(() {
                              final quality = (params['imageQuality'] ?? '').toString();
                              return quality.isNotEmpty && quality != 'auto' ? " | $quality" : "";
                            })()}${params['sampleSteps'] != null ? " | ${params['sampleSteps']}步" : ""} | 耗时 ${params['time']}秒',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF3a3a3a),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  avatar,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGeneratedImage(String imagePath, Message message) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showMessageContextMenu(
          details.globalPosition,
          _ChatContextTarget(message: message, imagePath: imagePath),
        );
      },
      child: ImageWithHover(
        imagePath: imagePath,
        maxImageWidth: 330 * _bubbleScale,
        onRepaintGenerate: (prompt, imgPath, {Uint8List? croppedBytes}) =>
            _handleMultiAngleGenerate(
              prompt,
              imgPath,
              croppedBytes: croppedBytes,
            ),
        onRepaintReturnToInput: (prompt, imgPath) =>
            _handleMultiAngleReturnToInput(prompt, imgPath),
        onSetReferenceToInput: (imgPath) => _setImageAsReference(imgPath),
        onContinueEdit: (imgPath) => _continueEditFromImage(imgPath),
        onGenerateSimilar: (imgPath) => _generateSimilarFromImage(imgPath),
        onTap: () {
          final session = ref.read(currentSessionProvider);
          if (session == null) return;
          final allImages = <String>[];
          for (final msg in session.messages) {
            if (msg.type == 'assistant') {
              allImages.addAll(msg.images);
            }
          }
          final idx = allImages.indexOf(imagePath);
          showDialog(
            context: context,
            builder: (context) => ImageViewerDialog(
              imageUrl: imagePath,
              imageUrls: allImages,
              initialIndex: idx >= 0 ? idx : 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildGeneratedVideo(String videoPath, Message message) {
    final prompt = _resolvePrompt(message: message);
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showMessageContextMenu(
          details.globalPosition,
          _ChatContextTarget(
            message: message,
            videoPath: videoPath,
            videoItemId: message.params?['videoItemId']?.toString(),
          ),
        );
      },
      child: Container(
        width: 330 * _bubbleScale,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 220 * _bubbleScale,
                width: double.infinity,
                child: VideoPlayerWidget(
                  filePath: videoPath,
                  autoPlay: false,
                  showControls: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => openFullscreenVideo(context, videoPath),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('播放/全屏'),
                ),
                TextButton.icon(
                  onPressed: () => _deleteVideoMessage(
                    videoPath,
                    videoItemId: message.params?['videoItemId']?.toString(),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除'),
                ),
              ],
            ),
            if (prompt.trim().isNotEmpty)
              Text(
                prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final aiState = ref.watch(aiAssistantProvider);
    final aiActive = aiState.isActive;
    final aiBusy =
        aiActive &&
        (aiState.isProcessing || aiState.phase == AssistantPhase.generating);

    final selectedImages = ref.watch(selectedImagesProvider);
    final parameterControls = <Widget>[
      _buildSelect(_selectedModel, _imageModelItems, (v) {
        _applyModelSelection(v!);
      }, labels: _imageModelLabels),
      _buildSelect(_aspectRatio, _activeAspectRatioItems, (v) {
        _applyAspectRatioSelection(v!);
      }),
      _buildSelect(_imageSize, _activeImageSizeItems, (v) {
        _applyImageSizeSelection(v!);
      }, labels: _activeImageSizeLabels),
      if (_showImageQualitySelect)
        _buildSelect(
          _imageQuality,
          GptImageGenerationPreset.qualityOptions,
          (v) => _applyImageQualitySelection(v!),
          labels: GptImageGenerationPreset.qualityLabels,
        ),
      if (_isZImageBaseSelected) _buildZImageSampleStepsInput(),
      _buildSelect('$_batchCount', ['1', '2', '4', '6', '8'], (v) {
        setState(() => _batchCount = int.parse(v!));
      }),
    ];
    final footerHints = <Widget>[
      if (_isZImageBaseSelected) _buildZImageBaseHint(),
      if (GptImageGenerationPreset.isModel(_selectedModel))
        _buildGptImageHint(),
    ];

    return AiCreatorInputBar(
      controller: _promptController,
      focusNode: _focusNode,
      textFieldKey: _textFieldKey,
      aiActive: aiActive,
      aiBusy: aiBusy,
      selectedImages: selectedImages,
      promptHistory: _promptHistory,
      pendingAnglePrompt: _pendingAnglePrompt,
      parameterControls: parameterControls,
      footerHints: footerHints,
      onSubmit: () {
        if (aiActive) {
          _handleAiSend();
        } else {
          _handleGenerate();
        }
      },
      onUploadReference: _pickReferenceImagesFromInput,
      onClear: () => _promptController.clear(),
      onPolish: () {
        if (_promptController.text.trim().isEmpty) return;
        showDialog(
          context: context,
          builder: (context) => PolishPromptDialog(
            originalPrompt: _promptController.text,
            onSelect: (polished) => _promptController.text = polished,
          ),
        );
      },
      onHistorySelected: (history) {
        _promptController.text = history;
        _promptController.selection = TextSelection.collapsed(
          offset: _promptController.text.length,
        );
        _focusNode.requestFocus();
      },
      onInsertImageToken: (index) {
        final token = '图${index + 1}';
        final currentText = _promptController.text;
        final cursorPos = _promptController.selection.baseOffset;
        final insertAt = cursorPos < 0 || cursorPos > currentText.length
            ? currentText.length
            : cursorPos;
        final nextText =
            currentText.substring(0, insertAt) +
            token +
            currentText.substring(insertAt);
        _promptController.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: insertAt + token.length),
        );
        _focusNode.requestFocus();
      },
      onRemoveSelectedImage: (image) {
        ref.read(selectedImagesProvider.notifier).removeImage(image.name);
      },
      onEditPendingAngle: _pendingAngleImagePath == null
          ? null
          : () {
              showDialog(
                context: context,
                builder: (ctx) => RepaintEditor(
                  imagePath: _pendingAngleImagePath!,
                  onGenerate: (prompt, imgPath, {Uint8List? croppedBytes}) =>
                      _handleMultiAngleGenerate(
                        prompt,
                        imgPath,
                        croppedBytes: croppedBytes,
                      ),
                  onReturnToInput: (prompt, imgPath) =>
                      _handleMultiAngleReturnToInput(prompt, imgPath),
                ),
              );
            },
      onClearPendingAngle: () => setState(() {
        _pendingAnglePrompt = null;
        _pendingAngleImagePath = null;
      }),
    );
  }

  Widget _buildSelect(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    Map<String, String>? labels,
  }) {
    final modelStatus = ref.watch(modelStatusProvider);
    final isModelSelect = items.contains('nano-banana-fast');

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
        items: items.map((e) {
          if (e == 'divider') {
            return DropdownMenuItem(
              enabled: false,
              value: e,
              child: Container(height: 1, color: AppColors.border2),
            );
          }
          return DropdownMenuItem(
            value: e,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isModelSelect && modelStatus.containsKey(e))
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: modelStatus[e]! ? Colors.green : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(labels?[e] ?? e),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _handleAiSend() async {
    final aiState = ref.read(aiAssistantProvider);
    if (aiState.isProcessing && aiState.phase != AssistantPhase.generating) {
      return;
    }

    final text = _promptController.text.trim();
    if (text.isEmpty) return;
    _promptController.clear();
    await ref.read(aiAssistantProvider.notifier).sendMessage(text);
    _scheduleScrollToBottom();
    await _tryAutoExecutePendingPlan();
  }

  Future<void> _handleAiOption(AiOption option) async {
    final notifier = ref.read(aiAssistantProvider.notifier);
    final aiState = ref.read(aiAssistantProvider);

    switch (option.action) {
      case 'confirm':
        if (aiState.isProcessing ||
            aiState.phase == AssistantPhase.generating) {
          return;
        }
        // execute generation with the pending plan
        final plan = aiState.pendingPlan;
        if (plan != null) {
          await _executeAiPlan(plan);
        } else {
          // no plan yet, prompt user to describe
          notifier.handleOptionClick(option);
        }
        break;

      case 'save_skill':
        if (mounted) {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => const AiSkillSaveDialog(),
          );
          if (confirmed == true) {
            await notifier.saveSkill(name: '我的技能', category: '自定义', tags: []);
          } else {
            notifier.handleOptionClick(
              AiOption(
                id: 'satisfied_continue',
                label: '满意，继续新需求',
                icon: '😊',
                type: 'secondary',
                action: 'satisfied',
              ),
            );
          }
        }
        break;

      case 'view_skills':
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => const SkillLibraryDialog(),
          );
        }
        break;

      case 'use_skill':
        final skillName = option.data['skillName'] as String?;
        if (skillName != null && skillName.trim().isNotEmpty) {
          await notifier.sendMessage('请使用$skillName技能直接完成当前创作需求');
          await _tryAutoExecutePendingPlan();
        } else {
          notifier.handleOptionClick(option);
        }
        break;

      case 'post_generation_intent':
        final intent = option.data['prompt']?.toString() ?? option.label;
        await _sendPostGenerationIntent(intent);
        break;

      // these actions have data with prompt_from_image — treat as confirm
      case 'gen_similar':
      case 'gen_modify':
      case 'gen_extend':
      case 'gen_video':
        final suggestedPrompt = option.data['prompt_from_image'] as String?;
        if (suggestedPrompt != null) {
          // update pending plan with suggested prompt and confirm
          final currentPlan = aiState.pendingPlan;
          final newPlan = GenerationPlan(
            operation: option.action == 'gen_video'
                ? 'video_i2v'
                : option.action == 'gen_modify'
                ? 'image_edit'
                : 'image_generate',
            prompt: suggestedPrompt,
            model: currentPlan?.model ?? _selectedModel,
            aspectRatio: currentPlan?.aspectRatio ?? _aspectRatio,
            imageSize: currentPlan?.imageSize ?? _imageSize,
            batchCount: currentPlan?.batchCount ?? _batchCount,
            negativePrompt: currentPlan?.negativePrompt ?? '',
            videoResolution:
                currentPlan?.videoResolution ??
                ref.read(videoSettingsProvider).defaults.resolution,
            videoFrameNum:
                currentPlan?.videoFrameNum ??
                ref.read(videoSettingsProvider).defaults.frameNum,
            videoSampleSteps:
                currentPlan?.videoSampleSteps ??
                ref.read(videoSettingsProvider).defaults.sampleSteps,
            videoGuideScale:
                currentPlan?.videoGuideScale ??
                ref.read(videoSettingsProvider).defaults.guideScale,
            videoShiftScale:
                currentPlan?.videoShiftScale ??
                ref.read(videoSettingsProvider).defaults.shiftScale,
            videoSeed:
                currentPlan?.videoSeed ??
                ref.read(videoSettingsProvider).defaults.seed,
            videoSampleSolver:
                currentPlan?.videoSampleSolver ??
                ref.read(videoSettingsProvider).defaults.sampleSolver,
            videoTaskType:
                currentPlan?.videoTaskType ??
                (option.action == 'gen_video' ? 'i2v-A14B' : 't2v-A14B'),
            videoModelName:
                currentPlan?.videoModelName ??
                ref.read(videoSettingsProvider).defaults.modelName,
            sourcePreference:
                currentPlan?.sourcePreference ?? 'selected_or_latest',
          );
          await _executeAiPlan(newPlan);
        } else {
          // fallback: send as text
          await notifier.sendMessage(option.label);
          await _tryAutoExecutePendingPlan();
        }
        break;

      default:
        // all other actions handled by provider
        notifier.handleOptionClick(option);
        break;
    }
  }

  Future<void> _tryAutoExecutePendingPlan() async {
    if (_isAutoExecutingAiPlan) return;

    final aiState = ref.read(aiAssistantProvider);
    if (!aiState.isActive || aiState.isProcessing) return;
    if (aiState.messages.isEmpty) return;

    final latest = aiState.messages.last;
    if (latest.isUser) return;

    if (_lastAutoExecutedAiMessageId == latest.id) return;

    AiExecutionPlan? executionPlan = aiState.pendingExecutionPlan;
    if (executionPlan == null && latest.executionPlan != null) {
      try {
        executionPlan = AiExecutionPlan.fromJson(latest.executionPlan!);
      } catch (_) {
        executionPlan = null;
      }
    }

    if (executionPlan != null && executionPlan.autoExecute) {
      _lastAutoExecutedAiMessageId = latest.id;
      _isAutoExecutingAiPlan = true;
      try {
        await _executeAiExecutionPlan(executionPlan);
      } finally {
        _isAutoExecutingAiPlan = false;
      }
      return;
    }

    final hasConfirmOption = latest.options.any((o) => o.action == 'confirm');
    final shouldAutoExecute =
        aiState.phase == AssistantPhase.confirming || hasConfirmOption;
    if (!shouldAutoExecute) return;

    GenerationPlan? plan = aiState.pendingPlan;
    if (plan == null && latest.plan != null) {
      try {
        plan = GenerationPlan.fromJson(latest.plan!);
      } catch (_) {
        plan = null;
      }
    }
    if (plan == null || plan.prompt.trim().isEmpty) return;

    _lastAutoExecutedAiMessageId = latest.id;
    _isAutoExecutingAiPlan = true;
    try {
      await _executeAiPlan(plan);
    } finally {
      _isAutoExecutingAiPlan = false;
    }
  }

  bool _isVideoOperation(String operation) {
    return operation == 'video_t2v' || operation == 'video_i2v';
  }

  Future<void> _executeAiExecutionPlan(AiExecutionPlan plan) async {
    if (plan.isStoryboardMode) {
      await _executeAiStoryboardGeneration(plan);
      return;
    }
    if (plan.isImageMode) {
      await _executeAiImageTasks(plan);
      return;
    }
  }

  Future<void> _executeAiImageTasks(AiExecutionPlan plan) async {
    final notifier = ref.read(aiAssistantProvider.notifier);
    final expandedTasks = <AiImageTaskPlan>[];
    for (final task in plan.imageTasks) {
      final batchCount = task.batchCount < 1 ? 1 : task.batchCount;
      for (int i = 0; i < batchCount; i++) {
        expandedTasks.add(task);
      }
    }

    if (expandedTasks.isEmpty) return;
    if (expandedTasks.length > 20) {
      notifier.addLocalMessage(
        AiAssistantMessage(
          type: AssistantMessageType.text,
          text:
              '这次会提交 ${expandedTasks.length} 张图片，已超过安全上限 20 张。请把数量缩小到 20 张以内，我再继续执行。',
        ),
        phase: AssistantPhase.understanding,
        isProcessing: false,
      );
      return;
    }

    final requests = <GenerateImageTaskRequest>[];
    final hasSelectedReferences = ref.read(selectedImagesProvider).isNotEmpty;
    for (final task in expandedTasks) {
      final needsReference =
          task.operation == 'image_edit' || plan.mode == 'multi_angle';
      final refs = await _resolveReferencesForAiTask(
        task,
        requireReference: needsReference,
        fallbackToSelected: plan.mode == 'storyboard' || hasSelectedReferences,
      );
      if (needsReference && refs.isEmpty) {
        notifier.addLocalMessage(
          AiAssistantMessage(
            type: AssistantMessageType.text,
            text: '这个任务需要参考图。请先上传或选择参考图，我拿到素材后就能继续执行。',
          ),
          phase: AssistantPhase.understanding,
          isProcessing: false,
        );
        return;
      }

      final model = task.model.trim().isNotEmpty ? task.model : _selectedModel;
      final aspectRatio = task.aspectRatio.trim().isNotEmpty
          ? task.aspectRatio
          : _aspectRatio;
      final imageSize = task.imageSize.trim().isNotEmpty
          ? task.imageSize
          : _imageSize;
      final imageQuality = task.imageQuality.trim().isNotEmpty
          ? task.imageQuality
          : _imageQuality;
      requests.add(
        GenerateImageTaskRequest(
          prompt: task.prompt,
          model: model,
          aspectRatio: aspectRatio,
          imageSize: imageSize,
          imageQuality: imageQuality,
          sampleSteps:
              task.sampleSteps ?? _resolveSampleStepsForModel(model, imageSize),
          referenceImages: refs.map((img) => img.base64).toList(),
          referenceImagePaths: refs.map((img) => img.path).toList(),
        ),
      );
    }

    final summary = plan.mode == 'multi_angle'
        ? '已提交多角度生成任务，正在错峰并发生成...'
        : '已提交AI图片任务，正在生成...';
    notifier.addLocalMessage(
      AiAssistantMessage(
        type: AssistantMessageType.generating,
        text: summary,
        executionPlan: plan.toJson(),
        polishedPrompt: plan.prompt,
      ),
      phase: AssistantPhase.generating,
      isProcessing: false,
    );

    _requestScrollToBottomOnNextSessionInsert();
    final resultImages = await ref
        .read(generateLogicServiceProvider)
        .generateQueuedTasks(
          originalPrompt: plan.prompt.isNotEmpty
              ? plan.prompt
              : expandedTasks.first.prompt,
          tasks: requests,
          delayMs: plan.delayMs,
          maxConcurrency: plan.maxConcurrency,
          progressLabel: plan.mode == 'multi_angle' ? '多角度生成中' : 'AI图片生成中',
        );
    notifier.addGenerationResult(resultImages);
    ref.read(selectedImagesProvider.notifier).clear();
  }

  Future<void> _executeAiStoryboardGeneration(AiExecutionPlan plan) async {
    final notifier = ref.read(aiAssistantProvider.notifier);
    final script = plan.script.trim().isNotEmpty
        ? plan.script.trim()
        : plan.prompt.trim();
    if (script.isEmpty) return;

    final configs = ref.read(apiConfigsProvider);
    final chatConfigs = configs.where((c) => c.type == 'chat').toList();
    if (chatConfigs.isEmpty) {
      notifier.addLocalMessage(
        AiAssistantMessage(
          type: AssistantMessageType.text,
          text: '未配置聊天API，无法拆解剧本分镜。请先在设置里配置聊天模型。',
        ),
        phase: AssistantPhase.understanding,
        isProcessing: false,
      );
      return;
    }
    final chatConfig = chatConfigs.firstWhere(
      (c) => c.isDefault,
      orElse: () => chatConfigs.first,
    );

    notifier.addLocalMessage(
      AiAssistantMessage(
        type: AssistantMessageType.generating,
        text: '正在按软件内分镜规则拆解剧本...',
        executionPlan: plan.toJson(),
        polishedPrompt: script,
      ),
      phase: AssistantPhase.generating,
      isProcessing: false,
    );

    try {
      final storyboardService = StoryboardService(ref.read(apiServiceProvider));
      final shots = await storyboardService.splitScript(
        apiUrl: chatConfig.url,
        apiKey: chatConfig.key,
        model: chatConfig.model,
        script: script,
        artStyle: '',
        worldView: '',
        aspectRatio: _aspectRatio,
        assets: [],
      );
      final tasks = shots.map((shot) {
        final prompt = shot.prompt.trim().isNotEmpty
            ? shot.prompt.trim()
            : [
                shot.shotName,
                shot.shotType,
                shot.sceneDescription,
                shot.action,
                shot.expression,
              ].where((part) => part.trim().isNotEmpty).join('，');
        return AiImageTaskPlan(
          operation: 'image_generate',
          prompt: prompt,
          referenceQuery: prompt,
        );
      }).toList();

      await _executeAiImageTasks(
        AiExecutionPlan(
          mode: 'storyboard',
          prompt: plan.prompt.isNotEmpty ? plan.prompt : script,
          imageTasks: tasks,
          script: script,
          delayMs: plan.delayMs,
          maxConcurrency: plan.maxConcurrency,
        ),
      );
    } catch (e) {
      notifier.addLocalMessage(
        AiAssistantMessage(
          type: AssistantMessageType.text,
          text: '剧本分镜拆解失败：$e',
          executionPlan: plan.toJson(),
        ),
        phase: AssistantPhase.understanding,
        isProcessing: false,
      );
    }
  }

  Future<List<UploadedImage>> _resolveReferencesForAiTask(
    AiImageTaskPlan task, {
    required bool requireReference,
    bool fallbackToSelected = false,
  }) async {
    final selectedImages = ref.read(selectedImagesProvider);
    final uploadedImages = ref.read(uploadedImagesProvider);
    final allImages = <UploadedImage>[];
    final seenPaths = <String>{};
    for (final image in [...selectedImages, ...uploadedImages]) {
      if (seenPaths.add(image.path)) {
        allImages.add(image);
      }
    }

    final resolved = <UploadedImage>[];
    for (final id in task.referenceImageIds) {
      final direct = allImages.where((img) {
        return img.id == id || img.name == id || img.path == id;
      }).toList();
      if (direct.isNotEmpty) {
        resolved.add(direct.first);
        continue;
      }
      final ctx = ref
          .read(aiAssistantProvider)
          .referenceContexts
          .where((item) => item.id == id || item.name == id || item.path == id)
          .toList();
      if (ctx.isNotEmpty) {
        final image = await _loadUploadedImageFromPath(
          ctx.first.path,
          id: ctx.first.id,
          name: ctx.first.name,
        );
        if (image != null) resolved.add(image);
      }
    }

    if (resolved.isEmpty && task.referenceQuery.trim().isNotEmpty) {
      resolved.addAll(await _matchReferenceImagesByQuery(task.referenceQuery));
    }

    if (resolved.isEmpty && (requireReference || fallbackToSelected)) {
      if (selectedImages.isNotEmpty) {
        resolved.addAll(
          fallbackToSelected ? selectedImages : [selectedImages.last],
        );
      } else {
        final latestPath = _resolveLatestSessionImagePath();
        if (latestPath != null) {
          final latest = await _loadUploadedImageFromPath(latestPath);
          if (latest != null) resolved.add(latest);
        }
      }
    }

    final unique = <UploadedImage>[];
    final uniquePaths = <String>{};
    for (final image in resolved) {
      if (uniquePaths.add(image.path)) unique.add(image);
    }
    return unique;
  }

  Future<List<UploadedImage>> _matchReferenceImagesByQuery(String query) async {
    final contexts = ref.read(aiAssistantProvider).referenceContexts;
    if (contexts.isEmpty) return const [];
    final normalizedQuery = query.toLowerCase();
    final keywords = normalizedQuery
        .replaceAll(RegExp(r'[，。,.、:：;；\n\r]'), ' ')
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.length >= 2)
        .where(
          (part) =>
              part != '参考图' && part != '图片' && part != '生成' && part != '画面',
        )
        .toList();

    final scored = <MapEntry<AiReferenceContext, int>>[];
    for (final ctx in contexts) {
      final haystack = '${ctx.name} ${ctx.description}'.toLowerCase();
      var score = 0;
      if (haystack.contains(normalizedQuery)) score += 5;
      for (final keyword in keywords) {
        if (haystack.contains(keyword)) score += 1;
      }
      const hints = ['男人', '女人', '人物', '角色', '街道', '背景', '场景', '道具'];
      for (final hint in hints) {
        if (normalizedQuery.contains(hint) && haystack.contains(hint)) {
          score += 2;
        }
      }
      if (score > 0) scored.add(MapEntry(ctx, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));

    final matches = <UploadedImage>[];
    for (final entry in scored.take(3)) {
      final image = await _loadUploadedImageFromPath(
        entry.key.path,
        id: entry.key.id,
        name: entry.key.name,
      );
      if (image != null) matches.add(image);
    }
    return matches;
  }

  Future<UploadedImage?> _loadUploadedImageFromPath(
    String imagePath, {
    String? id,
    String? name,
  }) async {
    if (imagePath.trim().isEmpty) return null;
    final file = File(imagePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final fileName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : file.path.split(Platform.pathSeparator).last;
    return UploadedImage(
      id: id?.trim().isNotEmpty == true ? id!.trim() : const Uuid().v4(),
      name: fileName,
      path: imagePath,
      base64: base64Encode(bytes),
      bytes: bytes,
    );
  }

  String? _resolveLatestSessionImagePath() {
    final session = ref.read(currentSessionProvider);
    if (session == null) return null;
    for (final message in session.messages.reversed) {
      for (final imagePath in message.images.reversed) {
        if (File(imagePath).existsSync()) {
          return imagePath;
        }
      }
    }
    return null;
  }

  String? _resolvePlanSourceImagePath(GenerationPlan plan) {
    final selectedImages = ref.read(selectedImagesProvider);
    final selectedPath = selectedImages.isNotEmpty
        ? selectedImages.last.path
        : null;
    final latestPath = _resolveLatestSessionImagePath();

    switch (plan.sourcePreference) {
      case 'selected_reference':
        return selectedPath;
      case 'latest_session_image':
        return latestPath;
      default:
        return selectedPath ?? latestPath;
    }
  }

  VideoGenerateParams _buildVideoParamsFromPlan(GenerationPlan plan) {
    final defaults = ref.read(videoSettingsProvider).defaults;
    final operation = plan.operation;
    final resolvedTaskType = plan.videoTaskType.isNotEmpty
        ? plan.videoTaskType
        : (operation == 'video_i2v' ? 'i2v-A14B' : 't2v-A14B');
    final resolvedModelName = plan.videoModelName.isNotEmpty
        ? plan.videoModelName
        : defaults.modelName;
    return defaults.copyWith(
      prompt: plan.prompt,
      negativePrompt: plan.negativePrompt,
      resolution: plan.videoResolution.isNotEmpty
          ? plan.videoResolution
          : defaults.resolution,
      frameNum: plan.videoFrameNum > 0 ? plan.videoFrameNum : defaults.frameNum,
      sampleSteps: plan.videoSampleSteps > 0
          ? plan.videoSampleSteps
          : defaults.sampleSteps,
      guideScale: plan.videoGuideScale > 0
          ? plan.videoGuideScale
          : defaults.guideScale,
      shiftScale: plan.videoShiftScale > 0
          ? plan.videoShiftScale
          : defaults.shiftScale,
      seed: plan.videoSeed,
      sampleSolver: plan.videoSampleSolver.isNotEmpty
          ? plan.videoSampleSolver
          : defaults.sampleSolver,
      taskType: resolvedTaskType,
      modelName: resolvedModelName,
    );
  }

  Future<void> _executeAiPlan(GenerationPlan plan) async {
    if (_isVideoOperation(plan.operation)) {
      await _executeAiVideoGeneration(plan);
      return;
    }
    await _executeAiImageGeneration(plan);
  }

  Future<void> _executeAiImageGeneration(GenerationPlan plan) async {
    final notifier = ref.read(aiAssistantProvider.notifier);
    final configs = ref.read(apiConfigsProvider);
    if (configs.isEmpty) return;
    final prompt = plan.prompt.trim();
    if (prompt.isEmpty) return;

    final selectedImages = ref.read(selectedImagesProvider);
    final referenceImages = selectedImages.map((img) => img.base64).toList();
    final refImagePaths = selectedImages.map((img) => img.path).toList();
    if (referenceImages.isEmpty && plan.operation == 'image_edit') {
      final latestImagePath = _resolveLatestSessionImagePath();
      if (latestImagePath != null) {
        final file = File(latestImagePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          referenceImages.add(base64Encode(bytes));
          refImagePaths.add(latestImagePath);
        }
      }
    }
    final currentModel = plan.model.trim().isNotEmpty
        ? plan.model
        : _selectedModel;
    final currentAspectRatio = plan.aspectRatio.trim().isNotEmpty
        ? plan.aspectRatio
        : _aspectRatio;
    final currentImageSize = plan.imageSize.trim().isNotEmpty
        ? plan.imageSize
        : _imageSize;
    final currentImageQuality = _imageQuality;
    final currentBatchCount = plan.batchCount > 0
        ? plan.batchCount
        : _batchCount;
    final currentSampleSteps = _resolveSampleStepsForCurrentModel();
    final submittedPlan = GenerationPlan(
      operation: plan.operation,
      prompt: prompt,
      model: currentModel,
      aspectRatio: currentAspectRatio,
      imageSize: currentImageSize,
      batchCount: currentBatchCount,
      negativePrompt: plan.negativePrompt,
      videoResolution: plan.videoResolution,
      videoFrameNum: plan.videoFrameNum,
      videoSampleSteps: plan.videoSampleSteps,
      videoGuideScale: plan.videoGuideScale,
      videoShiftScale: plan.videoShiftScale,
      videoSeed: plan.videoSeed,
      videoSampleSolver: plan.videoSampleSolver,
      videoTaskType: plan.videoTaskType,
      videoModelName: plan.videoModelName,
      sourcePreference: plan.sourcePreference,
      skillId: plan.skillId,
      skillName: plan.skillName,
    );
    final startMessageCount =
        ref.read(currentSessionProvider)?.messages.length ?? 0;

    notifier.addLocalMessage(
      AiAssistantMessage(
        type: AssistantMessageType.generating,
        text: plan.operation == 'image_edit'
            ? '已提交图片修改任务，正在按当前方案生成...'
            : '已提交图片生成任务，正在按当前方案生成...',
        polishedPrompt: prompt,
        plan: submittedPlan.toJson(),
      ),
      phase: AssistantPhase.generating,
      isProcessing: false,
    );

    _requestScrollToBottomOnNextSessionInsert();

    final generateService = ref.read(generateLogicServiceProvider);
    for (int i = 0; i < currentBatchCount; i++) {
      await generateService.generate(
        prompt: prompt,
        model: currentModel,
        aspectRatio: currentAspectRatio,
        imageSize: currentImageSize,
        imageQuality: currentImageQuality,
        sampleSteps: currentSampleSteps,
        referenceImages: referenceImages,
        referenceImagePaths: refImagePaths,
      );
    }

    // collect generated image paths
    final session = ref.read(currentSessionProvider);
    final resultImages = <String>[];
    if (session != null) {
      for (final msg in session.messages.skip(startMessageCount)) {
        if (msg.type == 'assistant' && msg.images.isNotEmpty) {
          resultImages.addAll(msg.images);
        }
      }
    }

    // trigger satisfaction query
    notifier.addGenerationResult(resultImages);
    ref.read(selectedImagesProvider.notifier).clear();
  }

  Future<void> _executeAiVideoGeneration(GenerationPlan plan) async {
    final notifier = ref.read(aiAssistantProvider.notifier);
    final prompt = plan.prompt.trim();
    if (prompt.isEmpty) return;

    final params = _buildVideoParamsFromPlan(plan);
    final submittedPlan = GenerationPlan(
      operation: plan.operation,
      prompt: params.prompt,
      model: plan.model,
      aspectRatio: plan.aspectRatio,
      imageSize: plan.imageSize,
      batchCount: plan.batchCount,
      negativePrompt: params.negativePrompt,
      videoResolution: params.resolution,
      videoFrameNum: params.frameNum,
      videoSampleSteps: params.sampleSteps,
      videoGuideScale: params.guideScale,
      videoShiftScale: params.shiftScale,
      videoSeed: params.seed,
      videoSampleSolver: params.sampleSolver,
      videoTaskType: params.taskType,
      videoModelName: params.modelName,
      sourcePreference: plan.sourcePreference,
      skillId: plan.skillId,
      skillName: plan.skillName,
    );

    notifier.addLocalMessage(
      AiAssistantMessage(
        type: AssistantMessageType.generating,
        text: plan.operation == 'video_i2v'
            ? '已提交图生视频任务，结果会回流到当前会话，你可以继续和我对话。'
            : '已提交文生视频任务，结果会回流到当前会话，你可以继续和我对话。',
        polishedPrompt: prompt,
        plan: submittedPlan.toJson(),
      ),
      phase: AssistantPhase.generating,
      isProcessing: false,
    );

    try {
      final taskNotifier = ref.read(videoTaskProvider.notifier);
      if (plan.operation == 'video_i2v') {
        final sourceImagePath = _resolvePlanSourceImagePath(plan);
        if (sourceImagePath == null || !File(sourceImagePath).existsSync()) {
          notifier.addLocalMessage(
            AiAssistantMessage(
              type: AssistantMessageType.text,
              text: '当前没有可用的参考图。请先在右侧参考图区域选择图片，或先生成一张图片后再让我做图生视频。',
            ),
            phase: AssistantPhase.understanding,
            isProcessing: false,
          );
          return;
        }
        await taskNotifier.submitI2V(
          params,
          sourceImagePath,
          writeToCurrentSession: true,
        );
      } else {
        await taskNotifier.submitT2V(params, writeToCurrentSession: true);
      }
    } catch (e) {
      notifier.addLocalMessage(
        AiAssistantMessage(
          type: AssistantMessageType.text,
          text: '视频任务提交失败：${_formatVideoTaskError(e)}',
          plan: submittedPlan.toJson(),
        ),
        phase: AssistantPhase.understanding,
        isProcessing: false,
      );
    }
  }
}

class _ChatContextTarget {
  final Message? message;
  final AiAssistantMessage? aiMessage;
  final String? imagePath;
  final String? videoPath;
  final String? videoItemId;

  const _ChatContextTarget({
    this.message,
    this.aiMessage,
    this.imagePath,
    this.videoPath,
    this.videoItemId,
  });
}

String _formatVideoTaskError(Object error) {
  var text = error.toString().trim();
  const prefixes = ['Exception: ', 'Bad state: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
    }
  }
  return text;
}

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../constants/app_colors.dart';
import '../models/asset.dart';
import '../providers/asset_provider.dart';
import '../providers/api_config_provider.dart';
import '../providers/generate_provider.dart';
import '../providers/generated_images_provider.dart';
import '../providers/settings_provider.dart';
import '../services/asset_service.dart';
import '../utils/gpt_image_generation_preset.dart';
import '../providers/background_task_provider.dart';

class AssetLibraryScreen extends ConsumerStatefulWidget {
  final bool dropEnabled;

  const AssetLibraryScreen({super.key, this.dropEnabled = true});

  @override
  ConsumerState<AssetLibraryScreen> createState() => _AssetLibraryScreenState();
}

class _AssetLibraryScreenState extends ConsumerState<AssetLibraryScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<String> _categories = [
    'All',
    'Person',
    'Scene',
    'Prop',
    'Costume',
    'Other',
  ];
  bool _isDescending = true;

  // 记忆多视角生成参数
  String _lastGenModel = 'nano-banana-fast';
  String _lastGenRatio = '1:1';
  String _lastGenSize = '1K';
  String _lastGenQuality = 'auto';

  String _getCategoryName(String category) {
    const categoryMap = {
      'All': '全部',
      'Person': '人物',
      'Scene': '场景',
      'Prop': '道具',
      'Costume': '服装',
      'Other': '其他',
    };
    return categoryMap[category] ?? category;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    _loadCategoryOrder();
    _refreshData(); // 初始化时也自动刷新一次
  }

  Future<void> _loadCategoryOrder() async {
    final storage = ref.read(storageServiceProvider);
    final savedOrder = await storage.loadAssetCategoryOrder();
    if (savedOrder != null && savedOrder.isNotEmpty) {
      // 检查保存的类别是否与当前定义的类别一致（防止版本更新后硬编码类别变化导致的问题）
      final currentCategoriesSet = Set.from([
        'All',
        'Person',
        'Scene',
        'Prop',
        'Costume',
        'Other',
      ]);
      final isValidOrder =
          savedOrder.every((c) => currentCategoriesSet.contains(c)) &&
          savedOrder.length == currentCategoriesSet.length;

      if (isValidOrder) {
        setState(() {
          _categories = savedOrder;
          // 重新初始化 TabController，因为长度没变但顺序变了
          _tabController.dispose();
          _tabController = TabController(
            length: _categories.length,
            vsync: this,
          );
          _tabController.addListener(() {
            if (!_tabController.indexIsChanging) {
              setState(() {});
            }
          });
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<String> _assetDialogAspectRatioItems(String model) {
    if (GptImageGenerationPreset.isModel(model)) {
      return GptImageGenerationPreset.getAspectRatioOptions(model);
    }
    return const ['1:1', '16:9', '9:16', '4:3', '3:4'];
  }

  List<String> _assetDialogImageSizeItems(String model, String aspectRatio) {
    if (GptImageGenerationPreset.usesResolutionDropdown(model)) {
      return GptImageGenerationPreset.getImageSizeOptions(model, aspectRatio);
    }
    return GptImageGenerationPreset.legacyImageSizes;
  }

  Map<String, String>? _assetDialogImageSizeLabels(
    String model,
    String aspectRatio,
  ) {
    if (!GptImageGenerationPreset.usesResolutionDropdown(model)) {
      return null;
    }
    return GptImageGenerationPreset.getResolutionLabels(model, aspectRatio);
  }

  Map<String, String> _normalizeAssetDialogParams({
    required String model,
    required String aspectRatio,
    required String imageSize,
    required String imageQuality,
  }) {
    final ratioItems = _assetDialogAspectRatioItems(model);
    final normalizedAspectRatio = GptImageGenerationPreset.isModel(model)
        ? GptImageGenerationPreset.normalizeAspectRatio(aspectRatio)
        : ratioItems.contains(aspectRatio)
        ? aspectRatio
        : ratioItems.first;
    final normalizedImageSize = GptImageGenerationPreset.isModel(model)
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
    final normalizedQuality = GptImageGenerationPreset.normalizeQuality(
      imageQuality,
    );
    return {
      'aspectRatio': normalizedAspectRatio,
      'imageSize': normalizedImageSize,
      'imageQuality': normalizedQuality,
    };
  }

  PreferredSizeWidget _buildCustomTabBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          buildDefaultDragHandles: false, // 禁用默认拖拽句柄
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              final String category = _categories.removeAt(oldIndex);
              _categories.insert(newIndex, category);

              // 保持当前选中的类别索引正确
              if (_tabController.index == oldIndex) {
                _tabController.index = newIndex;
              } else if (_tabController.index > oldIndex &&
                  _tabController.index <= newIndex) {
                _tabController.index -= 1;
              } else if (_tabController.index < oldIndex &&
                  _tabController.index >= newIndex) {
                _tabController.index += 1;
              }

              // 永久保存排序
              ref
                  .read(storageServiceProvider)
                  .saveAssetCategoryOrder(_categories);
            });
          },
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            final isSelected = _tabController.index == index;
            return ReorderableDragStartListener(
              // 使用 Listener 包裹整个按钮区域
              key: ValueKey(category),
              index: index,
              child: GestureDetector(
                onTap: () {
                  _tabController.animateTo(index);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ), // 增加水平内边距
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border2,
                      width: 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getCategoryName(category),
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.text,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14, // 稍微增大字体
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    // 刷新资产库
    await ref.read(assetProvider.notifier).loadAssets();

    // 刷新生成图片区域（重新扫描 output 文件夹）
    final appDir = Directory.current;
    final outputDir = Directory(path.join(appDir.path, 'data', 'output'));
    if (await outputDir.exists()) {
      final List<GeneratedImage> images = [];
      await for (final entity in outputDir.list(recursive: false)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (ext == '.png' ||
              ext == '.jpg' ||
              ext == '.jpeg' ||
              ext == '.webp') {
            final stat = await entity.stat();
            images.add(
              GeneratedImage(path: entity.path, timestamp: stat.modified),
            );
          }
        }
      }
      // 按时间倒序排序
      images.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      ref.read(generatedImagesProvider.notifier).setImages(images);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetProvider);
    final generatedImages = ref.watch(generatedImagesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.sidebar,
        title: const Text('影视资产库', style: TextStyle(color: AppColors.text)),
        bottom: _buildCustomTabBar(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.text),
            onPressed: _refreshData,
          ),
        ],
      ),
      body: DropTarget(
        enable: widget.dropEnabled,
        onDragDone: (details) {
          if (details.files.isNotEmpty) {
            _handleImageDrop(details.files.first.path);
          }
        },
        child: Row(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _categories.map((category) {
                  final filteredAssets = category == 'All'
                      ? assets
                      : assets.where((a) => a.category == category).toList();
                  return _buildAssetGrid(filteredAssets);
                }).toList(),
              ),
            ),
            _buildGeneratedImagesSidebar(generatedImages),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF424242),
        onPressed: () => _showAddEditDialog(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildGeneratedImagesSidebar(List<GeneratedImage> images) {
    return Container(
      width: 200,
      color: AppColors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '生成作品区',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.sort,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  color: AppColors.sidebar,
                  onSelected: (value) {
                    setState(() {
                      _isDescending = value == 'desc';
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'desc',
                      child: Text(
                        '倒序',
                        style: TextStyle(color: AppColors.text),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'asc',
                      child: Text(
                        '正序',
                        style: TextStyle(color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: images.isEmpty
                ? Center(
                    child: Text(
                      '暂无生成图片',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      final img = _isDescending
                          ? images[index]
                          : images[images.length - 1 - index];
                      return Draggable<String>(
                        data: img.path,
                        // 修复：添加 onDragEnd 监听，如果未被接受（wasAccepted为false），则不做任何处理
                        // 但这里我们希望如果拖拽到标签页区域（被DropTarget接受），也能触发添加逻辑
                        // 问题在于：DropTarget (desktop_drop) 监听的是系统级拖拽，而Draggable是Flutter内部拖拽
                        // 我们需要在 body 的 DragTarget 中同时处理内部拖拽数据
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(img.path),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.inputBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(img.path),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetGrid(List<Asset> assets) {
    // 允许在空白区域和已有资产区域拖拽
    // 嵌套一个 Flutter 原生 DragTarget 来接收内部 Draggable
    return DragTarget<String>(
      onAcceptWithDetails: (details) => _handleImageDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        // 如果资产为空，显示占位符
        if (assets.isEmpty) {
          return Center(
            child: Text(
              candidateData.isNotEmpty ? '松开添加到当前类别' : '拖拽图片到此处添加资产',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        final groupedAssets = <String, List<Asset>>{};
        for (var asset in assets) {
          groupedAssets.putIfAbsent(asset.category, () => []).add(asset);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupedAssets.length,
          itemBuilder: (context, categoryIndex) {
            final category = groupedAssets.keys.elementAt(categoryIndex);
            final categoryAssets = groupedAssets[category]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (categoryIndex > 0)
                  const Divider(color: AppColors.border1, height: 32),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _getCategoryName(category),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: categoryAssets.length,
                  itemBuilder: (context, index) {
                    final asset = categoryAssets[index];
                    return GestureDetector(
                      onTap: () => _showAddEditDialog(context, asset: asset),
                      onLongPress: () => _showDeleteDialog(context, asset),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.sidebar,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: candidateData.isNotEmpty
                                ? AppColors.primary
                                : AppColors.border1,
                            width: candidateData.isNotEmpty ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                                child:
                                    asset.imagePath.isNotEmpty &&
                                        File(asset.imagePath).existsSync()
                                    ? Image.file(
                                        File(asset.imagePath),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return const Center(
                                                child: Icon(
                                                  Icons.broken_image,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              );
                                            },
                                      )
                                    : const Center(
                                        child: Icon(
                                          Icons.image_not_supported,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    asset.name,
                                    style: const TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (asset.description.isNotEmpty)
                                    Text(
                                      asset.description,
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleImageDrop(String imagePath) async {
    // 获取当前选中的类别
    final currentCategory = _categories[_tabController.index];
    // 如果当前选中的是 'All'，则默认使用 'Person'
    final defaultCategory = currentCategory == 'All'
        ? 'Person'
        : currentCategory;

    // 检查是否已经在 showDialog，避免重复弹出
    // 注意：Flutter中没有直接API检查当前是否弹窗，这里通过简单的flag或直接弹出
    // 实际场景中，DropTarget可能会频繁触发，需要防抖或状态锁
    // 这里简单处理：每次Drop都弹出，用户取消即可

    await _showAddEditDialog(
      context,
      imagePath: imagePath,
      initialCategory: defaultCategory, // 传递初始类别
    );
  }

  /// 多角度视图预设定义
  static List<Map<String, String>> _getViewPreset(int count) {
    // 正面就是主图，不需要生成
    const all = [
      {
        'angle': '左侧',
        'prompt': 'left side view, profile view from the left',
        'desc': '左侧视图',
      },
      {
        'angle': '右侧',
        'prompt': 'right side view, profile view from the right',
        'desc': '右侧视图',
      },
      {'angle': '背面', 'prompt': 'back view, seen from behind', 'desc': '背面视图'},
      {
        'angle': '面部特写',
        'prompt': 'close-up face portrait, detailed facial features',
        'desc': '面部特写',
      },
      {'angle': '全身', 'prompt': 'full body shot, head to toe', 'desc': '全身视图'},
      {
        'angle': '顶部',
        'prompt': 'top-down view, bird eye view from above',
        'desc': '顶部俯视图',
      },
      {
        'angle': '脚部',
        'prompt': 'close-up of feet and shoes, low angle',
        'desc': '脚部特写',
      },
      {
        'angle': '眼睛特写',
        'prompt': 'extreme close-up of eyes, detailed iris',
        'desc': '眼睛特写',
      },
    ];
    if (count == 3) return all.sublist(0, 2); // 左侧+右侧（主图=正面，共3视图）
    if (count == 6) return all.sublist(0, 5); // +背面+面部特写+全身（共6视图含主图）
    return all; // 全部8个+主图=9视图
  }

  Future<void> _showAddEditDialog(
    BuildContext context, {
    Asset? asset,
    String? imagePath,
    String? initialCategory,
  }) async {
    final isEditing = asset != null;
    final nameController = TextEditingController(text: asset?.name);
    final descriptionController = TextEditingController(
      text: asset?.description,
    );
    String selectedCategory = asset?.category ?? initialCategory ?? 'Person';
    String? selectedImagePath = imagePath ?? asset?.imagePath;
    final List<AssetRefImage> extraImages = List.from(asset?.images ?? []);
    // 预制2个空视图框（左侧/右侧），正面就是左侧的主图
    if (extraImages.isEmpty) {
      final presetNames = ['左侧', '右侧'];
      for (final name in presetNames) {
        extraImages.add(AssetRefImage(path: '', name: name, description: ''));
      }
    }
    bool isGenerating = false;
    int generatedCount = 0;
    int totalToGenerate = 0;
    String? _fgTaskId; // 前台生成转后台时的任务ID
    bool _fgMinimized = false; // 前台生成是否已最小化

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return Dialog(
            backgroundColor: AppColors.sidebar,
            child: Container(
              width: 800,
              height: 600,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 标题栏
                  Row(
                    children: [
                      Text(
                        isEditing ? '编辑资产' : '添加资产',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (selectedImagePath != null) ...[
                        _buildViewBtn(
                          3,
                          isGenerating,
                          () => _generateViews(
                            3,
                            selectedImagePath!,
                            nameController.text,
                            selectedCategory,
                            extraImages,
                            setDialogState,
                            (v) => isGenerating = v,
                            (v) => generatedCount = v,
                            (v) => totalToGenerate = v,
                            extraImages.length,
                            bgTaskIdGetter: () => _fgTaskId,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildViewBtn(
                          6,
                          isGenerating,
                          () => _generateViews(
                            6,
                            selectedImagePath!,
                            nameController.text,
                            selectedCategory,
                            extraImages,
                            setDialogState,
                            (v) => isGenerating = v,
                            (v) => generatedCount = v,
                            (v) => totalToGenerate = v,
                            extraImages.length,
                            bgTaskIdGetter: () => _fgTaskId,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildViewBtn(
                          9,
                          isGenerating,
                          () => _generateViews(
                            9,
                            selectedImagePath!,
                            nameController.text,
                            selectedCategory,
                            extraImages,
                            setDialogState,
                            (v) => isGenerating = v,
                            (v) => generatedCount = v,
                            (v) => totalToGenerate = v,
                            extraImages.length,
                            bgTaskIdGetter: () => _fgTaskId,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      // 最小化按钮（生成中时显示）
                      if (isGenerating)
                        IconButton(
                          icon: const Icon(
                            Icons.minimize,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          tooltip: '最小化到后台',
                          onPressed: () {
                            if (_fgTaskId == null) {
                              _fgTaskId =
                                  'asset_fg_${DateTime.now().millisecondsSinceEpoch}';
                              ref
                                  .read(backgroundTaskProvider.notifier)
                                  .addTask(
                                    BackgroundTask(
                                      id: _fgTaskId!,
                                      title: '生成${nameController.text}多角度图',
                                      description:
                                          '$generatedCount/$totalToGenerate 完成',
                                      progress: totalToGenerate > 0
                                          ? generatedCount / totalToGenerate
                                          : 0,
                                      targetPageIndex: 3,
                                    ),
                                  );
                            }
                            _fgMinimized = true;
                            Navigator.pop(dialogContext);
                          },
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: isGenerating
                            ? null
                            : () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isGenerating)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: totalToGenerate > 0
                                ? generatedCount / totalToGenerate
                                : 0,
                            backgroundColor: AppColors.inputBg,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '正在生成多角度参考图 ($generatedCount/$totalToGenerate)',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 主体内容
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧：主图 + 基本信息
                        SizedBox(
                          width: 280,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final result = await FilePicker.platform
                                        .pickFiles(type: FileType.image);
                                    if (result != null &&
                                        result.files.single.path != null) {
                                      setDialogState(
                                        () => selectedImagePath =
                                            result.files.single.path,
                                      );
                                    }
                                  },
                                  child: Container(
                                    height: 180,
                                    width: 180,
                                    decoration: BoxDecoration(
                                      color: AppColors.inputBg,
                                      border: Border.all(
                                        color: AppColors.border2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: selectedImagePath != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.file(
                                              File(selectedImagePath!),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.add_a_photo,
                                                color: AppColors.textSecondary,
                                                size: 40,
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                '点击选择主图',
                                                style: TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: nameController,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: const InputDecoration(
                                    labelText: '名称',
                                    labelStyle: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.border2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: selectedCategory,
                                  dropdownColor: AppColors.sidebar,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: const InputDecoration(
                                    labelText: '类别',
                                    labelStyle: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.border2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    isDense: true,
                                  ),
                                  items: _categories
                                      .where((c) => c != 'All')
                                      .map(
                                        (c) => DropdownMenuItem(
                                          value: c,
                                          child: Text(_getCategoryName(c)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) => setDialogState(
                                    () => selectedCategory = val!,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: descriptionController,
                                  style: const TextStyle(color: AppColors.text),
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: '备注',
                                    hintText: 'AI助手将结合名称和备注进行智能匹配',
                                    labelStyle: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                    hintStyle: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.border2,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 右侧：预制视图框网格
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '参考图列表',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${extraImages.where((e) => e.path.isNotEmpty).length}/${extraImages.length}张)',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Spacer(),
                                  // 添加更多空框
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_circle_outline,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    tooltip: '添加更多视图框',
                                    onPressed: () => setDialogState(
                                      () => extraImages.add(
                                        AssetRefImage(
                                          path: '',
                                          name: '',
                                          description: '',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        childAspectRatio: 0.7,
                                      ),
                                  itemCount: extraImages.length,
                                  itemBuilder: (ctx, index) => _buildViewSlot(
                                    extraImages,
                                    index,
                                    selectedCategory,
                                    setDialogState,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 底部按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (isEditing)
                        TextButton(
                          onPressed: isGenerating
                              ? null
                              : () {
                                  Navigator.pop(dialogContext);
                                  _showDeleteDialog(context, asset!);
                                },
                          child: const Text(
                            '删除',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: isGenerating
                            ? null
                            : () => Navigator.pop(dialogContext),
                        child: const Text(
                          '取消',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        onPressed: isGenerating
                            ? null
                            : () async {
                                if (nameController.text.isEmpty ||
                                    selectedImagePath == null) {
                                  ScaffoldMessenger.of(
                                    dialogContext,
                                  ).showSnackBar(
                                    const SnackBar(content: Text('名称和图片为必填项')),
                                  );
                                  return;
                                }
                                String finalImagePath = selectedImagePath!;
                                final isNewImage =
                                    asset?.imagePath != selectedImagePath;
                                if (isNewImage) {
                                  try {
                                    final service = ref.read(
                                      assetServiceProvider,
                                    );
                                    finalImagePath = await service
                                        .copyImageToAssets(
                                          selectedImagePath!,
                                          selectedCategory,
                                        );
                                  } catch (e) {
                                    debugPrint('Error copying image: $e');
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(content: Text('保存图片失败: $e')),
                                      );
                                    return;
                                  }
                                }
                                final newAsset = Asset(
                                  id: isEditing ? asset!.id : const Uuid().v4(),
                                  name: nameController.text,
                                  category: selectedCategory,
                                  imagePath: finalImagePath,
                                  description: descriptionController.text,
                                  images: extraImages
                                      .where((e) => e.path.isNotEmpty)
                                      .toList(),
                                );
                                if (isEditing) {
                                  ref
                                      .read(assetProvider.notifier)
                                      .updateAsset(newAsset);
                                } else {
                                  ref
                                      .read(assetProvider.notifier)
                                      .addAsset(newAsset);
                                }
                                if (mounted) Navigator.pop(dialogContext);
                              },
                        child: const Text(
                          '保存',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 视图框（空框显示加号，有图显示图片）
  Widget _buildViewSlot(
    List<AssetRefImage> extraImages,
    int index,
    String category,
    StateSetter setDialogState,
  ) {
    final img = extraImages[index];
    final isEmpty = img.path.isEmpty;
    final viewLabel = img.name.isNotEmpty ? img.name : '视图${index + 1}';

    if (isEmpty) {
      // 空框：显示加号和视图名称
      return GestureDetector(
        onTap: () async {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.image,
          );
          if (result != null && result.files.single.path != null) {
            final service = ref.read(assetServiceProvider);
            try {
              final savedPath = await service.copyImageToAssets(
                result.files.single.path!,
                category,
              );
              setDialogState(
                () => extraImages[index] = img.copyWith(path: savedPath),
              );
            } catch (e) {
              debugPrint('Error adding image: $e');
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.border2,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            color: AppColors.textSecondary.withOpacity(0.4),
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击上传',
                            style: TextStyle(
                              color: AppColors.textSecondary.withOpacity(0.5),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 删除空框按钮（预制的2个不显示删除）
                    if (index >= 2)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setDialogState(() => extraImages.removeAt(index)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 名称编辑
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 28,
                        child: TextField(
                          controller: TextEditingController(text: img.name),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            hintText: viewLabel,
                            hintStyle: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                          ),
                          onChanged: (val) =>
                              extraImages[index] = img.copyWith(name: val),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(
                            text: img.description,
                          ),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: '描述',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) => extraImages[index] = img.copyWith(
                            description: val,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 有图片的框
    final imgFile = File(img.path);
    final exists = imgFile.existsSync();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  child: exists
                      ? Image.file(
                          imgFile,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: AppColors.textSecondary,
                          ),
                        ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setDialogState(() {
                      if (index < 2) {
                        // 预制框只清空图片，不删除框
                        extraImages[index] = img.copyWith(path: '');
                      } else {
                        extraImages.removeAt(index);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  left: 2,
                  child: GestureDetector(
                    onTap: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                      );
                      if (result != null && result.files.single.path != null) {
                        final service = ref.read(assetServiceProvider);
                        try {
                          final savedPath = await service.copyImageToAssets(
                            result.files.single.path!,
                            category,
                          );
                          setDialogState(
                            () => extraImages[index] = img.copyWith(
                              path: savedPath,
                            ),
                          );
                        } catch (e) {
                          debugPrint('Error replacing image: $e');
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.swap_horiz,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                children: [
                  SizedBox(
                    height: 28,
                    child: TextField(
                      controller: TextEditingController(text: img.name),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 11,
                      ),
                      decoration: const InputDecoration(
                        hintText: '名称',
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                      ),
                      onChanged: (val) =>
                          extraImages[index] = img.copyWith(name: val),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: img.description),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: '描述',
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) =>
                          extraImages[index] = img.copyWith(description: val),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewBtn(int count, bool isGenerating, VoidCallback onPressed) {
    return SizedBox(
      height: 30,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF424242),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: isGenerating ? null : onPressed,
        child: Text(
          '${count}视图',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }

  /// 弹出生成参数选择面板
  Future<Map<String, String>?> _showGenerateParamsDialog(
    BuildContext parentContext,
  ) async {
    // 使用上次记忆的参数作为初始值
    String selectedModel = _lastGenModel;
    String selectedRatio = _lastGenRatio;
    String selectedSize = _lastGenSize;
    String selectedQuality = _lastGenQuality;
    final initialNormalized = _normalizeAssetDialogParams(
      model: selectedModel,
      aspectRatio: selectedRatio,
      imageSize: selectedSize,
      imageQuality: selectedQuality,
    );
    selectedRatio = initialNormalized['aspectRatio']!;
    selectedSize = initialNormalized['imageSize']!;
    selectedQuality = initialNormalized['imageQuality']!;

    const models = [
      'z_image_base',
      'nano-banana',
      'nano-banana-2',
      'nano-banana-fast',
      'nano-banana-pro',
      'nano-banana-pro-4k-vip',
      'nano-banana-pro-cl',
      'nano-banana-pro-vip',
      'nano-banana-pro-vt',
      'gpt-image-2',
      'gpt-image-2-vip',
    ];

    final result = await showDialog<Map<String, String>>(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setParamState) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text(
            '生成参数设置',
            style: TextStyle(color: AppColors.text, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedModel,
                dropdownColor: AppColors.sidebar,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: '模型',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  isDense: true,
                ),
                items: models
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (val) {
                  final normalized = _normalizeAssetDialogParams(
                    model: val!,
                    aspectRatio: selectedRatio,
                    imageSize: selectedSize,
                    imageQuality: selectedQuality,
                  );
                  setParamState(() {
                    selectedModel = val;
                    selectedRatio = normalized['aspectRatio']!;
                    selectedSize = normalized['imageSize']!;
                    selectedQuality = normalized['imageQuality']!;
                  });
                  unawaited(
                    ref
                        .read(apiConfigsProvider.notifier)
                        .autoSwitchImageConfigForModel(val!),
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRatio,
                dropdownColor: AppColors.sidebar,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: '图片比例',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  isDense: true,
                ),
                items: _assetDialogAspectRatioItems(selectedModel)
                    .map(
                      (ratio) =>
                          DropdownMenuItem(value: ratio, child: Text(ratio)),
                    )
                    .toList(),
                onChanged: (val) {
                  final normalized = _normalizeAssetDialogParams(
                    model: selectedModel,
                    aspectRatio: val!,
                    imageSize: selectedSize,
                    imageQuality: selectedQuality,
                  );
                  setParamState(() {
                    selectedRatio = normalized['aspectRatio']!;
                    selectedSize = normalized['imageSize']!;
                    selectedQuality = normalized['imageQuality']!;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedSize,
                dropdownColor: AppColors.sidebar,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                  labelText: '分辨率',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                  isDense: true,
                ),
                items: _assetDialogImageSizeItems(selectedModel, selectedRatio)
                    .map(
                      (size) => DropdownMenuItem(
                        value: size,
                        child: Text(
                          _assetDialogImageSizeLabels(
                                selectedModel,
                                selectedRatio,
                              )?[size] ??
                              size,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setParamState(() => selectedSize = val!),
              ),
              if (GptImageGenerationPreset.supportsQuality(selectedModel)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedQuality,
                  dropdownColor: AppColors.sidebar,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: '质量',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                    isDense: true,
                  ),
                  items: GptImageGenerationPreset.qualityOptions
                      .map(
                        (quality) => DropdownMenuItem(
                          value: quality,
                          child: Text(
                            GptImageGenerationPreset.qualityLabels[quality] ??
                                quality,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) =>
                      setParamState(() => selectedQuality = val!),
                ),
              ],
              if (GptImageGenerationPreset.isVipModel(selectedModel)) ...[
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'GPT-Image-2-VIP：分辨率会随比例联动，支持更高像素尺寸。',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
              onPressed: () => Navigator.pop(ctx, {
                'apiUrl':
                    (ref
                            .read(apiConfigsProvider.notifier)
                            .resolveImageConfigForModel(selectedModel))
                        ?.url ??
                    '',
                'apiKey':
                    (ref
                            .read(apiConfigsProvider.notifier)
                            .resolveImageConfigForModel(selectedModel))
                        ?.key ??
                    '',
                'model': selectedModel,
                'aspectRatio': selectedRatio,
                'imageSize': selectedSize,
                'imageQuality': selectedQuality,
                'background': 'true',
              }),
              child: const Text('后台生成', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () => Navigator.pop(ctx, {
                'apiUrl':
                    (ref
                            .read(apiConfigsProvider.notifier)
                            .resolveImageConfigForModel(selectedModel))
                        ?.url ??
                    '',
                'apiKey':
                    (ref
                            .read(apiConfigsProvider.notifier)
                            .resolveImageConfigForModel(selectedModel))
                        ?.key ??
                    '',
                'model': selectedModel,
                'aspectRatio': selectedRatio,
                'imageSize': selectedSize,
                'imageQuality': selectedQuality,
              }),
              child: const Text('开始生成', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    // 记忆本次选择的参数
    if (result != null) {
      _lastGenModel = selectedModel;
      _lastGenRatio = selectedRatio;
      _lastGenSize = selectedSize;
      _lastGenQuality = selectedQuality;
    }

    return result;
  }

  Future<void> _generateViews(
    int count,
    String mainImagePath,
    String assetName,
    String category,
    List<AssetRefImage> extraImages,
    StateSetter setDialogState,
    void Function(bool) setGenerating,
    void Function(int) setGenCount,
    void Function(int) setTotal,
    int initialImageCount, {
    String? Function()? bgTaskIdGetter,
  }) async {
    if (assetName.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先填写名称')));
      return;
    }

    // 弹出参数选择面板
    final params = await _showGenerateParamsDialog(context);
    if (params == null) return; // 用户取消

    final isBackground = params['background'] == 'true';
    final apiService = ref.read(apiServiceProvider);
    final assetService = ref.read(assetServiceProvider);
    final settings = ref.read(settingsProvider);
    final views = _getViewPreset(count);

    if (isBackground) {
      // 后台生成模式：关闭对话框，任务在后台运行
      final taskId = 'asset_gen_${DateTime.now().millisecondsSinceEpoch}';
      ref
          .read(backgroundTaskProvider.notifier)
          .addTask(
            BackgroundTask(
              id: taskId,
              title: '生成$assetName多角度图',
              description: '0/${views.length}',
              progress: 0,
              targetPageIndex: 3, // 影视资产库页面索引
            ),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已转入后台生成，可在左下角查看进度'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // 后台异步执行
      _runBackgroundGenerate(
        taskId,
        views,
        mainImagePath,
        assetName,
        category,
        params,
        extraImages,
        setDialogState,
        initialImageCount,
      );
      return;
    }

    // 前台生成模式（支持最小化到后台）
    setDialogState(() {
      setGenerating(true);
      setGenCount(0);
      setTotal(views.length);
    });

    // 确保有足够的视图框
    while (extraImages.length < views.length) {
      final viewIdx = extraImages.length;
      final viewName = viewIdx < views.length
          ? views[viewIdx]['angle']!
          : '视图${viewIdx + 1}';
      extraImages.add(AssetRefImage(path: '', name: viewName, description: ''));
    }
    try {
      setDialogState(() {});
    } catch (_) {}

    // 先把主图拷贝到资产目录（为最小化后自动保存做准备）
    String finalMainImagePath = mainImagePath;
    try {
      finalMainImagePath = await assetService.copyImageToAssets(
        mainImagePath,
        category,
      );
    } catch (e) {
      debugPrint('Error copying main image to assets: $e');
    }

    // 主图转base64
    String mainImageUrl = mainImagePath;
    if (!mainImageUrl.startsWith('http')) {
      try {
        final bytes = await File(mainImagePath).readAsBytes();
        final ext = path
            .extension(mainImagePath)
            .toLowerCase()
            .replaceAll('.', '');
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        mainImageUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      } catch (e) {
        debugPrint('Error reading main image: $e');
      }
    }

    int completed = 0;
    int failed = 0;
    final futures = <Future>[];
    for (int i = 0; i < views.length; i++) {
      final view = views[i];
      final targetIdx = i;
      futures.add(() async {
        try {
          String? resultUrl;
          await for (final progress in apiService.generateImage(
            apiUrl: params['apiUrl']!,
            apiKey: params['apiKey']!,
            model: params['model']!,
            prompt:
                'Based on the reference image, generate a ${view['prompt']} of this character/subject named "$assetName". Maintain consistency in appearance, clothing, and style. The image should only show this single view angle, not a multi-view sheet.',
            aspectRatio: params['aspectRatio']!,
            imageSize: params['imageSize']!,
            imageQuality: params['imageQuality'] ?? 'auto',
            urls: [mainImageUrl],
            uploadMethod: settings.uploadMethod,
          )) {
            if (progress.status == 'succeeded' &&
                progress.results != null &&
                progress.results!.isNotEmpty) {
              resultUrl = progress.results!.first;
            } else if (progress.status == 'failed') {
              throw Exception(progress.error ?? '生成失败');
            }
          }
          if (resultUrl != null) {
            final savedPath = await _downloadAndSaveImage(
              resultUrl,
              assetService,
              category,
            );
            extraImages[targetIdx] = AssetRefImage(
              path: savedPath,
              name: '$assetName的${view['angle']}',
              description: view['desc']!,
            );
            completed++;
            try {
              setDialogState(() {
                setGenCount(completed);
              });
            } catch (_) {}
            // 更新后台任务进度（如果已最小化）
            final tid = bgTaskIdGetter?.call();
            if (tid != null) {
              ref
                  .read(backgroundTaskProvider.notifier)
                  .updateTask(
                    tid,
                    description: '$completed/${views.length} 完成',
                    progress: completed / views.length,
                  );
            }
          }
        } catch (e) {
          completed++;
          failed++;
          try {
            setDialogState(() {
              setGenCount(completed);
            });
          } catch (_) {}
          final tid = bgTaskIdGetter?.call();
          if (tid != null) {
            ref
                .read(backgroundTaskProvider.notifier)
                .updateTask(
                  tid,
                  description: '$completed/${views.length} (${failed}失败)',
                  progress: completed / views.length,
                );
          }
          debugPrint('Error generating view ${view['angle']}: $e');
        }
      }());
    }
    await Future.wait(futures);
    try {
      setDialogState(() => setGenerating(false));
    } catch (_) {}

    // 如果已最小化到后台，更新后台任务状态并自动保存资产
    final tid = bgTaskIdGetter?.call();
    if (tid != null) {
      // 自动保存资产到资产库
      final validImages = extraImages.where((e) => e.path.isNotEmpty).toList();
      final newAsset = Asset(
        id: const Uuid().v4(),
        name: assetName,
        category: category,
        imagePath: finalMainImagePath,
        description: '',
        images: validImages,
      );
      await ref.read(assetProvider.notifier).addAsset(newAsset);

      ref
          .read(backgroundTaskProvider.notifier)
          .updateTask(
            tid,
            description: failed > 0
                ? '完成 (${views.length - failed}成功, $failed失败)'
                : '全部完成',
            progress: 1.0,
            isComplete: true,
          );
    }
  }

  Future<void> _runBackgroundGenerate(
    String taskId,
    List<Map<String, String>> views,
    String mainImagePath,
    String assetName,
    String category,
    Map<String, String> params,
    List<AssetRefImage> extraImages,
    StateSetter setDialogState,
    int initialImageCount, {
    String description = '',
  }) async {
    final apiService = ref.read(apiServiceProvider);
    final assetService = ref.read(assetServiceProvider);
    final settings = ref.read(settingsProvider);

    // 先把主图拷贝到资产目录
    String finalMainImagePath = mainImagePath;
    try {
      finalMainImagePath = await assetService.copyImageToAssets(
        mainImagePath,
        category,
      );
    } catch (e) {
      debugPrint('Error copying main image to assets: $e');
    }

    // 确保有足够的视图框
    while (extraImages.length < views.length) {
      final viewIdx = extraImages.length;
      final viewName = viewIdx < views.length
          ? views[viewIdx]['angle']!
          : '视图${viewIdx + 1}';
      extraImages.add(AssetRefImage(path: '', name: viewName, description: ''));
    }

    String mainImageUrl = mainImagePath;
    if (!mainImageUrl.startsWith('http')) {
      try {
        final bytes = await File(mainImagePath).readAsBytes();
        final ext = path
            .extension(mainImagePath)
            .toLowerCase()
            .replaceAll('.', '');
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        mainImageUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      } catch (e) {
        debugPrint('Error reading main image: $e');
      }
    }

    int completed = 0;
    int failed = 0;
    final futures = <Future>[];
    for (int i = 0; i < views.length; i++) {
      final view = views[i];
      final targetIdx = i;
      futures.add(() async {
        try {
          String? resultUrl;
          await for (final progress in apiService.generateImage(
            apiUrl: params['apiUrl']!,
            apiKey: params['apiKey']!,
            model: params['model']!,
            prompt:
                'Based on the reference image, generate a ${view['prompt']} of this character/subject named "$assetName". Maintain consistency in appearance, clothing, and style. The image should only show this single view angle, not a multi-view sheet.',
            aspectRatio: params['aspectRatio']!,
            imageSize: params['imageSize']!,
            imageQuality: params['imageQuality'] ?? 'auto',
            urls: [mainImageUrl],
            uploadMethod: settings.uploadMethod,
          )) {
            if (progress.status == 'succeeded' &&
                progress.results != null &&
                progress.results!.isNotEmpty) {
              resultUrl = progress.results!.first;
            } else if (progress.status == 'failed') {
              throw Exception(progress.error ?? '生成失败');
            }
          }
          if (resultUrl != null) {
            final savedPath = await _downloadAndSaveImage(
              resultUrl,
              assetService,
              category,
            );
            extraImages[targetIdx] = AssetRefImage(
              path: savedPath,
              name: '$assetName的${view['angle']}',
              description: view['desc']!,
            );
            completed++;
            ref
                .read(backgroundTaskProvider.notifier)
                .updateTask(
                  taskId,
                  description: '$completed/${views.length} 完成',
                  progress: completed / views.length,
                );
          }
        } catch (e) {
          completed++;
          failed++;
          ref
              .read(backgroundTaskProvider.notifier)
              .updateTask(
                taskId,
                description: '$completed/${views.length} (${failed}失败)',
                progress: completed / views.length,
              );
          debugPrint('Error generating view ${view['angle']}: $e');
        }
      }());
    }
    await Future.wait(futures);

    // 生成完成后，自动创建资产并保存到资产库
    final validImages = extraImages.where((e) => e.path.isNotEmpty).toList();
    final newAsset = Asset(
      id: const Uuid().v4(),
      name: assetName,
      category: category,
      imagePath: finalMainImagePath,
      description: description,
      images: validImages,
    );
    await ref.read(assetProvider.notifier).addAsset(newAsset);

    ref
        .read(backgroundTaskProvider.notifier)
        .updateTask(
          taskId,
          description: failed > 0
              ? '完成 (${views.length - failed}成功, $failed失败)'
              : '全部完成',
          progress: 1.0,
          isComplete: true,
        );
  }

  Future<String> _downloadAndSaveImage(
    String imageUrl,
    AssetService assetService,
    String category,
  ) async {
    final assetsDir = assetService.getAssetsDir();
    final categoryDir = Directory(path.join(assetsDir, category));
    if (!await categoryDir.exists()) await categoryDir.create(recursive: true);
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}.png';
    final targetPath = path.join(categoryDir.path, fileName);
    if (imageUrl.startsWith('http')) {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(imageUrl));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      await File(targetPath).writeAsBytes(bytes);
      httpClient.close();
    } else if (imageUrl.startsWith('data:')) {
      final base64Data = imageUrl.split(',').last;
      await File(targetPath).writeAsBytes(base64Decode(base64Data));
    } else {
      await File(imageUrl).copy(targetPath);
    }
    return targetPath;
  }

  Future<void> _showDeleteDialog(BuildContext context, Asset asset) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('删除资产', style: TextStyle(color: AppColors.text)),
        content: Text(
          '确定要删除"${asset.name}"吗？',
          style: const TextStyle(color: AppColors.textSecondary),
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
                final file = File(asset.imagePath);
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (e) {
                debugPrint('Error deleting file: $e');
              }
              ref.read(assetProvider.notifier).deleteAsset(asset.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

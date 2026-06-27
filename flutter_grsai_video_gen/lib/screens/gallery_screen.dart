import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:file_picker/file_picker.dart';
import '../constants/app_colors.dart';
import '../providers/gallery_provider.dart';
import '../providers/favorite_provider.dart';
import '../providers/video_gallery_provider.dart';
import '../models/favorite_image.dart';
import '../models/video_item.dart';
import '../widgets/image_viewer_dialog.dart';
import '../widgets/quick_i2v_dialog.dart';
import '../widgets/video_player_widget.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen>
    with SingleTickerProviderStateMixin {
  String _sortOrder = 'desc';
  double _thumbnailSize = 4.0;
  late TabController _tabController;

  // 多选相关
  bool _multiSelectMode = false;
  final Set<int> _selectedIndices = {};
  int? _lastClickedIndex;

  // 收藏页排序
  String _favSortOrder = 'desc';
  String _videoSortOrder = 'desc';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedIndices.clear();
          _lastClickedIndex = null;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(galleryImagesProvider.notifier).loadImages();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 打开全屏图片浏览
  void _openImageViewer(String imagePath, List<String> allPaths, int index) {
    showDialog(
      context: context,
      builder: (context) => ImageViewerDialog(
        imageUrl: imagePath,
        imageUrls: allPaths,
        initialIndex: index,
      ),
    );
  }

  void _handleTap(
    int index, {
    List<String>? allImagePaths,
    String? currentPath,
  }) {
    if (!_multiSelectMode) {
      // 非多选模式：单击 = 全屏浏览
      if (allImagePaths != null && currentPath != null) {
        _openImageViewer(currentPath, allImagePaths, index);
      }
      return;
    }

    // 多选模式
    final isShiftPressed =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );

    setState(() {
      if (isShiftPressed && _lastClickedIndex != null) {
        // Shift+点击：从锚点到当前点的区间
        // 先清除之前的选择，重新选择锚点到当前点的区间
        _selectedIndices.clear();
        final start = _lastClickedIndex! < index ? _lastClickedIndex! : index;
        final end = _lastClickedIndex! > index ? _lastClickedIndex! : index;
        for (int i = start; i <= end; i++) {
          _selectedIndices.add(i);
        }
        // 不更新 _lastClickedIndex，保持锚点不变
      } else {
        // 普通点击：切换单张选中
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
        _lastClickedIndex = index;
      }
    });
  }

  Future<void> _copyImageToClipboard(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final item = DataWriterItem();
        item.add(Formats.png(bytes));
        await clipboard.write([item]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制图片到剪贴板'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    }
  }

  Future<void> _downloadImages(List<String> paths) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存文件夹',
    );
    if (result == null) return;

    int count = 0;
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) {
        final filename = path.split(Platform.pathSeparator).last;
        final targetPath = '$result${Platform.pathSeparator}$filename';
        // 避免覆盖同名文件
        final target = File(targetPath);
        if (await target.exists()) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final ext = filename.contains('.')
              ? '.${filename.split('.').last}'
              : '';
          final name = filename.contains('.')
              ? filename.substring(0, filename.lastIndexOf('.'))
              : filename;
          await file.copy('$result${Platform.pathSeparator}${name}_$ts$ext');
        } else {
          await file.copy(targetPath);
        }
        count++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已下载 $count 张图片到: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteImages(List<String> filenames) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text(
          '确定要删除 ${filenames.length} 张图片吗？',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    for (final filename in filenames) {
      await ref.read(galleryImagesProvider.notifier).deleteImage(filename);
    }
    setState(() {
      _selectedIndices.clear();
      _lastClickedIndex = null;
    });
  }

  Future<void> _copyPromptToClipboard(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该作品暂无可复制的提示词'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制提示词到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _showImagePromptDialog(_ImageItem item) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('生成提示词', style: TextStyle(color: AppColors.text)),
        content: SizedBox(
          width: 560,
          child: item.prompt.trim().isEmpty
              ? const Text(
                  '当前作品暂无已保存的提示词信息。',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.6),
                )
              : SingleChildScrollView(
                  child: SelectableText(
                    item.prompt,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          if (item.prompt.trim().isNotEmpty)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _copyPromptToClipboard(item.prompt);
              },
              child: const Text('复制提示词'),
            ),
        ],
      ),
    );
  }

  Future<void> _addToFavorites(List<_ImageItem> items) async {
    int count = 0;
    for (final item in items) {
      final favorite = FavoriteImage(
        url: item.path,
        prompt: item.prompt,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await ref.read(favoritesProvider.notifier).addFavorite(favorite);
      count++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已收藏 $count 张图片'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
    setState(() {
      _selectedIndices.clear();
      _lastClickedIndex = null;
    });
  }

  Future<void> _removeFromFavorites(List<String> urls) async {
    for (final url in urls) {
      await ref.read(favoritesProvider.notifier).removeFavorite(url);
    }
    setState(() {
      _selectedIndices.clear();
      _lastClickedIndex = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已取消收藏 ${urls.length} 张图片'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _showContextMenu(
    Offset position, {
    required bool isFavTab,
    required List<_ImageItem> items,
  }) async {
    final action = await showMenu<String>(
      context: context,
      color: AppColors.sidebar,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (items.length == 1)
          const PopupMenuItem(value: 'generate_video', child: Text('生成视频')),
        if (items.length == 1)
          const PopupMenuItem(value: 'show_prompt', child: Text('查看提示词')),
        if (items.length == 1)
          const PopupMenuItem(value: 'copy_prompt', child: Text('复制提示词')),
        if (!isFavTab)
          const PopupMenuItem(value: 'favorite', child: Text('收藏')),
        if (isFavTab)
          const PopupMenuItem(value: 'unfavorite', child: Text('取消收藏')),
        const PopupMenuItem(value: 'download', child: Text('下载')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'generate_video':
        await showDialog<void>(
          context: context,
          builder: (_) => QuickI2VDialog(imagePath: items.first.path),
        );
        break;
      case 'show_prompt':
        await _showImagePromptDialog(items.first);
        break;
      case 'copy_prompt':
        await _copyPromptToClipboard(items.first.prompt);
        break;
      case 'favorite':
        await _addToFavorites(items);
        break;
      case 'unfavorite':
        await _removeFromFavorites(items.map((e) => e.url).toList());
        break;
      case 'download':
        await _downloadImages(items.map((e) => e.path).toList());
        break;
      case 'delete':
        if (isFavTab) {
          await _removeFromFavorites(items.map((e) => e.url).toList());
        } else {
          await _deleteImages(items.map((e) => e.filename).toList());
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 标签页头部
          Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.primary,
                  labelColor: AppColors.text,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(fontSize: 16),
                  tabs: const [
                    Tab(text: '作品管理'),
                    Tab(text: '作品收藏'),
                    Tab(text: '视频作品'),
                  ],
                ),
              ),
              // 缩略图大小和排序控件
              Row(
                children: [
                  const Text(
                    '缩略图大小',
                    style: TextStyle(color: AppColors.text, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: Slider(
                      value: _thumbnailSize,
                      min: 2,
                      max: 6,
                      divisions: 4,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _thumbnailSize = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.inputBg,
                      border: Border.all(color: AppColors.border2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButton<String>(
                      value: _tabController.index == 0
                          ? _sortOrder
                          : _tabController.index == 1
                          ? _favSortOrder
                          : _videoSortOrder,
                      underline: const SizedBox.shrink(),
                      dropdownColor: AppColors.sidebar,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'desc', child: Text('按时间降序')),
                        DropdownMenuItem(value: 'asc', child: Text('按时间升序')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          if (_tabController.index == 0) {
                            _sortOrder = v!;
                            ref
                                .read(galleryImagesProvider.notifier)
                                .sortByTime(v == 'asc');
                          } else if (_tabController.index == 1) {
                            _favSortOrder = v!;
                          } else {
                            _videoSortOrder = v!;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 多选开关
                  if (_tabController.index != 2)
                    InkWell(
                      onTap: () => setState(() {
                        _multiSelectMode = !_multiSelectMode;
                        if (!_multiSelectMode) {
                          _selectedIndices.clear();
                          _lastClickedIndex = null;
                        }
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _multiSelectMode
                              ? AppColors.primary
                              : AppColors.inputBg,
                          border: Border.all(
                            color: _multiSelectMode
                                ? AppColors.primary
                                : AppColors.border2,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checklist,
                              size: 16,
                              color: _multiSelectMode
                                  ? Colors.white
                                  : AppColors.text,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '多选',
                              style: TextStyle(
                                color: _multiSelectMode
                                    ? Colors.white
                                    : AppColors.text,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      ref.read(galleryImagesProvider.notifier).loadImages();
                    },
                    icon: const Icon(Icons.refresh, color: AppColors.text),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF3a3a3a),
                      padding: const EdgeInsets.all(8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    tooltip: '刷新',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 多选提示栏
          if (_selectedIndices.isNotEmpty && _tabController.index != 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Text(
                    '已选中 ${_selectedIndices.length} 张图片',
                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedIndices.clear();
                      _lastClickedIndex = null;
                    }),
                    child: const Text(
                      '取消选择',
                      style: TextStyle(color: AppColors.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // 标签页内容
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGalleryTab(),
                _buildFavoritesTab(),
                _buildVideoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryTab() {
    final images = ref.watch(galleryImagesProvider);

    if (images.isEmpty) {
      return const Center(
        child: Text('暂无作品', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Stack(
      children: [
        GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: (8 - _thumbnailSize).toInt(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: images.length,
          itemBuilder: (context, index) {
            final img = images[index];
            final isSelected = _selectedIndices.contains(index);
            final favorites = ref.watch(favoritesProvider);
            final isFavorited = favorites.any(
              (fav) => fav.url.contains(img.filename),
            );

            return GestureDetector(
              onTap: () => _handleTap(
                index,
                allImagePaths: images.map((e) => e.path).toList(),
                currentPath: img.path,
              ),
              onSecondaryTapDown: (details) {
                // 右键点击：如果当前图片不在选中集合中，则单选它
                if (!_selectedIndices.contains(index)) {
                  setState(() {
                    _selectedIndices.clear();
                    _selectedIndices.add(index);
                    _lastClickedIndex = index;
                  });
                }
                // 构建选中的图片列表
                final selectedItems = _selectedIndices.map((i) {
                  final im = images[i];
                  return _ImageItem(
                    filename: im.filename,
                    path: im.path,
                    url: im.url,
                    prompt: im.prompt,
                  );
                }).toList();
                _showContextMenu(
                  details.globalPosition,
                  isFavTab: false,
                  items: selectedItems,
                );
              },
              child: Stack(
                children: [
                  // 图片
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(img.path),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey,
                          child: const Icon(Icons.error, color: Colors.white),
                        );
                      },
                    ),
                  ),
                  // 选中遮罩
                  if (isSelected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 3,
                          ),
                          color: AppColors.primary.withOpacity(0.15),
                        ),
                      ),
                    ),
                  if (img.prompt.trim().isNotEmpty)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 48,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.58),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            img.prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // 右下角悬浮按钮：收藏、查看提示词、复制提示词、复制图片、删除
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _floatingButton(
                          icon: isFavorited
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: isFavorited ? Colors.red : Colors.white,
                          tooltip: isFavorited ? '取消收藏' : '收藏',
                          onTap: () {
                            if (isFavorited) {
                              final fav = favorites.firstWhere(
                                (f) => f.url.contains(img.filename),
                              );
                              ref
                                  .read(favoritesProvider.notifier)
                                  .removeFavorite(fav.url);
                            } else {
                              final favorite = FavoriteImage(
                                url: img.path,
                                prompt: img.prompt,
                                timestamp:
                                    DateTime.now().millisecondsSinceEpoch,
                              );
                              ref
                                  .read(favoritesProvider.notifier)
                                  .addFavorite(favorite);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        _floatingButton(
                          icon: Icons.text_snippet_outlined,
                          color: Colors.white,
                          tooltip: '查看提示词',
                          onTap: () => _showImagePromptDialog(
                            _ImageItem(
                              filename: img.filename,
                              path: img.path,
                              url: img.url,
                              prompt: img.prompt,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _floatingButton(
                          icon: Icons.content_copy,
                          color: Colors.white,
                          tooltip: '复制提示词',
                          onTap: () => _copyPromptToClipboard(img.prompt),
                        ),
                        const SizedBox(width: 4),
                        _floatingButton(
                          icon: Icons.copy,
                          color: Colors.white,
                          tooltip: '复制',
                          onTap: () => _copyImageToClipboard(img.path),
                        ),
                        const SizedBox(width: 4),
                        _floatingButton(
                          icon: Icons.delete,
                          color: Colors.white,
                          tooltip: '删除',
                          onTap: () => _deleteImages([img.filename]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // 打开作品目录按钮
        Positioned(
          right: 0,
          bottom: 0,
          child: ElevatedButton.icon(
            onPressed: () async {
              final exePath = Platform.resolvedExecutable;
              final appDir = File(exePath).parent.path;
              final outputDir = '$appDir\\data\\output';
              await Process.run('explorer', [outputDir]);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3a3a3a),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            icon: const Icon(Icons.folder_open, color: Colors.white),
            label: const Text('打开作品目录', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesTab() {
    final favorites = ref.watch(favoritesProvider);

    // 排序
    final sorted = [...favorites];
    if (_favSortOrder == 'asc') {
      sorted.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } else {
      sorted.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    if (sorted.isEmpty) {
      return const Center(
        child: Text('暂无收藏', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (8 - _thumbnailSize).toInt(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final fav = sorted[index];
        final isSelected = _selectedIndices.contains(index);

        return GestureDetector(
          onTap: () => _handleTap(
            index,
            allImagePaths: sorted.map((e) => e.url).toList(),
            currentPath: fav.url,
          ),
          onSecondaryTapDown: (details) {
            if (!_selectedIndices.contains(index)) {
              setState(() {
                _selectedIndices.clear();
                _selectedIndices.add(index);
                _lastClickedIndex = index;
              });
            }
            final selectedItems = _selectedIndices.map((i) {
              final f = sorted[i];
              final fname = f.url.split(Platform.pathSeparator).last;
              return _ImageItem(
                filename: fname,
                path: f.url,
                url: f.url,
                prompt: f.prompt,
              );
            }).toList();
            _showContextMenu(
              details.globalPosition,
              isFavTab: true,
              items: selectedItems,
            );
          },
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(fav.url),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey,
                      child: const Icon(Icons.error, color: Colors.white),
                    );
                  },
                ),
              ),
              if (isSelected)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary, width: 3),
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                ),
              if (fav.prompt.trim().isNotEmpty)
                Positioned(
                  left: 8,
                  right: 52,
                  bottom: 8,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.58),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        fav.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              // 右上角红心（实心，点击取消收藏）
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: () {
                    ref
                        .read(favoritesProvider.notifier)
                        .removeFavorite(fav.url);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                ),
              ),
              // 右下角悬浮按钮
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _floatingButton(
                      icon: Icons.text_snippet_outlined,
                      color: Colors.white,
                      tooltip: '查看提示词',
                      onTap: () => _showImagePromptDialog(
                        _ImageItem(
                          filename: fav.url.split(Platform.pathSeparator).last,
                          path: fav.url,
                          url: fav.url,
                          prompt: fav.prompt,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    _floatingButton(
                      icon: Icons.content_copy,
                      color: Colors.white,
                      tooltip: '复制提示词',
                      onTap: () => _copyPromptToClipboard(fav.prompt),
                    ),
                    const SizedBox(width: 4),
                    _floatingButton(
                      icon: Icons.copy,
                      color: Colors.white,
                      tooltip: '复制',
                      onTap: () => _copyImageToClipboard(fav.url),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoTab() {
    final videos = [...ref.watch(videoGalleryProvider)];
    if (_videoSortOrder == 'asc') {
      videos.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      videos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    if (videos.isEmpty) {
      return const Center(
        child: Text('暂无视频作品', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (8 - _thumbnailSize).toInt(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.88,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        final thumbExists =
            video.thumbnailPath != null &&
            File(video.thumbnailPath!).existsSync();
        final videoExists = File(video.localPath).existsSync();

        return GestureDetector(
          onTap: () => _showVideoPreviewDialog(video),
          onSecondaryTapDown: (details) {
            _showVideoContextMenu(details.globalPosition, video);
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.sidebar,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border2),
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                    child: thumbExists
                        ? Image.file(
                            File(video.thumbnailPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: Icon(
                              videoExists
                                  ? Icons.movie_creation_outlined
                                  : Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 36,
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              video.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: videoExists
                                ? () => openFullscreenVideo(
                                    context,
                                    video.localPath,
                                  )
                                : null,
                            icon: const Icon(Icons.fullscreen, size: 18),
                            color: AppColors.text,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${video.type.name.toUpperCase()} · ${video.resolution}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        video.prompt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
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

  Future<void> _showVideoPreviewDialog(VideoItem video) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.sidebar,
        child: SizedBox(
          width: 980,
          height: 680,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        video.fileName,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: AppColors.text),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: VideoPlayerWidget(
                        filePath: video.localPath,
                        autoPlay: false,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: AppColors.border2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '提示词',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  video.prompt,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: video.prompt),
                                  ),
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text('复制提示词'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => openFullscreenVideo(
                                    context,
                                    video.localPath,
                                  ),
                                  icon: const Icon(Icons.fullscreen, size: 16),
                                  label: const Text('全屏播放'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVideoContextMenu(Offset position, VideoItem video) async {
    final action = await showMenu<String>(
      context: context,
      color: AppColors.sidebar,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'play', child: Text('播放')),
        const PopupMenuItem(value: 'fullscreen', child: Text('全屏播放')),
        PopupMenuItem(
          value: 'favorite',
          child: Text(video.isFavorite ? '取消收藏' : '收藏'),
        ),
        const PopupMenuItem(value: 'copy_prompt', child: Text('复制提示词')),
        const PopupMenuItem(value: 'open_dir', child: Text('打开目录')),
        const PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'play':
        await _showVideoPreviewDialog(video);
        break;
      case 'fullscreen':
        openFullscreenVideo(context, video.localPath);
        break;
      case 'favorite':
        await ref.read(videoGalleryProvider.notifier).toggleFavorite(video.id);
        if (mounted) setState(() {});
        break;
      case 'copy_prompt':
        await Clipboard.setData(ClipboardData(text: video.prompt));
        break;
      case 'open_dir':
        await Process.run('explorer', [File(video.localPath).parent.path]);
        break;
      case 'delete':
        await ref.read(videoGalleryProvider.notifier).deleteVideo(video.id);
        break;
    }
  }

  Widget _floatingButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            color: onTap == null ? Colors.grey : color,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// 内部辅助类，用于右键菜单传递图片信息
class _ImageItem {
  final String filename;
  final String path;
  final String url;
  final String prompt;

  _ImageItem({
    required this.filename,
    required this.path,
    required this.url,
    this.prompt = '',
  });
}

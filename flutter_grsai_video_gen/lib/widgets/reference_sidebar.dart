import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../constants/app_colors.dart';
import '../constants/app_sizes.dart';
import '../providers/image_provider.dart';
import '../providers/gallery_provider.dart';
import '../providers/ai_assistant_provider.dart';
import '../models/uploaded_image.dart';
import '../models/ai_assistant_message.dart';
import '../utils/reference_image_file_name.dart';
import 'repaint_editor.dart';

class ReferenceSidebar extends ConsumerStatefulWidget {
  final TextEditingController? promptController;
  final void Function(
    String prompt,
    String imagePath, {
    Uint8List? croppedBytes,
  })?
  onRepaintGenerate;

  const ReferenceSidebar({
    super.key,
    this.promptController,
    this.onRepaintGenerate,
  });

  @override
  ConsumerState<ReferenceSidebar> createState() => _ReferenceSidebarState();
}

class _ReferenceSidebarState extends ConsumerState<ReferenceSidebar>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(galleryImagesProvider.notifier).loadImages();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _addImageToReference(String path) async {
    final file = File(path);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      final fileName = displayFileNameFromPath(file.path);

      final existingImages = ref.read(uploadedImagesProvider);
      final existing = existingImages.where((img) => img.name == fileName);
      if (existing.isNotEmpty) {
        final image = existing.first;
        ref.read(selectedImagesProvider.notifier).addImage(image);
        if (ref.read(aiAssistantProvider).isActive) {
          ref.read(aiAssistantProvider.notifier).registerReferenceImage(image);
        }
        return; // Already exists
      }

      // 复制到 data/input 目录，避免引用原始文件（防止删除参考图时误删作品）
      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;
      final inputDir = Directory('$appDir/data/input');
      await inputDir.create(recursive: true);
      final targetPath = p.join(inputDir.path, fileName);
      if (path != targetPath) {
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
      if (ref.read(aiAssistantProvider).isActive) {
        ref.read(aiAssistantProvider.notifier).registerReferenceImage(image);
      }
    }
  }

  Future<void> _handleReferenceImageClick(UploadedImage image) async {
    final aiState = ref.read(aiAssistantProvider);
    final aiNotifier = ref.read(aiAssistantProvider.notifier);

    // AI助手模式：点击右侧参考图直接发送给AI分析
    if (aiState.isActive) {
      if (aiState.isProcessing || aiState.phase == AssistantPhase.generating) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI助手正在处理上一条消息，请稍候')));
        return;
      }

      ref.read(selectedImagesProvider.notifier).addImage(image);
      aiNotifier.registerReferenceImage(image);
      await aiNotifier.sendImage(
        image.base64,
        image.name,
        imagePath: image.path,
        imageId: image.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已选中参考图并发送给AI助手解析')));
      return;
    }

    // 非AI模式保持原行为：加入已选参考图
    ref.read(selectedImagesProvider.notifier).addImage(image);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.sidebarWidth,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: '参考图片'),
              Tab(text: '作品管理'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildReferenceTab(), _buildGalleryTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferenceTab() {
    final images = ref.watch(uploadedImagesProvider);

    return Column(
      children: [
        Expanded(
          child: DropTarget(
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

              final exePath = Platform.resolvedExecutable;
              final appDir = File(exePath).parent.path;
              final inputDir = Directory('$appDir/data/input');
              await inputDir.create(recursive: true);

              for (final xFile in files) {
                final file = File(xFile.path);
                if (await file.exists()) {
                  final bytes = await file.readAsBytes();
                  final originalFileName = displayFileNameFromPath(file.path);
                  final targetFileName = buildReferenceCopyFileName(
                    originalFileName,
                    DateTime.now().millisecondsSinceEpoch,
                  );
                  final targetPath = p.join(inputDir.path, targetFileName);
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
                    ref
                        .read(aiAssistantProvider.notifier)
                        .registerReferenceImage(image);
                  }
                }
              }
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final image = images[index];
                return InkWell(
                  onTap: () => _handleReferenceImageClick(image),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.transparent, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          Image.memory(
                            image.bytes,
                            width: double.infinity,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              color: Colors.black.withValues(alpha: 0.7),
                              child: Text(
                                image.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 5,
                            right: 5,
                            child: InkWell(
                              onTap: () => ref
                                  .read(uploadedImagesProvider.notifier)
                                  .removeImage(image.id),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          if (widget.onRepaintGenerate != null)
                            Positioned(
                              bottom: 28,
                              right: 5,
                              child: InkWell(
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => RepaintEditor(
                                      imagePath: image.path,
                                      onGenerate: widget.onRepaintGenerate!,
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_fix_high,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        '重绘',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final images = await ref
                        .read(uploadedImagesProvider.notifier)
                        .uploadImages();
                    for (final image in images) {
                      ref.read(selectedImagesProvider.notifier).addImage(image);
                      if (ref.read(aiAssistantProvider).isActive) {
                        ref
                            .read(aiAssistantProvider.notifier)
                            .registerReferenceImage(image);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3a3a3a),
                    foregroundColor: AppColors.text,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: AppColors.border2),
                  ),
                  child: const Text('上传图片', style: TextStyle(fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      ref.read(uploadedImagesProvider.notifier).clearImages(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3a3a3a),
                    foregroundColor: AppColors.text,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: AppColors.border2),
                  ),
                  child: const Text('清空图片', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryTab() {
    final galleryImages = ref.watch(galleryImagesProvider);

    if (galleryImages.isEmpty) {
      return const Center(
        child: Text('暂无作品', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: galleryImages.length,
      itemBuilder: (context, index) {
        final img = galleryImages[index];
        return Draggable<String>(
          data: img.path,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(File(img.path), fit: BoxFit.cover),
              ),
            ),
          ),
          child: InkWell(
            onTap: () => _addImageToReference(img.path),
            child: Stack(
              children: [
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
                if (widget.onRepaintGenerate != null)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => RepaintEditor(
                            imagePath: img.path,
                            onGenerate: widget.onRepaintGenerate!,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_fix_high,
                              color: Colors.white,
                              size: 12,
                            ),
                            SizedBox(width: 2),
                            Text(
                              '重绘',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

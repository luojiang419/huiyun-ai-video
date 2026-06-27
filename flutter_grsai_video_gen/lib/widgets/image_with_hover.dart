import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_clipboard/super_clipboard.dart';
import '../providers/image_provider.dart';
import '../providers/favorite_provider.dart';
import '../providers/session_provider.dart';
import '../services/file_service.dart';
import '../models/uploaded_image.dart';
import '../models/favorite_image.dart';
import 'ai_result_action_toolbar.dart';
import 'quick_i2v_dialog.dart';
import 'repaint_editor.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

class ImageWithHover extends ConsumerStatefulWidget {
  final String imagePath;
  final VoidCallback onTap;
  final double maxImageWidth;
  final void Function(
    String prompt,
    String imagePath, {
    Uint8List? croppedBytes,
  })?
  onRepaintGenerate;
  final void Function(String prompt, String imagePath)? onRepaintReturnToInput;
  final Future<void> Function(String imagePath)? onSetReferenceToInput;
  final Future<void> Function(String imagePath)? onContinueEdit;
  final Future<void> Function(String imagePath)? onGenerateSimilar;

  const ImageWithHover({
    super.key,
    required this.imagePath,
    required this.onTap,
    this.maxImageWidth = 330,
    this.onRepaintGenerate,
    this.onRepaintReturnToInput,
    this.onSetReferenceToInput,
    this.onContinueEdit,
    this.onGenerateSimilar,
  });

  @override
  ConsumerState<ImageWithHover> createState() => _ImageWithHoverState();
}

class _ImageWithHoverState extends ConsumerState<ImageWithHover> {
  bool _isHovering = false;

  String _getAbsolutePath(String path) {
    if (path.startsWith('data/')) {
      final fileService = FileService();
      return '${fileService.getAppDirectory()}/$path';
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Stack(
        children: [
          InkWell(
            onTap: widget.onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: BoxConstraints(maxWidth: widget.maxImageWidth),
                child: Image.file(
                  File(_getAbsolutePath(widget.imagePath)),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: widget.maxImageWidth,
                      height: widget.maxImageWidth * 0.7,
                      color: Colors.grey,
                      child: const Icon(Icons.error, color: Colors.white),
                    );
                  },
                ),
              ),
            ),
          ),
          if (_isHovering)
            Positioned(
              right: 8,
              bottom: 8,
              child: Consumer(
                builder: (context, ref, child) {
                  final absolutePath = _getAbsolutePath(widget.imagePath);
                  final favorites = ref.watch(favoritesProvider);
                  final isFavorited = favorites.any(
                    (fav) => fav.url == absolutePath,
                  );
                  return AiResultActionToolbar(
                    actions: [
                      AiResultAction(
                        label: '重绘',
                        icon: Icons.brush_outlined,
                        onPressed: widget.onRepaintGenerate == null
                            ? null
                            : () {
                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (ctx) => RepaintEditor(
                                    imagePath: absolutePath,
                                    onGenerate: widget.onRepaintGenerate!,
                                    onReturnToInput:
                                        widget.onRepaintReturnToInput,
                                  ),
                                );
                              },
                      ),
                      AiResultAction(
                        label: '设为参考',
                        icon: Icons.add_photo_alternate_outlined,
                        isPrimary: true,
                        onPressed: () async {
                          if (widget.onSetReferenceToInput != null) {
                            await widget.onSetReferenceToInput!(absolutePath);
                            return;
                          }
                          await _addImageToReferences(absolutePath);
                        },
                      ),
                      AiResultAction(
                        label: '继续修改',
                        icon: Icons.tune_outlined,
                        onPressed: widget.onContinueEdit == null
                            ? null
                            : () => widget.onContinueEdit!(absolutePath),
                      ),
                      AiResultAction(
                        label: '同风格再来',
                        icon: Icons.auto_awesome_motion_outlined,
                        onPressed: widget.onGenerateSimilar == null
                            ? null
                            : () => widget.onGenerateSimilar!(absolutePath),
                      ),
                      AiResultAction(
                        label: '图生视频',
                        icon: Icons.movie_creation_outlined,
                        onPressed: () async {
                          if (!mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (_) =>
                                QuickI2VDialog(imagePath: absolutePath),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已打开快捷图生视频面板'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                      AiResultAction(
                        label: '复制图片',
                        icon: Icons.copy_outlined,
                        onPressed: () => _copyImage(absolutePath),
                      ),
                      AiResultAction(
                        label: isFavorited ? '已收藏' : '收藏',
                        icon: isFavorited
                            ? Icons.favorite
                            : Icons.favorite_border,
                        onPressed: isFavorited
                            ? null
                            : () async {
                                final favorite = FavoriteImage(
                                  url: absolutePath,
                                  prompt: '',
                                  timestamp:
                                      DateTime.now().millisecondsSinceEpoch,
                                );
                                await ref
                                    .read(favoritesProvider.notifier)
                                    .addFavorite(favorite);
                              },
                      ),
                      AiResultAction(
                        label: '下载',
                        icon: Icons.download_outlined,
                        onPressed: () => _downloadImage(absolutePath),
                      ),
                      AiResultAction(
                        label: '删除',
                        icon: Icons.delete_outline,
                        isDanger: true,
                        onPressed: () => _deleteImage(absolutePath),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addImageToReferences(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final fileService = FileService();
    final appDir = fileService.getAppDirectory();
    final inputDir = Directory('$appDir/data/input');
    await inputDir.create(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final newFileName = 'ref_$timestamp.png';
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
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已添加到参考图')));
  }

  Future<void> _copyImage(String absolutePath) async {
    final file = File(absolutePath);
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

  Future<void> _downloadImage(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return;
    final savedPath = await FileService().saveImageWithDialog(absolutePath);
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存到: $savedPath')));
  }

  Future<void> _deleteImage(String absolutePath) async {
    final file = File(absolutePath);
    if (await file.exists()) {
      await file.delete();
    }
    if (!mounted) return;
    ref
        .read(currentSessionProvider.notifier)
        .removeImageFromMessages(widget.imagePath);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除图片')));
  }
}

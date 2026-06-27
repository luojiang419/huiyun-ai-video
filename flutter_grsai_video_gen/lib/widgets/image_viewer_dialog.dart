import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

class ImageViewerDialog extends StatefulWidget {
  final String imageUrl;
  final List<String>? imageUrls;
  final int? initialIndex;

  const ImageViewerDialog({
    super.key,
    required this.imageUrl,
    this.imageUrls,
    this.initialIndex,
  });

  @override
  State<ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<ImageViewerDialog> {
  late int _currentIndex;
  late PageController _pageController;
  late PhotoViewController _photoViewController;
  final Map<int, PhotoViewController> _galleryControllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);
    _photoViewController = PhotoViewController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _photoViewController.dispose();
    for (var controller in _galleryControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _previousImage();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _nextImage();
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.pop(context);
      }
    }
  }

  void _previousImage() {
    if (widget.imageUrls != null && _currentIndex > 0) {
      setState(() => _currentIndex--);
      _pageController.animateToPage(_currentIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _nextImage() {
    if (widget.imageUrls != null && _currentIndex < widget.imageUrls!.length - 1) {
      setState(() => _currentIndex++);
      _pageController.animateToPage(_currentIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  String _getAbsolutePath(String path) {
    if (path.startsWith('data/')) {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      return '$exeDir/$path';
    }
    return path;
  }

  ImageProvider _getImageProvider(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return NetworkImage(url);
    } else {
      final absolutePath = _getAbsolutePath(url);
      return FileImage(File(absolutePath));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty)
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final controller = _galleryControllers[_currentIndex];
                    if (controller != null) {
                      final scale = controller.scale ?? 1.0;
                      // 向上滚动(dy < 0)是放大，向下滚动(dy > 0)是缩小
                      // 步进系数改为 1.05 / 0.95 实现更平滑的无级缩放感
                      final newScale = event.scrollDelta.dy < 0 ? scale * 1.05 : scale * 0.95;
                      // 扩大缩放范围：0.1倍到20倍，几近无限制
                      controller.scale = newScale.clamp(0.1, 20.0);
                    }
                  }
                },
                child: PhotoViewGallery.builder(
                  scrollPhysics: const BouncingScrollPhysics(),
                  builder: (context, index) {
                    _galleryControllers.putIfAbsent(index, () => PhotoViewController());
                    return PhotoViewGalleryPageOptions(
                      controller: _galleryControllers[index],
                      imageProvider: _getImageProvider(widget.imageUrls![index]),
                      minScale: PhotoViewComputedScale.contained * 0.1, // 允许缩得很小
                      maxScale: PhotoViewComputedScale.covered * 20,    // 允许放得很大
                    );
                  },
                  itemCount: widget.imageUrls!.length,
                  loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  pageController: _pageController,
                  onPageChanged: (index) => setState(() => _currentIndex = index),
                ),
              )
            else
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final scale = _photoViewController.scale ?? 1.0;
                    // 向上滚动(dy < 0)是放大，向下滚动(dy > 0)是缩小
                    final newScale = event.scrollDelta.dy < 0 ? scale * 1.05 : scale * 0.95;
                    _photoViewController.scale = newScale.clamp(0.1, 20.0);
                  }
                },
                child: PhotoView(
                  controller: _photoViewController,
                  imageProvider: _getImageProvider(widget.imageUrl),
                  minScale: PhotoViewComputedScale.contained * 0.1,
                  maxScale: PhotoViewComputedScale.covered * 20,
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  enableRotation: true,
                ),
              ),
          if (widget.imageUrls != null && widget.imageUrls!.length > 1) ...[
            Positioned(
              left: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 32),
                  onPressed: _currentIndex > 0 ? _previousImage : null,
                ),
              ),
            ),
            Positioned(
              right: 20,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 32),
                  onPressed: _currentIndex < widget.imageUrls!.length - 1 ? _nextImage : null,
                ),
              ),
            ),
          ],
          Positioned(
            top: 20,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/session_provider.dart';
import '../widgets/image_viewer_dialog.dart';

class SessionGalleryDialog extends ConsumerWidget {
  const SessionGalleryDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final allImages = <String>[];

    if (session != null) {
      for (final msg in session.messages) {
        if (msg.type == 'assistant') {
          allImages.addAll(msg.images);
        }
      }
    }

    return Dialog(
      backgroundColor: AppColors.sidebar,
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  '会话图片管理',
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w500),
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
              child: allImages.isEmpty
                  ? const Center(
                      child: Text('当前会话暂无图片', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: allImages.length,
                      itemBuilder: (context, index) {
                        final imagePath = allImages[index];
                        return InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => ImageViewerDialog(
                                imageUrl: imagePath,
                                imageUrls: allImages,
                                initialIndex: index,
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey,
                                child: const Icon(Icons.error, color: Colors.white),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

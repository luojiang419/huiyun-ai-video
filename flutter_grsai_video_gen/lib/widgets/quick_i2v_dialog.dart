import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../screens/video_generate_screen.dart';

class QuickI2VDialog extends StatelessWidget {
  final String imagePath;
  final String? initialPrompt;

  const QuickI2VDialog({
    super.key,
    required this.imagePath,
    this.initialPrompt,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1080,
        height: 760,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border2)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '快捷图生视频',
                      style: TextStyle(color: AppColors.text, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.text),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VideoI2VTab(
                  initialImagePath: imagePath,
                  initialPrompt: initialPrompt,
                  embedded: true,
                  onSubmitted: () {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

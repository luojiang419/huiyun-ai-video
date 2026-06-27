import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/uploaded_image.dart';

class AiCreatorInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Key? textFieldKey;
  final bool aiActive;
  final bool aiBusy;
  final List<UploadedImage> selectedImages;
  final List<String> promptHistory;
  final String? pendingAnglePrompt;
  final List<Widget> parameterControls;
  final List<Widget> footerHints;
  final VoidCallback onSubmit;
  final VoidCallback onUploadReference;
  final VoidCallback onClear;
  final VoidCallback onPolish;
  final VoidCallback? onEditPendingAngle;
  final VoidCallback? onClearPendingAngle;
  final ValueChanged<String> onHistorySelected;
  final ValueChanged<int> onInsertImageToken;
  final ValueChanged<UploadedImage> onRemoveSelectedImage;

  const AiCreatorInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.textFieldKey,
    required this.aiActive,
    required this.aiBusy,
    required this.selectedImages,
    required this.promptHistory,
    this.pendingAnglePrompt,
    required this.parameterControls,
    required this.footerHints,
    required this.onSubmit,
    required this.onUploadReference,
    required this.onClear,
    required this.onPolish,
    required this.onHistorySelected,
    required this.onInsertImageToken,
    required this.onRemoveSelectedImage,
    this.onEditPendingAngle,
    this.onClearPendingAngle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(top: BorderSide(color: AppColors.border1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReferenceStrip(),
          if (promptHistory.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildHistoryStrip(),
          ],
          if (pendingAnglePrompt != null) ...[
            const SizedBox(height: 8),
            _buildPendingAngle(),
          ],
          const SizedBox(height: 8),
          _buildComposer(),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: parameterControls,
                ),
              ),
              const SizedBox(width: 10),
              _iconCommand(
                tooltip: '清空输入框',
                icon: Icons.backspace_outlined,
                onTap: onClear,
              ),
              const SizedBox(width: 6),
              _iconCommand(
                tooltip: 'AI提示词润色',
                icon: Icons.auto_fix_high_outlined,
                onTap: onPolish,
              ),
              const SizedBox(width: 6),
              _primaryCommand(
                label: aiActive ? '发送给AI' : '图片生成',
                icon: aiActive
                    ? Icons.smart_toy_outlined
                    : Icons.image_outlined,
                onTap: aiBusy ? null : onSubmit,
              ),
            ],
          ),
          if (footerHints.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...footerHints,
          ],
        ],
      ),
    );
  }

  Widget _buildReferenceStrip() {
    return Container(
      height: selectedImages.isEmpty ? 48 : 84,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selectedImages.isEmpty
              ? AppColors.border1
              : AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: selectedImages.isEmpty
                  ? AppColors.hover
                  : AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              selectedImages.isEmpty
                  ? Icons.add_photo_alternate_outlined
                  : Icons.collections_outlined,
              color: selectedImages.isEmpty
                  ? AppColors.textSecondary
                  : AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          if (selectedImages.isEmpty)
            const Expanded(
              child: Text(
                '拖入或上传参考图',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: selectedImages.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = selectedImages[index];
                  return _referenceThumb(image, index);
                },
              ),
            ),
          const SizedBox(width: 10),
          _iconCommand(
            tooltip: '上传参考图片',
            icon: Icons.add,
            onTap: onUploadReference,
          ),
        ],
      ),
    );
  }

  Widget _referenceThumb(UploadedImage image, int index) {
    return InkWell(
      onTap: () => onInsertImageToken(index),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 68,
        height: 68,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                image.bytes,
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 68,
                  height: 68,
                  color: AppColors.hover,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '图${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 3,
              top: 3,
              child: InkWell(
                onTap: () => onRemoveSelectedImage(image),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryStrip() {
    return SizedBox(
      height: 28,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: promptHistory.length,
        itemBuilder: (context, index) {
          final history = promptHistory[index];
          return GestureDetector(
            onTap: () => onHistorySelected(history),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border2),
              ),
              child: Text(
                history.length > 22
                    ? '${history.substring(0, 22)}...'
                    : history,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingAngle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.rotate_90_degrees_ccw,
            color: AppColors.primary,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pendingAnglePrompt!,
              style: const TextStyle(color: AppColors.primary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _smallIcon(Icons.edit_outlined, onEditPendingAngle),
          _smallIcon(Icons.close, onClearPendingAngle),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Stack(
      children: [
        TextField(
          key: textFieldKey,
          controller: controller,
          focusNode: focusNode,
          enabled: !aiBusy,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          style: const TextStyle(color: AppColors.text, height: 1.35),
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            hintText: aiActive ? '描述你想怎么续创这张图...' : '输入画面描述，或先上传参考图...',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border2),
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 50, 12),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _iconCommand(
            tooltip: '上传参考图片',
            icon: Icons.add_photo_alternate_outlined,
            onTap: onUploadReference,
          ),
        ),
      ],
    );
  }

  Widget _primaryCommand({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.hover : AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _iconCommand({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.inputBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border2),
          ),
          child: Icon(icon, color: AppColors.text, size: 17),
        ),
      ),
    );
  }

  static Widget _smallIcon(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: AppColors.primary, size: 14),
      ),
    );
  }
}

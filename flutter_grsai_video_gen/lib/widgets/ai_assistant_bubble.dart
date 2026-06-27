import 'dart:io';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/ai_assistant_message.dart';
import 'ai_creation_plan_card.dart';
import 'ai_option_buttons.dart';
import 'ai_result_action_toolbar.dart';

class AiAssistantBubble extends StatelessWidget {
  final AiAssistantMessage message;
  final void Function(AiOption) onOptionTap;
  final VoidCallback? onImageTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final void Function(TapDownDetails, String imagePath)?
  onImageSecondaryTapDown;
  final Future<void> Function(String imagePath)? onSetReference;
  final Future<void> Function(String imagePath)? onContinueEdit;
  final Future<void> Function(String imagePath)? onGenerateSimilar;
  final int? imageIndex;

  const AiAssistantBubble({
    super.key,
    required this.message,
    required this.onOptionTap,
    this.onImageTap,
    this.onSecondaryTapDown,
    this.onImageSecondaryTapDown,
    this.onSetReference,
    this.onContinueEdit,
    this.onGenerateSimilar,
    this.imageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // AI avatar + name
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF3a3a3a)
                        : AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      isUser ? '我' : '🤖',
                      style: TextStyle(
                        color: isUser ? Colors.white : null,
                        fontSize: isUser ? 12 : 16,
                        fontWeight: isUser
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isUser ? '我' : 'AI助手',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (message.matchedSkillName != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '📚 ${message.matchedSkillName}',
                      style: TextStyle(color: AppColors.primary, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),

            // message bubble
            GestureDetector(
              onSecondaryTapDown: onSecondaryTapDown,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isUser
                      ? const Color(0xFF3a3a3a)
                      : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border2.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // text content
                    if (message.text != null && message.text!.isNotEmpty)
                      _buildTextContent(),

                    // polished prompt preview
                    if (message.polishedPrompt != null &&
                        message.polishedPrompt!.isNotEmpty)
                      _buildPromptPreview(),

                    // params display
                    if (message.plan != null) _buildParamsDisplay(),

                    if (message.executionPlan != null)
                      AiCreationPlanCard(executionPlan: message.executionPlan!),

                    // images
                    if (message.images != null && message.images!.isNotEmpty)
                      _buildImages(),

                    // analysis
                    if (message.analysis != null &&
                        message.analysis!.isNotEmpty)
                      _buildAnalysis(),

                    // option buttons
                    if (message.options.isNotEmpty)
                      AiOptionButtons(
                        options: message.options,
                        onOptionTap: onOptionTap,
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

  Widget _buildTextContent() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message.text!,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildPromptPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('✨', style: TextStyle(fontSize: 12)),
              SizedBox(width: 4),
              Text(
                '润色提示词',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message.polishedPrompt!,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.4,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildParamsDisplay() {
    final plan = message.plan!;
    final operation = (plan['operation'] ?? 'image_generate').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _paramChip('操作', _describeOperation(operation)),
          if ((plan['model'] ?? '').toString().isNotEmpty)
            _paramChip('模型', plan['model'] ?? ''),
          if ((plan['videoModelName'] ?? '').toString().isNotEmpty &&
              operation.startsWith('video_'))
            _paramChip('视频模型', plan['videoModelName'] ?? ''),
          if ((plan['aspectRatio'] ?? '').toString().isNotEmpty &&
              !operation.startsWith('video_'))
            _paramChip('比例', plan['aspectRatio'] ?? ''),
          if ((plan['imageSize'] ?? '').toString().isNotEmpty &&
              !operation.startsWith('video_'))
            _paramChip('尺寸', plan['imageSize'] ?? ''),
          if ((plan['videoResolution'] ?? '').toString().isNotEmpty &&
              operation.startsWith('video_'))
            _paramChip('分辨率', plan['videoResolution'] ?? ''),
          if (plan['batchCount'] != null &&
              plan['batchCount'] > 1 &&
              !operation.startsWith('video_'))
            _paramChip('数量', '${plan['batchCount']}'),
        ],
      ),
    );
  }

  String _describeOperation(String operation) {
    switch (operation) {
      case 'image_edit':
        return '图片修改';
      case 'video_t2v':
        return '文生视频';
      case 'video_i2v':
        return '图生视频';
      default:
        return '图片生成';
    }
  }

  Widget _paramChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label：',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildImages() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: message.images!.map((imgPath) {
          return _AiAssistantImageTile(
            imagePath: imgPath,
            onTap: onImageTap,
            onSecondaryTapDown: onImageSecondaryTapDown == null
                ? null
                : (details) => onImageSecondaryTapDown!(details, imgPath),
            onSetReference: onSetReference == null
                ? null
                : () => onSetReference!(imgPath),
            onContinueEdit: onContinueEdit == null
                ? null
                : () => onContinueEdit!(imgPath),
            onGenerateSimilar: onGenerateSimilar == null
                ? null
                : () => onGenerateSimilar!(imgPath),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAnalysis() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📝 AI解析',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message.analysis!,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiAssistantImageTile extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Future<void> Function()? onSetReference;
  final Future<void> Function()? onContinueEdit;
  final Future<void> Function()? onGenerateSimilar;

  const _AiAssistantImageTile({
    required this.imagePath,
    this.onTap,
    this.onSecondaryTapDown,
    this.onSetReference,
    this.onContinueEdit,
    this.onGenerateSimilar,
  });

  @override
  State<_AiAssistantImageTile> createState() => _AiAssistantImageTileState();
}

class _AiAssistantImageTileState extends State<_AiAssistantImageTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(widget.imagePath),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 200,
                  height: 200,
                  color: AppColors.inputBg,
                  child: const Icon(
                    Icons.broken_image,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (_isHovering)
              Positioned(
                right: 6,
                bottom: 6,
                child: AiResultActionToolbar(
                  actions: [
                    AiResultAction(
                      label: '设为参考',
                      icon: Icons.add_photo_alternate_outlined,
                      onPressed: widget.onSetReference,
                      isPrimary: true,
                    ),
                    AiResultAction(
                      label: '继续修改',
                      icon: Icons.tune_outlined,
                      onPressed: widget.onContinueEdit,
                    ),
                    AiResultAction(
                      label: '同风格再来',
                      icon: Icons.auto_awesome_motion_outlined,
                      onPressed: widget.onGenerateSimilar,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class UserMessageBubble extends StatelessWidget {
  final String text;

  const UserMessageBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/ai_assistant_message.dart';

class AiOptionButtons extends StatelessWidget {
  final List<AiOption> options;
  final void Function(AiOption) onOptionTap;

  const AiOptionButtons({
    super.key,
    required this.options,
    required this.onOptionTap,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    // separate tags from buttons
    final tags = options.where((o) => o.type == 'tag').toList();
    final buttons = options.where((o) => o.type != 'tag').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: tags.map((opt) => _buildTag(opt)).toList(),
            ),
          ),
        if (buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: buttons.map((opt) => _buildButton(opt)).toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildTag(AiOption opt) {
    return InkWell(
      onTap: () => onOptionTap(opt),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.inputBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (opt.icon.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(opt.icon, style: const TextStyle(fontSize: 14)),
              ),
            Flexible(
              child: Text(
                opt.label,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(AiOption opt) {
    Color bgColor;
    Color textColor;
    Color borderColor;

    switch (opt.type) {
      case 'primary':
        bgColor = const Color(0xFF2E7D32);
        textColor = Colors.white;
        borderColor = const Color(0xFF2E7D32);
        break;
      case 'danger':
        bgColor = Colors.transparent;
        textColor = const Color(0xFFEF5350);
        borderColor = const Color(0xFFEF5350);
        break;
      default: // secondary
        bgColor = Colors.transparent;
        textColor = AppColors.primary;
        borderColor = AppColors.primary;
    }

    return InkWell(
      onTap: () => onOptionTap(opt),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (opt.icon.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(opt.icon, style: const TextStyle(fontSize: 14)),
              ),
            Flexible(
              child: Text(
                opt.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: opt.type == 'primary'
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

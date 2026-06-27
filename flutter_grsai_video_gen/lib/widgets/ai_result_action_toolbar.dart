import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AiResultAction {
  final String label;
  final IconData icon;
  final FutureOr<void> Function()? onPressed;
  final bool isDanger;
  final bool isPrimary;

  const AiResultAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.isDanger = false,
    this.isPrimary = false,
  });
}

class AiResultActionToolbar extends StatelessWidget {
  final List<AiResultAction> actions;
  final Axis direction;

  const AiResultActionToolbar({
    super.key,
    required this.actions,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final enabledActions = actions.where((action) => action.onPressed != null);
    if (enabledActions.isEmpty) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border2),
      ),
      child: Flex(
        direction: direction,
        mainAxisSize: MainAxisSize.min,
        children: enabledActions
            .map(
              (action) => Tooltip(
                message: action.label,
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  onTap: () async => action.onPressed?.call(),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: action.isPrimary
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      action.icon,
                      size: 16,
                      color: action.isDanger
                          ? const Color(0xFFFF6B6B)
                          : action.isPrimary
                          ? AppColors.primary
                          : AppColors.text,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

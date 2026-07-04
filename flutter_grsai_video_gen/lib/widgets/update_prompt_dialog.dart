import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/pending_update_job.dart';
import '../providers/update_provider.dart';

Future<void> showUpdatePromptDialog({
  required BuildContext context,
  required PendingUpdateJob job,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UpdatePromptDialog(job: job),
  );
}

class UpdatePromptDialog extends ConsumerStatefulWidget {
  final PendingUpdateJob job;

  const UpdatePromptDialog({super.key, required this.job});

  @override
  ConsumerState<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends ConsumerState<UpdatePromptDialog> {
  bool _isSubmitting = false;
  String? _error;

  Future<void> _installNow() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref
          .read(updateProvider.notifier)
          .installPendingUpdate(job: widget.job);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _installOnNextLaunch() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await ref
          .read(updateProvider.notifier)
          .scheduleInstallOnNextLaunch(job: widget.job);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已设置为下次启动时自动安装更新')));
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.job.info;
    final notes = info.releaseNotes.trim().isEmpty
        ? '本次更新未填写详细说明。'
        : info.releaseNotes.trim();

    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: Text(
        '发现新版本 ${info.version}',
        style: const TextStyle(color: AppColors.text),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '安装包大小：${info.sizeLabel}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            const Text(
              '更新说明',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  notes,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            if (widget.job.status == PendingUpdateStatus.failed &&
                widget.job.lastFailureReason.trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                '上次自动安装失败：${widget.job.lastFailureReason}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 18),
              const LinearProgressIndicator(
                backgroundColor: Colors.white12,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              const Text(
                '正在启动安装包，请在弹出的安装向导中完成更新...',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isSubmitting && !info.mandatory)
          TextButton(
            onPressed: _installOnNextLaunch,
            child: const Text('下次启动时更新'),
          ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _installNow,
          child: Text(
            widget.job.status == PendingUpdateStatus.failed ? '重新安装' : '立即更新',
          ),
        ),
      ],
    );
  }
}

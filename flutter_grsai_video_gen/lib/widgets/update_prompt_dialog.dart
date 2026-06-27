import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/update_info.dart';
import '../providers/update_provider.dart';

Future<void> showUpdatePromptDialog({
  required BuildContext context,
  required UpdateInfo info,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (_) => UpdatePromptDialog(info: info),
  );
}

class UpdatePromptDialog extends ConsumerStatefulWidget {
  final UpdateInfo info;

  const UpdatePromptDialog({super.key, required this.info});

  @override
  ConsumerState<UpdatePromptDialog> createState() => _UpdatePromptDialogState();
}

class _UpdatePromptDialogState extends ConsumerState<UpdatePromptDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _skipVersion() async {
    await ref.read(updateProvider.notifier).skipVersion(widget.info.version);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await ref
          .read(updateProvider.notifier)
          .downloadAndInstall(
            widget.info,
            onProgress: (progress) {
              if (mounted) {
                setState(() => _progress = progress);
              }
            },
          );
    } catch (error) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
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
            if (_isDownloading) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: Colors.white12,
                color: AppColors.primary,
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0
                    ? '正在下载 ${(100 * _progress).clamp(0, 100).toStringAsFixed(0)}%'
                    : '正在连接下载服务器',
                style: const TextStyle(color: AppColors.textSecondary),
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
        if (!_isDownloading && !info.mandatory)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        if (!_isDownloading && !info.mandatory)
          TextButton(onPressed: _skipVersion, child: const Text('跳过此版本')),
        ElevatedButton(
          onPressed: _isDownloading ? null : _downloadAndInstall,
          child: Text(_error == null ? '下载并安装' : '重试下载'),
        ),
      ],
    );
  }
}

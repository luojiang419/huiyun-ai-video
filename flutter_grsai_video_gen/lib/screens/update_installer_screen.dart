import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/update_install_session.dart';
import '../providers/update_provider.dart';

class UpdateInstallerApp extends StatelessWidget {
  final UpdateInstallSessionLaunchArgs launchArgs;
  final void Function(int exitCode)? exitHandler;

  const UpdateInstallerApp({
    super.key,
    required this.launchArgs,
    this.exitHandler,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '绘云AI 更新安装器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.primary,
          surface: AppColors.surface,
        ),
      ),
      home: UpdateInstallerScreen(
        launchArgs: launchArgs,
        exitHandler: exitHandler,
      ),
    );
  }
}

class UpdateInstallerScreen extends ConsumerStatefulWidget {
  final UpdateInstallSessionLaunchArgs launchArgs;
  final void Function(int exitCode)? exitHandler;

  const UpdateInstallerScreen({
    super.key,
    required this.launchArgs,
    this.exitHandler,
  });

  @override
  ConsumerState<UpdateInstallerScreen> createState() =>
      _UpdateInstallerScreenState();
}

class _UpdateInstallerScreenState
    extends ConsumerState<UpdateInstallerScreen> {
  UpdateInstallSession? _session;
  String _headline = '正在准备更新';
  String _message = '正在接管更新任务，请勿关闭此窗口。';
  String? _detail;
  bool _isFailed = false;
  bool _isCompleted = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInstallFlow();
    });
  }

  Future<void> _startInstallFlow() async {
    if (_started) {
      return;
    }
    _started = true;

    final updateService = ref.read(updateServiceProvider);
    final initialSession = await updateService.loadInstallSession(
      sessionFilePath: widget.launchArgs.sessionFilePath,
    );
    if (initialSession == null) {
      _showFailure(
        '未找到更新会话文件，请重新下载更新包后再试。',
        null,
      );
      return;
    }
    if (initialSession.sessionId != widget.launchArgs.sessionId) {
      _showFailure(
        '更新会话编号不匹配，已终止本次自动更新。',
        initialSession,
      );
      return;
    }

    if (mounted) {
      setState(() {
        _session = initialSession;
        _headline = _headlineForStatus(initialSession.status);
        _message = '更新程序已就绪，正在开始静默安装。';
        _detail = _buildDetailText(initialSession);
      });
    }

    try {
      await updateService.runDetachedInstallSession(
        sessionFilePath: widget.launchArgs.sessionFilePath,
        expectedSessionId: widget.launchArgs.sessionId,
        onProgress: (session, message) {
          if (!mounted) {
            return;
          }
          setState(() {
            _session = session;
            _headline = _headlineForStatus(session.status);
            _message = message;
            _detail = _buildDetailText(session);
            _isFailed = session.status == UpdateInstallSessionStatus.failed;
          });
        },
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isCompleted = true;
        _headline = '更新完成';
        _message = '新版本正在启动，本窗口即将自动关闭。';
        _detail = _buildDetailText(_session);
      });
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _exitApp(0);
        }
      });
    } catch (error) {
      final latestSession = await updateService.loadInstallSession(
        sessionFilePath: widget.launchArgs.sessionFilePath,
      );
      _showFailure(error.toString(), latestSession ?? _session);
    }
  }

  void _showFailure(String message, UpdateInstallSession? session) {
    if (!mounted) {
      return;
    }
    setState(() {
      _session = session;
      _isFailed = true;
      _isCompleted = false;
      _headline = '更新失败';
      _message = '安装更新失败，请稍后重试。';
      final details = <String>[message];
      final sessionDetails = _buildDetailText(session);
      if (sessionDetails != null && sessionDetails.isNotEmpty) {
        details.add(sessionDetails);
      }
      _detail = details.join('\n\n');
    });
  }

  String _headlineForStatus(UpdateInstallSessionStatus status) {
    switch (status) {
      case UpdateInstallSessionStatus.prepared:
      case UpdateInstallSessionStatus.launching:
        return '正在接管更新';
      case UpdateInstallSessionStatus.installing:
        return '正在安装更新';
      case UpdateInstallSessionStatus.completed:
        return '更新完成';
      case UpdateInstallSessionStatus.failed:
        return '更新失败';
    }
  }

  String? _buildDetailText(UpdateInstallSession? session) {
    if (session == null) {
      return null;
    }
    final lines = <String>[
      '目标版本：${session.targetVersion}',
      '安装目录：${session.installDir}',
    ];
    if (session.logFilePath.isNotEmpty) {
      lines.add('日志文件：${session.logFilePath}');
    }
    return lines.join('\n');
  }

  void _exitApp(int exitCode) {
    final handler = widget.exitHandler;
    if (handler != null) {
      handler(exitCode);
      return;
    }
    exit(exitCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _isFailed
                          ? Colors.redAccent.withValues(alpha: 0.14)
                          : AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _isFailed
                          ? Icons.error_outline
                          : _isCompleted
                          ? Icons.check_circle_outline
                          : Icons.system_update_alt,
                      color: _isFailed ? Colors.redAccent : AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '绘云AI 正在更新',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _headline,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: _isFailed ? 1 : (_isCompleted ? 1 : null),
                  backgroundColor: AppColors.border1,
                  color: _isFailed ? Colors.redAccent : AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _message,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              if (_detail != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border1),
                  ),
                  child: SelectableText(
                    _detail!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
              if (_isFailed || _isCompleted) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _exitApp(_isFailed ? 1 : 0),
                    child: Text(_isFailed ? '关闭窗口' : '立即关闭'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

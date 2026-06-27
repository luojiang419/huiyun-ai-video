import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/session_provider.dart';
import '../services/session_service.dart';

class SessionHistoryDialog extends ConsumerStatefulWidget {
  const SessionHistoryDialog({super.key});

  @override
  ConsumerState<SessionHistoryDialog> createState() => _SessionHistoryDialogState();
}

class _SessionHistoryDialogState extends ConsumerState<SessionHistoryDialog> {
  List<SessionInfo> _sessions = [];
  final Set<String> _selectedSessions = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final service = ref.read(sessionServiceProvider);
    final sessions = await service.getAllSessions();
    sessions.sort((a, b) => b.created.compareTo(a.created));
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.sidebar,
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  '历史会话',
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                if (_selectedSessions.isNotEmpty) ...[
                  TextButton(
                    onPressed: _deleteSelectedSessions,
                    child: Text('删除选中(${_selectedSessions.length})', style: const TextStyle(color: Colors.red)),
                  ),
                  const SizedBox(width: 8),
                ],
                if (_sessions.isNotEmpty)
                  TextButton(
                    onPressed: _clearAllSessions,
                    child: const Text('清空全部', style: TextStyle(color: Colors.red)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.text),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: AppColors.border1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _sessions.isEmpty
                      ? const Center(
                          child: Text('暂无历史会话', style: TextStyle(color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) {
                            final session = _sessions[index];
                            return _buildSessionItem(session);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionItem(SessionInfo session) {
    final isSelected = _selectedSessions.contains(session.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.hover : AppColors.inputBg,
        border: Border.all(color: isSelected ? AppColors.primary : AppColors.border2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Checkbox(
          value: isSelected,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _selectedSessions.add(session.name);
              } else {
                _selectedSessions.remove(session.name);
              }
            });
          },
        ),
        title: Text(session.name, style: const TextStyle(color: AppColors.text)),
        subtitle: Text(
          '${_formatDate(session.created)} · ${session.messageCount}条对话',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.text, size: 18),
              onPressed: () => _showRenameDialog(session),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 18),
              onPressed: () => _deleteSession(session),
            ),
          ],
        ),
        onTap: () {
          ref.read(currentSessionProvider.notifier).loadSession(session.name);
          Navigator.pop(context);
        },
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showRenameDialog(SessionInfo session) async {
    final controller = TextEditingController(text: session.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('重命名会话', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.text),
          decoration: const InputDecoration(
            hintText: '输入新名称',
            hintStyle: TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.inputBg,
            border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != session.name) {
      final service = ref.read(sessionServiceProvider);
      await service.renameSession(session.name, result);
      _loadSessions();
    }
  }

  Future<void> _deleteSession(SessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text('确定要删除会话 "${session.name}" 吗？', style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(currentSessionProvider.notifier).deleteSession(session.name);
      _loadSessions();
    }
  }

  Future<void> _deleteSelectedSessions() async {
    if (_selectedSessions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认删除', style: TextStyle(color: AppColors.text)),
        content: Text('确定要删除选中的 ${_selectedSessions.length} 个会话吗？', style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final name in _selectedSessions) {
        await ref.read(currentSessionProvider.notifier).deleteSession(name);
      }
      _selectedSessions.clear();
      _loadSessions();
    }
  }

  Future<void> _clearAllSessions() async {
    if (_sessions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('确认清空', style: TextStyle(color: AppColors.text)),
        content: Text('确定要清空所有 ${_sessions.length} 个历史会话吗？此操作不可恢复！', style: const TextStyle(color: AppColors.text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final session in _sessions) {
        await ref.read(currentSessionProvider.notifier).deleteSession(session.name);
      }
      _loadSessions();
      if (mounted) Navigator.pop(context);
    }
  }
}

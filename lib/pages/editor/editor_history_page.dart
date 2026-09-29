import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';

part 'editor_history_page_build.dart';

/// 编辑器类型显示名
const _typeLabels = {
  'post': '发帖',
  'comment': '评论',
  'reply': '回复',
  'editPost': '编辑帖子',
  'editReply': '编辑评论',
};

/// 编辑历史记录页 — 统一显示所有会话，按类型分组
///
/// 返回结果：
/// - `{'action': 'restore', 'snapshotId': '...'}` → 恢复指定快照
class EditorHistoryPage extends StatefulWidget {
  final String sessionKey;

  const EditorHistoryPage({super.key, required this.sessionKey});

  @override
  State<EditorHistoryPage> createState() => _EditorHistoryPageState();
}

class _EditorHistoryPageState extends State<EditorHistoryPage> {
  bool _loading = true;
  String? _error;

  /// 所有会话（按时间倒序）
  List<EditorSessionSummary> _sessions = [];

  /// 展开的 sessionKey
  final Set<String> _expandedSessions = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prov = context.read<EditorHistoryProvider>();
      final sessions = await prov.getAllSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });

      // 如果指定了 sessionKey，展开该会话
      if (widget.sessionKey.isNotEmpty) {
        final match = sessions.where((s) => s.key == widget.sessionKey);
        if (match.isNotEmpty) {
          setState(() => _expandedSessions.add(widget.sessionKey));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);

  // ==================== 操作 ====================

  void _restore(EditorSnapshot snapshot) {
    Navigator.of(context).pop({'action': 'restore', 'snapshotId': snapshot.id});
  }

  Future<void> _delete(EditorSnapshot snapshot) async {
    final confirm = await showConfirmDialog(
      context,
      title: '删除快照',
      titleStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      message:
          '确定删除 "${snapshot.title.isNotEmpty ? snapshot.title : formatFullTime(snapshot.createdAt)}" 吗？',
      confirmText: '删除',
      danger: true,
      maxWidth: 360,
    );

    if (confirm == true && context.mounted) {
      await context.read<EditorHistoryProvider>().deleteSnapshot(snapshot.id);
      _load();
      if (mounted) {
        showToast('已删除');
      }
    }
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showConfirmDialog(
      context,
      title: '清空所有历史',
      titleStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      message: '确定要删除所有编辑历史吗？此操作不可撤销。',
      confirmText: '清空',
      danger: true,
      maxWidth: 360,
    );

    if (confirm == true && context.mounted) {
      await context.read<EditorHistoryProvider>().clearAll();
      _load();
      if (mounted) {
        showToast('已清空所有历史');
      }
    }
  }
}

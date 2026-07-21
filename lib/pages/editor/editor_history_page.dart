import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/models/editor_snapshot.dart';

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑历史'),
        surfaceTintColor: cs.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '暂无编辑历史',
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _sessions.length,
      itemBuilder: (_, i) => _buildSessionCard(_sessions[i]),
    );
  }

  // ==================== Session 卡片 ====================

  Widget _buildSessionCard(EditorSessionSummary session) {
    final cs = Theme.of(context).colorScheme;
    final expanded = _expandedSessions.contains(session.key);
    final typeLabel = _typeLabel(session.key);
    final typeIcon = _typeIcon(session.key);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedSessions.remove(session.key);
              } else {
                _expandedSessions.add(session.key);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  typeIcon,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                session.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${session.totalCount} 条记录',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildSnapshotList(session.key),
        ],
      ),
    );
  }

  String _typeLabel(String key) {
    for (final entry in _typeLabels.entries) {
      if (key.startsWith(entry.key)) return entry.value;
    }
    return '其他';
  }

  Widget _typeIcon(String key) {
    final cs = Theme.of(context).colorScheme;
    IconData icon;
    Color color;
    if (key.startsWith('post')) {
      icon = Icons.post_add;
      color = cs.onSurfaceVariant;
    } else if (key.startsWith('comment')) {
      icon = Icons.comment;
      color = cs.onSurfaceVariant;
    } else if (key.startsWith('reply')) {
      icon = Icons.reply;
      color = cs.onSurfaceVariant;
    } else if (key.startsWith('editPost') || key.startsWith('editReply')) {
      icon = Icons.edit;
      color = cs.onSurfaceVariant;
    } else {
      icon = Icons.description;
      color = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  // ==================== Snapshot 列表 ====================

  Widget _buildSnapshotList(String sessionKey) {
    final prov = context.read<EditorHistoryProvider>();
    final all = prov.getAllSnapshots(sessionKey);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: all.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 8),
      itemBuilder: (_, i) => _buildSnapshotTile(all[i]),
    );
  }

  Widget _buildSnapshotTile(EditorSnapshot snapshot) {
    final cs = Theme.of(context).colorScheme;
    final timeStr = _formatTime(snapshot.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // 时间 + 标签
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              if (snapshot.isManual)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    '手动',
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.title.isNotEmpty)
                  Text(
                    snapshot.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                // 字数 + 图片数
                Row(
                  children: [
                    if (snapshot.title.isNotEmpty) const SizedBox(height: 2),
                    Text(
                      '${snapshot.wordCount} 字',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (snapshot.pendingAids.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${snapshot.pendingAids.length} 张图片',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 操作
          _actionChip(
            label: '查看',
            icon: Icons.visibility_outlined,
            onTap: () => _showDetail(snapshot),
          ),
          const SizedBox(width: 4),
          _actionChip(
            label: '恢复',
            icon: Icons.restore_outlined,
            onTap: () => _restore(snapshot),
          ),
          const SizedBox(width: 4),
          _actionChip(
            label: '删除',
            icon: Icons.delete_outline,
            color: cs.error,
            onTap: () => _delete(snapshot),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: c,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 操作 ====================

  void _restore(EditorSnapshot snapshot) {
    Navigator.of(context).pop({'action': 'restore', 'snapshotId': snapshot.id});
  }

  Future<void> _delete(EditorSnapshot snapshot) async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Row(
          children: [
            Expanded(
              child: Text(
                '删除快照',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          '确定删除 "${snapshot.title.isNotEmpty ? snapshot.title : _timeLabel(snapshot.createdAt)}" 吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<EditorHistoryProvider>().deleteSnapshot(snapshot.id);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除')));
      }
    }
  }

  void _showDetail(EditorSnapshot snapshot) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        titlePadding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        title: Row(
          children: [
            Expanded(
              child: Text(
                snapshot.title.isNotEmpty ? snapshot.title : '快照详情',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('时间', _formatTime(snapshot.createdAt)),
              _detailRow('类型', snapshot.isManual ? '手动保存' : '自动快照'),
              _detailRow('字数', '${snapshot.wordCount} 字'),
              if (snapshot.pendingAids.isNotEmpty)
                _detailRow('图片', '${snapshot.pendingAids.length} 张'),
              if (snapshot.tid.isNotEmpty) _detailRow('tid', snapshot.tid),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // 只显示原始 BBCode 文本，不渲染
              if (snapshot.content.isNotEmpty)
                SelectableText(
                  snapshot.content,
                  style: const TextStyle(fontSize: 12, height: 1.4),
                )
              else
                Text('(空内容)', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        actions: [
          if (snapshot.content.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: snapshot.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // ==================== 工具 ====================

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);

    if (date == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (date == today.subtract(const Duration(days: 1))) {
      return '昨天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }

  String _timeLabel(DateTime dt) {
    return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

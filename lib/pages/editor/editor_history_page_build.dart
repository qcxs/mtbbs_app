part of 'editor_history_page.dart';

/// 编辑历史记录页 — 构建相关 UI 方法。
extension on _EditorHistoryPageState {
  Widget _buildPage(BuildContext context) {
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
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空所有',
            onPressed: _confirmClearAll,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingView();

    if (_error != null) {
      return PageErrorWidget(message: _error!, onRetry: _load, showBack: false);
    }

    if (_sessions.isEmpty) {
      return const EmptyView(icon: Icons.history, text: '暂无编辑历史');
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
            onTap: () => _setState(() {
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
    final timeStr = formatSmartTime(snapshot.createdAt);

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
              _detailRow('时间', formatDateTimeFull(snapshot.createdAt)),
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
                showToast('已复制', duration: const Duration(seconds: 1));
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
}

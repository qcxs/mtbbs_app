part of 'thread_cache_manage_page.dart';

/// 帖子缓存管理页 — 离线帖子 Tab。
extension on _ThreadCacheManagePageState {
  Widget _buildOfflineTab() {
    final items = List<ThreadSnapshotMeta>.from(_offline)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: EmptyView(
              icon: Icons.download_outlined,
              text: '暂无离线帖子\n可在帖子页菜单「保存离线副本」',
            ),
          )
        else ...[
          for (final meta in items) _buildOfflineTile(meta),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_forever_outlined, size: 18),
              label: const Text('清空离线帖子'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _handleClearOffline,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOfflineTile(ThreadSnapshotMeta meta) {
    final time = meta.savedAt ?? meta.createdAt;
    final savedBy = (meta.savedBy ?? '').replaceFirst('uid:', '');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: const Icon(Icons.download_done, size: 20),
        title: Text(
          meta.title.isEmpty ? '帖子${meta.tid}' : meta.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${meta.host} · 保存于 ${formatRelativeTime(time)}'
          '${savedBy.isEmpty ? '' : ' · 账号 $savedBy'} · '
          '评论 ${meta.cachedPages.length}/${meta.totalPages} 页 · '
          '${formatBytes(meta.approxBytes)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '删除离线副本',
          onPressed: () => _deleteOffline(meta),
        ),
        onTap: () => ThreadViewPage.openCached(context, key: meta.key),
      ),
    );
  }

  Future<void> _deleteOffline(ThreadSnapshotMeta meta) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除离线帖子',
      message:
          '将删除「${meta.title.isEmpty ? '帖子${meta.tid}' : meta.title}」'
          '的离线副本，且不可恢复。',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.deleteOfflineThread(
      host: meta.host,
      tid: meta.tid,
    );
    if (!mounted) return;
    showToast(ok ? '已删除' : '删除失败');
    await _refresh();
  }

  Future<void> _handleClearOffline() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清空离线帖子',
      message: '将删除全部离线副本，且不可恢复。',
      confirmText: '清空',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.clearOffline();
    if (!mounted) return;
    showToast(ok ? '离线帖子已清空' : '清空失败');
    await _refresh();
  }
}

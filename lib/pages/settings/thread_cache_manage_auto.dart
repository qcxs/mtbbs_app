part of 'thread_cache_manage_page.dart';

/// 帖子缓存管理页 — 自动缓存 Tab。
extension on _ThreadCacheManagePageState {
  Widget _buildAutoTab() {
    final settings = context.watch<SettingsProvider>();
    final groups = <String, List<ThreadSnapshotMeta>>{};
    for (final meta in _auto) {
      groups.putIfAbsent(meta.threadGroupKey, () => []).add(meta);
    }
    final entries = groups.entries.toList()
      ..sort(
        (a, b) =>
            _latestOf(b.value).sortTime.compareTo(_latestOf(a.value).sortTime),
      );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule, size: 20),
                title: Text('自动缓存过期：${settings.threadCacheDays} 天'),
                subtitle: const Text('过期后自动清理；不提供永不过期'),
                trailing: TextButton(
                  onPressed: () => _showDayPicker(settings.threadCacheDays),
                  child: const Text('修改'),
                ),
              ),
              const Divider(height: 1),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        size: 16,
                      ),
                      label: const Text('清理过期'),
                      onPressed: _handleCleanExpired,
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      icon: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      label: const Text('清空自动'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: _handleClearAuto,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: EmptyView(
              icon: Icons.history,
              text: '暂无自动缓存\n访问新帖后会自动缓存主帖与已加载评论',
            ),
          )
        else
          for (final entry in entries) _buildAutoTile(entry.value),
      ],
    );
  }

  ThreadSnapshotMeta _latestOf(List<ThreadSnapshotMeta> versions) {
    final sorted = List<ThreadSnapshotMeta>.from(versions)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return sorted.first;
  }

  Widget _buildAutoTile(List<ThreadSnapshotMeta> versions) {
    final latest = _latestOf(versions);
    final time = latest.lastVisitedAt ?? latest.createdAt;
    final totalBytes = versions.fold<int>(0, (s, m) => s + m.approxBytes);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: const Icon(Icons.history, size: 20),
        title: Text(
          latest.title.isEmpty ? '帖子${latest.tid}' : latest.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${latest.host} · 最后访问 ${formatRelativeTime(time)} · '
          '${versions.length} 个版本 · 评论 '
          '${latest.cachedPages.length}/${latest.totalPages} 页 · '
          '${formatBytes(totalBytes)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: '删除该帖自动缓存',
          onPressed: () => _deleteAutoThread(versions),
        ),
        onTap: () => _showVersionPicker(versions),
      ),
    );
  }

  Future<void> _showVersionPicker(List<ThreadSnapshotMeta> versions) async {
    final sorted = List<ThreadSnapshotMeta>.from(versions)
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    final selected = await showModalBottomSheet<ThreadSnapshotMeta>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '选择要查看的版本（最多保留 ${kThreadAutoMaxVersions} 个）',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var i = 0; i < sorted.length; i++)
            ListTile(
              leading: const Icon(Icons.history, size: 20),
              title: Text(
                i == 0 ? '最新版本' : '历史版本 ${i + 1}',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '${formatRelativeTime(sorted[i].sortTime)} · '
                '评论 ${sorted[i].cachedPages.length}/${sorted[i].totalPages} 页 · '
                '${formatBytes(sorted[i].approxBytes)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(ctx).pop(sorted[i]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (selected != null && mounted) {
      await ThreadViewPage.openCached(context, key: selected.key);
    }
  }

  Future<void> _deleteAutoThread(List<ThreadSnapshotMeta> versions) async {
    final latest = _latestOf(versions);
    final confirmed = await showConfirmDialog(
      context,
      title: '删除自动缓存',
      message:
          '将删除「${latest.title.isEmpty ? '帖子${latest.tid}' : latest.title}」'
          '的全部 ${versions.length} 个版本。',
      confirmText: '删除',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.deleteAutoThread(
      host: latest.host,
      viewer: _viewer,
      tid: latest.tid,
    );
    if (!mounted) return;
    showToast(ok ? '已删除' : '删除失败');
    await _refresh();
  }

  Future<void> _showDayPicker(int currentDays) async {
    const options = [1, 3, 7, 14, 30];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动缓存过期天数'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final days in options)
              RadioListTile<int>(
                title: Text('$days 天'),
                value: days,
                groupValue: currentDays,
                dense: true,
                onChanged: (v) => Navigator.of(ctx).pop(v),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await context.read<SettingsProvider>().setThreadCacheDays(picked);
    if (mounted) showToast('已设置为 $picked 天');
  }

  Future<void> _handleCleanExpired() async {
    final removed = await _service.cleanExpired();
    if (!mounted) return;
    showToast(removed > 0 ? '已清理 $removed 条过期缓存' : '没有过期缓存');
    await _refresh();
  }

  Future<void> _handleClearAuto() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '清空自动缓存',
      message: '将删除当前账号的全部自动缓存（不影响离线帖子）。',
      confirmText: '清空',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final ok = await _service.clearAuto(viewer: _viewer);
    if (!mounted) return;
    showToast(ok ? '自动缓存已清空' : '清空失败');
    await _refresh();
  }
}

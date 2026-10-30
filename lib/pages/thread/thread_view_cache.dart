part of 'thread_view_page.dart';

/// 帖子浏览页 — 缓存只读模式、自动缓存写入、离线副本保存。
///
/// 只读模式与网络模式共用 `_data/_commentPages` 等视图状态，差异集中在
/// 数据来源、分页边界与写操作开关；入口为 `ThreadViewPage.openCached`。
extension on _ThreadViewPageState {
  // ==================== 只读缓存模式 ====================

  /// 从独立缓存库读取快照并填充页面状态。
  Future<void> _loadCacheInitial() async {
    _setState(() {
      _loading = true;
      _error = null;
    });
    final service = ThreadCacheService.instance;
    if (service.isDisabled) {
      if (!mounted) return;
      _setState(() {
        _loading = false;
        _error = '缓存不可用';
      });
      return;
    }
    try {
      final snapshot = await service.readSnapshot(widget.cacheKey!);
      if (!mounted) return;
      if (snapshot == null) {
        _setState(() {
          _loading = false;
          _error = '缓存不存在或已被清理';
        });
        return;
      }
      final pages = snapshot.cachedPages;
      final page = pages.contains(1) ? 1 : (pages.isNotEmpty ? pages.first : 1);
      final posts = snapshot.commentPages[page];
      _setState(() {
        _cacheSnapshot = snapshot;
        _data = snapshot.toViewData(page: page);
        _totalPages = snapshot.totalPages;
        _currentPage = page;
        _liked = false;
        _commentPages
          ..clear()
          ..[page] = List<PostItem>.from(posts ?? const []);
        _mainPostLoaded = true;
        _loading = false;
      });
      AppLogger.i(
        'THREAD_CACHE',
        'cached view: tid=${snapshot.tid}, page=$page, '
            'cachedPages=${pages.join(',')}',
      );
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'read cached page failed: $e');
      if (!mounted) return;
      _setState(() {
        _loading = false;
        _error = '读取缓存失败';
      });
    }
  }

  /// 从快照取评论页；缺失页返回 false（不发网络请求）
  Future<bool> _loadCachedCommentPage(int page, {required bool switchPage}) {
    final snapshot = _cacheSnapshot;
    final posts = snapshot?.commentPages[page];
    if (snapshot == null || posts == null) return Future<bool>.value(false);
    _setState(() {
      _commentPages[page] = List<PostItem>.from(posts);
      if (switchPage) _currentPage = page;
    });
    return Future<bool>.value(true);
  }

  /// 只读模式跳页：只允许已缓存页
  void _goToCachedPage(int page) {
    final snapshot = _cacheSnapshot;
    if (snapshot == null || page == _currentPage) return;
    if (!snapshot.cachedPages.contains(page)) return;
    final posts = snapshot.commentPages[page];
    if (posts == null) return;
    _setState(() {
      _commentPages[page] = List<PostItem>.from(posts);
      _currentPage = page;
    });
    _scrollToFirstPostOfCurrentPage();
  }

  /// 只读模式的评论分页选择器：只列已缓存页
  void _showCachedPagePicker() {
    final snapshot = _cacheSnapshot;
    if (snapshot == null) return;
    final pages = snapshot.cachedPages;
    if (pages.isEmpty) {
      showToast('暂无已缓存的评论页');
      return;
    }
    showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '评论分页 · 已缓存 ${pages.length}/${snapshot.totalPages} 页',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final page in pages)
            ListTile(
              selected: page == _currentPage,
              title: Text('第 $page 页'),
              subtitle: Text('${snapshot.commentPages[page]?.length ?? 0} 条评论'),
              trailing: page == _currentPage
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () => Navigator.of(ctx).pop(page),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ).then((picked) {
      if (picked != null && mounted) _goToPage(picked);
    });
  }

  /// 回到正常帖子页重新加载最新内容（缓存页本身不发请求）
  void _reloadLatestFromCache() {
    final tid = _cacheSnapshot?.tid ?? widget.tid;
    if (tid.isEmpty) {
      showToast('缺少帖子 ID，无法重新加载');
      return;
    }
    context.pushReplacement('/thread/$tid');
  }

  /// 只读缓存横幅（窄屏随内容滚动；宽屏固定在双栏上方）
  Widget _buildCacheBanner() {
    final snapshot = _cacheSnapshot;
    if (snapshot == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final offline = snapshot.isOffline;
    final time = offline
        ? (snapshot.savedAt ?? snapshot.createdAt)
        : (snapshot.lastVisitedAt ?? snapshot.createdAt);
    final bg = offline ? cs.secondaryContainer : cs.surfaceContainerHigh;
    final fg = offline ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final title = offline
        ? '离线副本 · 保存于 ${formatRelativeTime(time)}'
        : '缓存快照 · 最后访问 ${formatRelativeTime(time)}';
    final versionText = offline
        ? ''
        : ' · 正文版本 ${snapshot.contentHash.isEmpty ? '-' : snapshot.contentHash.substring(0, 8)}';

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            offline ? Icons.download_done : Icons.history,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title$versionText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '只读内容，可能不是最新 · 已缓存 '
                  '${snapshot.cachedPages.length}/${snapshot.totalPages} 页',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: fg.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 版本切换固定在右侧：单行按钮，不额外占高度
          TextButton.icon(
            onPressed: _switchCachedVersion,
            icon: const Icon(Icons.layers_outlined, size: 14),
            label: const Text('切换版本'),
            style: TextButton.styleFrom(
              foregroundColor: fg,
              backgroundColor: fg.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 自动缓存写入 ====================

  /// 写入自动缓存（不 await），并记录缓存键供评论页回写
  void _writeAutoCache(ThreadViewData data) {
    if (_isCacheMode) return;
    // 用户可在「帖子缓存管理」里关闭自动缓存：关闭后只停止写入，
    // 已有缓存仍可在缓存管理页查看/导出。
    if (!context.read<SettingsProvider>().threadCacheEnabled) return;
    final service = ThreadCacheService.instance;
    if (service.isDisabled) return;
    final auth = context.read<AuthProvider>();
    final pending = service.onThreadLoaded(
      data: data,
      host: SiteStore.instance.host,
      viewer: auth.uid,
      authorid: widget.authorid,
    );
    _autoCachePending = pending;
    pending.then((key) {
      if (key != null) _autoCacheKey = key;
    });
  }

  /// 加载失败时查询该帖的可选缓存，供错误页显示「查看缓存」
  Future<void> _loadErrorCacheCandidates() async {
    final service = ThreadCacheService.instance;
    if (service.isDisabled) return;
    final list = await service.snapshotsForThread(
      host: SiteStore.instance.host,
      tid: widget.tid,
      viewer: context.read<AuthProvider>().uid,
    );
    if (!mounted) return;
    _setState(() => _errorCacheCandidates = list);
  }

  /// 评论页回写到自动缓存（无缓存键时跳过）
  Future<void> _writeCommentPageCache(
    int page,
    List<PostItem> posts,
    int totalPages,
  ) async {
    var key = _autoCacheKey;
    if (key == null) {
      final pending = _autoCachePending;
      if (pending != null) key = await pending;
    }
    if (key == null) return;
    await ThreadCacheService.instance.onCommentPageLoaded(
      cacheKey: key,
      page: page,
      posts: posts,
      totalPages: totalPages,
    );
  }

  // ==================== 帖子缓存入口 ====================

  Future<void> _handleViewCached() async {
    if (ThreadCacheService.instance.isDisabled) {
      showToast('缓存不可用');
      return;
    }
    await _openCachedPicker();
  }

  /// 打开快照选择器：只有 1 份直接进只读页，多份先弹层选择
  Future<void> _openCachedPicker({List<ThreadSnapshotMeta>? metas}) async {
    final list =
        metas ??
        await ThreadCacheService.instance.snapshotsForThread(
          host: SiteStore.instance.host,
          tid: widget.tid,
          viewer: context.read<AuthProvider>().uid,
        );
    if (!mounted) return;
    if (list.isEmpty) {
      showToast('暂无缓存');
      return;
    }
    if (list.length == 1) {
      await ThreadViewPage.openCached(context, key: list.first.key);
      return;
    }
    final selected = await _pickSnapshot(list);
    if (selected != null && mounted) {
      await ThreadViewPage.openCached(context, key: selected.key);
    }
  }

  /// 只读页内切换版本：列出该帖全部快照，选中后原地替换路由。
  ///
  /// 用 `pushReplacement` 而非 `push`：版本间切换不应叠加返回栈，
  /// 返回仍是进入只读页之前的页面。
  Future<void> _switchCachedVersion() async {
    final current = _cacheSnapshot;
    final currentKey = widget.cacheKey;
    if (current == null || currentKey == null) return;
    final list = await ThreadCacheService.instance.snapshotsForThread(
      host: current.host,
      tid: current.tid,
      viewer: context.read<AuthProvider>().uid,
    );
    if (!mounted) return;
    if (list.length <= 1) {
      showToast('没有其他版本');
      return;
    }
    final picked = await _pickSnapshot(list, currentKey: currentKey);
    if (picked == null || !mounted || picked.key == currentKey) return;
    context.pushReplacement(
      '/thread/cache?key=${Uri.encodeQueryComponent(picked.key)}',
    );
  }

  /// 快照选择弹层（帖子页入口与只读页「切换版本」共用）
  Future<ThreadSnapshotMeta?> _pickSnapshot(
    List<ThreadSnapshotMeta> list, {
    String? currentKey,
  }) {
    return showModalBottomSheet<ThreadSnapshotMeta>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          if (currentKey != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '共 ${list.length} 个版本',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final meta in list)
            ListTile(
              leading: Icon(
                meta.isOffline ? Icons.download_done : Icons.history,
                size: 20,
              ),
              title: Text(
                meta.title.isEmpty ? '帖子${meta.tid}' : meta.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${meta.isOffline ? '离线副本' : '自动缓存'} · '
                '${meta.isOffline ? '保存于 ${formatRelativeTime(meta.savedAt ?? meta.createdAt)}' : '最后访问 ${formatRelativeTime(meta.lastVisitedAt ?? meta.createdAt)}'} · '
                '评论 ${meta.cachedPages.length}/${meta.totalPages} 页'
                '${meta.summary.isEmpty ? '' : '\n${meta.summary}'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              selected: meta.key == currentKey,
              trailing: meta.key == currentKey
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () => Navigator.of(ctx).pop(meta),
            ),
        ],
      ),
    );
  }
}

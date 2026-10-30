part of 'thread_view_page.dart';

/// 帖子浏览页 — 离线副本保存（评论页补全、大小超限回退）。
extension on _ThreadViewPageState {
  // ==================== 离线副本保存 ====================

  Future<void> _handleSaveOffline() async {
    final service = ThreadCacheService.instance;
    if (service.isDisabled) {
      showToast('缓存功能已禁用，请先在缓存管理中处理');
      return;
    }
    final data = _data;
    if (data == null || data.mainPost == null) {
      showToast('帖子尚未加载完成');
      return;
    }
    if (widget.authorid != null && widget.authorid!.isNotEmpty) {
      showToast('作者筛选视图不支持离线保存');
      return;
    }
    final host = _session.host;
    final viewer = _session.uid;
    if (await service.hasOffline(host: host, tid: widget.tid)) {
      if (!mounted) return;
      final overwrite = await showConfirmDialog(
        context,
        title: '已存在离线副本',
        message: '是否覆盖原有离线副本？',
        confirmText: '覆盖',
        danger: true,
      );
      if (overwrite != true || !mounted) return;
    }

    final total = _totalPages;
    if (_commentPages.length < total) {
      final choice = await _askCommentStrategy(_commentPages.length, total);
      if (choice == null || !mounted) return;
      if (choice == _OfflineCommentChoice.loadAll) {
        final progress = await _loadMissingCommentPages(total);
        if (!mounted) return;
        if (!progress.completed) {
          final partial = await showConfirmDialog(
            context,
            title: '部分评论未加载',
            message: '已获取 ${progress.loaded}/$total 页，是否保存已加载部分？',
            confirmText: '保存已加载',
          );
          if (partial != true || !mounted) return;
        }
      }
    }

    final pages = <int, List<PostItem>>{
      for (final e in _commentPages.entries)
        e.key: List<PostItem>.from(e.value),
    };
    final result = await service.saveOffline(
      data: data,
      commentPages: pages,
      host: host,
      viewer: viewer,
    );
    if (!mounted) return;
    await _showOfflineSaveResult(
      result,
      data: data,
      pages: pages,
      allowFallback: true,
    );
  }

  Future<_OfflineCommentChoice?> _askCommentStrategy(int loaded, int total) {
    return showDialog<_OfflineCommentChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存离线副本'),
        content: Text(
          '还有 ${total - loaded} 页评论未加载。\n'
          '加载全部评论可能需要更多时间和流量；'
          '也可以只保存当前已加载的 $loaded 页。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_OfflineCommentChoice.loadedOnly),
            child: const Text('仅保存已加载'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(_OfflineCommentChoice.loadAll),
            child: const Text('加载全部并保存'),
          ),
        ],
      ),
    );
  }

  /// 顺序加载缺失评论页（保持当前显示页不变），带可取消进度
  Future<({bool completed, int loaded})> _loadMissingCommentPages(
    int total,
  ) async {
    final progress = ValueNotifier<int>(_commentPages.length);
    var cancelled = false;
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在加载评论'),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: total <= 0
                      ? null
                      : (value / total).clamp(0.0, 1.0).toDouble(),
                ),
                const SizedBox(height: 12),
                Text('正在加载 $value/$total 页'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(ctx).pop();
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    var completed = true;
    for (var page = 1; page <= total; page++) {
      if (cancelled || !mounted) {
        completed = false;
        break;
      }
      if (_commentPages.containsKey(page)) continue;
      final ok = await _loadCommentPage(page, switchPage: false);
      if (!ok) {
        completed = false;
        break;
      }
      progress.value = _commentPages.length;
    }

    if (!cancelled && mounted && dialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    await dialogFuture;
    progress.dispose();
    return (completed: completed, loaded: _commentPages.length);
  }

  Future<void> _showOfflineSaveResult(
    ThreadCacheSaveResult result, {
    required ThreadViewData data,
    required Map<int, List<PostItem>> pages,
    required bool allowFallback,
  }) async {
    switch (result.status) {
      case ThreadCacheSaveStatus.saved:
        showToast('已保存离线副本（约 ${formatBytes(result.bytes)}）');
        return;
      case ThreadCacheSaveStatus.disabled:
        showToast('缓存功能已禁用，请先在缓存管理中处理');
        return;
      case ThreadCacheSaveStatus.failed:
        showToast(result.message ?? '保存失败');
        return;
      case ThreadCacheSaveStatus.tooLarge:
        if (allowFallback && pages.length > 1) {
          final fallback = await showConfirmDialog(
            context,
            title: '超出单帖上限',
            message:
                '内容约 ${formatBytes(result.bytes)}，'
                '超过单帖上限 ${formatBytes(result.limit)}。\n'
                '是否改为仅保存主帖 + 第 1 页？',
            confirmText: '仅保存第 1 页',
          );
          if (fallback == true && mounted) {
            final reduced = <int, List<PostItem>>{
              if (pages.containsKey(1)) 1: List<PostItem>.from(pages[1]!),
            };
            final retry = await ThreadCacheService.instance.saveOffline(
              data: data,
              commentPages: reduced,
              host: _session.host,
              viewer: _session.uid,
            );
            if (!mounted) return;
            await _showOfflineSaveResult(
              retry,
              data: data,
              pages: reduced,
              allowFallback: false,
            );
          }
          return;
        }
        showToast(
          '内容约 ${formatBytes(result.bytes)}，'
          '超过单帖上限 ${formatBytes(result.limit)}，未保存',
        );
        return;
    }
  }
}

enum _OfflineCommentChoice { loadAll, loadedOnly }

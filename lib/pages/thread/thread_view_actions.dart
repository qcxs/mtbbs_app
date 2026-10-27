part of 'thread_view_page.dart';

/// 主帖"回复可见"占位标记。
///
/// 与 `post_parser.dart` / `html2bbcode.dart` 写出的 appdata 保持一致：
/// 未回复时 Discuz 只下发 `.locked`（🔒 提示），回复后才会换成正文。
final _lockedAppdataRe = RegExp(
  r'\[appdata\]\{"type":"locked".*?\}\[/appdata\]',
);

/// 帖子浏览页 — 交互与数据操作。
///
/// 通过 `part of` 与 thread_view_page.dart 共享库内私有成员。
extension on _ThreadViewPageState {
  /// 打开评分弹窗（支持帖子或评论）
  /// 评分 API 两站一致，直接拼接 forum.php?mod=misc&action=rate&tid=&pid=
  Future<void> _handleRate(PostItem post) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (post.pid.isEmpty) return;
    final rateUrl =
        '${SiteStore.instance.baseUrl}/forum.php?mod=misc&action=rate'
        '&tid=${widget.tid}&pid=${post.pid}';
    final success = await showRateDialog(context, rateUrl);
    if (success == true && mounted) {
      // 评分成功后刷新当前页
      await _loadInitial();
    }
  }

  /// 收藏帖子（带备注）：仿手机端弹窗输入备注后直接 POST API
  Future<void> _handleFavorite() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (_favoriting) return;

    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => FavoriteNoteDialog(tid: widget.tid),
    );
    if (note == null || !mounted) return; // 取消

    _setState(() => _favoriting = true);
    try {
      final result = await favorite_api.addFavorite(
        ApiService().dio,
        tid: widget.tid,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      _setState(() {
        _favoriting = false;
        if (result['success'] == true) _favorited = true;
      });
      showToast(result['message']?.toString() ?? '收藏成功');
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'favorite error: $e');
      _setState(() => _favoriting = false);
      showToast('网络错误: $e');
    }
  }

  Future<void> _handleRecommend(PostItem post) async {
    if (post.recommendUrl.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    try {
      final result = await action_api.doRecommend(
        ApiService().dio,
        post.recommendUrl,
      );
      if (!mounted) return;
      if (result.success) _setState(() => _liked = !_liked);
      showToast(result.message.isNotEmpty ? result.message : '操作成功');
    } catch (e) {
      if (!mounted) return;
      showToast('网络错误: $e');
    }
  }

  /// 记录帖子浏览历史（含当前页码）
  void _recordThreadHistory() {
    if (_data == null) return;
    context.read<HistoryProvider>().addRecord(
      BrowseRecord(
        id: '${SiteStore.instance.host}:thread_${widget.tid}',
        host: SiteStore.instance.host,
        type: 'thread',
        routePath: '/thread/${widget.tid}',
        timestamp: DateTime.now(),
        info: {
          'tid': widget.tid,
          'title': _data!.title,
          'author': _data!.mainPost?.username ?? '',
          'authorUid': _data!.mainPost?.uid ?? '',
          'time': _data!.mainPost?.postTime ?? '',
          'page': _currentPage,
          'url':
              '${SiteStore.instance.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}',
        },
      ),
    );
  }

  void _showBbcodeDialog(PostItem post) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'BBCode - ${post.username}',
                style: const TextStyle(fontSize: 15),
                overflow: TextOverflow.ellipsis,
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
        // BBCode 可能很长（整楼原文 / 含代码块）：必须可滚动，
        // 否则超出 AlertDialog 的 maxHeight 后被裁剪、无法查看
        content: SingleChildScrollView(
          child: SelectableText(
            post.bbcode,
            style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () {
              _copyToClipboard(post.bbcode);
              Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制'),
          ),
        ],
      ),
    );
  }

  /// 生成当前楼层的分享图片（预览 → 截图保存，见 pages/thread/thread_share_page.dart）
  void _showShareImage(PostItem post) {
    ThreadSharePage.open(
      context,
      post: post,
      tid: widget.tid,
      threadTitle: _data?.title ?? '',
      opUid: _data?.mainPost?.uid ?? '',
    );
  }

  void _editPost(PostItem post) {
    final isOp = post.pid == _data?.mainPost?.pid;
    _openEditor(
      '/editor?type=${isOp ? 'editPost' : 'editReply'}&tid=${widget.tid}&pid=${post.pid}',
      editingPid: post.pid,
    );
  }

  Future<void> _fetchPostDetailInfo(PostItem post) async {
    final url =
        '/forum.php?mod=post&action=reply&fid=2&tid=${widget.tid}&repquote=${post.pid}&page=1';
    try {
      final resp = await ApiService().dio.get<String>(url);
      if (!mounted) return;
      final body = resp.data is String ? (resp.data as String) : '';
      final doc = htmlParser.parse(body);
      String? extractField(String name) =>
          doc.querySelector('input[name="$name"]')?.attributes['value'];
      final noticetrimstr = extractField('noticetrimstr') ?? '';
      String? postTime;
      final timeMatch = RegExp(
        r'发表于\s+(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})',
      ).firstMatch(noticetrimstr);
      if (timeMatch != null) postTime = timeMatch.group(1);
      if (mounted) {
        final time = postTime ?? post.postTime;
        if (time.isNotEmpty) showToast('发表于 $time');
      }
    } catch (e) {
      if (!mounted) return;
      showToast('获取详情失败: $e');
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast('已复制到剪贴板', duration: const Duration(seconds: 1));
  }

  void _showPagePicker() {
    // 只读缓存：只允许跳到已缓存页（实现见 thread_view_cache.dart）
    if (_isCacheMode) {
      _showCachedPagePicker();
      return;
    }
    showPageJumpDialog(
      context,
      currentPage: _currentPage,
      totalPages: _totalPages,
      title: '跳转页码',
      initialText: '$_currentPage',
      autofocus: true,
      showSummary: false,
      onGoToPage: _goToPage,
    );
  }

  // ==================== 导航 ====================

  void _navigateComment() {
    if (_data == null) return;
    // 「帖子迷你编辑器」关闭时退回原设计（全屏编辑器）
    if (context.read<SettingsProvider>().threadMiniEditorEnabled) {
      _startComment();
    } else {
      _openEditor('/editor?type=comment&tid=${widget.tid}');
    }
  }

  /// 回复某条评论：迷你编辑器开启则内嵌切换目标，否则退回全屏编辑器
  void _replyToPost(PostItem post) {
    if (context.read<SettingsProvider>().threadMiniEditorEnabled) {
      _startReply(post);
    } else {
      _openEditor('/editor?type=reply&tid=${widget.tid}&pid=${post.pid}');
    }
  }

  /// 窄屏时滚动到评论区顶部
  void _scrollToComments() {
    final ctx = _commentAnchorKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      alignment: 0.0,
    );
  }

  /// 点标题"回顶部"（宽/窄屏共用同一 `_scrollController`）。
  ///
  /// 必须判 `hasClients`：内容区可能尚未挂载（加载中 / 错误页 / 空态），
  /// 此时 `animateTo` 会命中 `_positions.isNotEmpty` 断言（release 为静默无效）。
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToPid() {
    final pid = widget.pid;
    if (pid == null || pid.isEmpty) return;
    _scrollToPost(pid);
  }

  /// 平滑滚动到指定楼层（无该楼层时不做任何事）
  void _scrollToPost(String pid) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _postKeys[pid]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    });
  }

  /// 刷新当前评论页（失败保留原有评论，不清空）
  Future<void> _refreshCurrentPage() async {
    if (_isCacheMode) {
      await _loadCacheInitial();
      return;
    }
    await _loadCommentPage(_currentPage, force: true);
  }

}

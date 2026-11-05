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
  /// 跨站点临时会话是只读的：默认账号只用于"看"，写操作必须先切站点。
  bool _guardReadOnly() {
    if (!_session.temporary) return false;
    showToast('跨站点浏览为只读，发帖/评论请先切换到目标站点');
    return true;
  }

  /// 打开评分弹窗（支持帖子或评论）
  /// 评分 API 两站一致，直接拼接 forum.php?mod=misc&action=rate&tid=&pid=
  Future<void> _handleRate(PostItem post) async {
    if (_guardReadOnly()) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    if (post.pid.isEmpty) return;
    final rateUrl =
        '${_session.baseUrl}/forum.php?mod=misc&action=rate'
        '&tid=${widget.tid}&pid=${post.pid}';
    final success = await showRateDialog(context, rateUrl);
    if (success == true && mounted) {
      // 评分成功后刷新当前页
      await _loadInitial();
    }
  }

  /// 收藏帖子（带备注）：仿手机端弹窗输入备注后直接 POST API
  Future<void> _handleFavorite() async {
    if (_guardReadOnly()) return;
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
        _dio,
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
    if (_guardReadOnly()) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      showToast('请先登录');
      return;
    }
    try {
      final result = await action_api.doRecommend(
        _dio,
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
    // 跨站点浏览不写历史：历史条目按"当前站点"归类，写进去后会指错站点
    if (_session.temporary) return;
    final host = _session.host;
    context.read<HistoryProvider>().addRecord(
      BrowseRecord(
        id: '$host:thread_${widget.tid}',
        host: host,
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
              '${_session.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}',
        },
      ),
    );
  }

  void _showPostSource(PostItem post) {
    PostSourceSheet.show(
      context,
      username: post.username,
      bbcode: post.bbcode,
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
      siteHost: _session.host,
      siteBaseUrl: _session.baseUrl,
    );
  }

  void _editPost(PostItem post) {
    if (_guardReadOnly()) return;
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
      final resp = await _dio.get<String>(url);
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

  /// 点击「评论区」标题：输入楼层号并跳转
  void _showFloorJumpDialog() {
    if (_isCacheMode || _data == null) return;
    // 只看作者视图按作者回复数分页，与全帖楼层号不是一套页码，无法可靠定位
    if (widget.authorid != null && widget.authorid!.isNotEmpty) {
      showToast('只看作者模式下不支持按楼层跳转');
      return;
    }
    showPageJumpDialog(
      context,
      currentPage: _currentPage,
      title: '跳转楼层',
      autofocus: true,
      showSummary: false,
      hintText: '输入楼层号（1 为主帖）',
      onGoToPage: _jumpToFloor,
    );
  }

  /// 用 Discuz 的跳转定位接口解析楼层所在页。
  ///
  /// 不本地推算每页帖数：置顶回复、删帖都会让"每页帖数"失真。
  Future<int?> _resolveFloorPage(int floor) async {
    final result = await redirect_api.resolveRedirectPage(
      _dio,
      tid: widget.tid,
      authorid: widget.authorid ?? '0',
      postno: floor,
    );
    if (result['success'] == true) {
      return result['page'] as int?;
    }
    // 落到帖子页但没有页码 = 楼层超出范围；其余按请求失败处理
    return result['reason'] == 'floor_not_found' ? 0 : null;
  }

  /// 按楼层号定位：由站点重定向解析目标页，必要时加载，再滚动到该楼层
  Future<void> _jumpToFloor(int floor) async {
    if (_isCacheMode || floor < 1) return;
    if (floor == 1) {
      _setState(() => _mainPostLoaded = true);
      _scrollToTop();
      return;
    }
    if (_pageLoading) {
      showToast('评论正在加载，请稍后再试');
      return;
    }
    final targetPage = await _resolveFloorPage(floor);
    if (!mounted) return;
    if (targetPage == null) {
      showToast('跳转失败，请稍后重试');
      return;
    }
    if (targetPage == 0) {
      showToast('楼层 $floor 不存在');
      return;
    }
    if (targetPage > _totalPages) {
      showToast('楼层 $floor 不存在');
      return;
    }
    if (targetPage != _currentPage) {
      _setState(() {
        _currentPage = targetPage;
      });
      _recordThreadHistory();
      if (!_commentPages.containsKey(targetPage)) {
        final ok = await _loadCommentPage(targetPage);
        if (!mounted) return;
        if (!ok) {
          showToast('加载第 $targetPage 页失败');
          return;
        }
      } else if (!mounted) {
        return;
      }
    }
    _scrollToFloor(floor);
  }

  /// 在当前页查找指定楼层并滚动；找不到时提示（楼层可能已删除）
  void _scrollToFloor(int floor) {
    final posts = _commentPages[_currentPage];
    if (posts != null) {
      for (final post in posts) {
        if (post.floor == floor) {
          _scrollToPost(post.pid);
          return;
        }
      }
    }
    showToast('未找到 $floor 楼（可能已被删除）');
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

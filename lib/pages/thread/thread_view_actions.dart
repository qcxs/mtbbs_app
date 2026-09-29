part of 'thread_view_page.dart';

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
        content: SelectableText(
          post.bbcode,
          style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.5),
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
    _openEditor('/editor?type=comment&tid=${widget.tid}');
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

  /// 刷新当前评论页
  Future<void> _refreshCurrentPage() async {
    _commentPages.remove(_currentPage);
    await _loadCommentPage(_currentPage);
  }

  /// 打开编辑器并处理发布结果
  ///
  /// 只有发布成功才动作——用户返回/放弃时 pop 为 null，什么都不做。
  /// - 编辑类：用已知 pid 取回内容，原地覆盖那一楼
  /// - 回复/评论：取回新楼追加到当前评论页末尾（对齐网页追加行为，不整页刷新）
  /// - 审核中：不追加（与网页一致，只由编辑器提示）
  Future<void> _openEditor(String path, {String? editingPid}) async {
    final r = await context.push<Map<String, dynamic>>(path);
    if (!mounted || r == null || r['success'] != true) return;
    final result = r['result'] as SubmitResult?;
    if (result == null) return;

    if (editingPid != null && editingPid.isNotEmpty) {
      await _replacePost(editingPid);
      return;
    }
    if (result.needsApproval || result.pid.isEmpty) return;
    await _appendPost(result.pid);
  }

  /// 取回单个楼层（网页追加回复时请求的 viewpid 接口）
  Future<PostItem?> _fetchPost(String pid) async {
    try {
      await EmojiService().load();
      final raw = await viewpid_api.getPostByPid(
        ApiService().dio,
        tid: widget.tid,
        viewpid: pid,
      );
      if (raw['success'] != true || raw['post'] == null) return null;
      final map = Map<String, dynamic>.from(raw['post'] as Map);
      map['floor'] = _resolveFloor(map);
      return PostItem.fromMap(map);
    } catch (e) {
      AppLogger.w('PAGE', 'fetch post $pid error: $e');
      return null;
    }
  }

  /// 楼层号兜底
  ///
  /// 解析层已从 postnum 标签取到楼层（数字 `16#` 或中文名 沙发/椅子…），
  /// 这里只在取不到时顺延末楼。
  int _resolveFloor(Map<String, dynamic> post) {
    final floor = (post['floor'] as int?) ?? 0;
    if (floor > 0) return floor;
    final posts = _commentPages[_currentPage];
    if (posts != null && posts.isNotEmpty) return posts.last.floor + 1;
    return 0;
  }

  /// 把新楼追加到当前评论页末尾并滚动过去（按 pid 去重）
  Future<void> _appendPost(String pid) async {
    final post = await _fetchPost(pid);
    if (post == null || !mounted) return;
    final posts = _commentPages[_currentPage] ??= <PostItem>[];
    if (posts.any((p) => p.pid == post.pid)) return;
    _setState(() => posts.add(post));
    _scrollToPost(post.pid);
  }

  /// 用取回的内容原地覆盖指定楼层（编辑成功后使用）
  Future<void> _replacePost(String pid) async {
    // 楼主帖不在评论列表里，单独刷新主帖区
    if (_data?.mainPost?.pid == pid) {
      await _reloadMainPost();
      return;
    }
    final post = await _fetchPost(pid);
    if (post == null || !mounted) return;
    final posts = _commentPages[_currentPage];
    if (posts == null) return;
    final index = posts.indexWhere((p) => p.pid == post.pid);
    if (index < 0) return;
    _setState(() => posts[index] = post);
  }

  /// 重新加载第 1 页以刷新主帖（不动已加载的评论页）
  Future<void> _reloadMainPost() async {
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: 1,
        authorid: widget.authorid,
      );
      if (raw['success'] != true || !mounted) return;
      final data = ThreadViewData.fromMap(raw, widget.tid);
      if (!mounted) return;
      _setState(() {
        _data = data;
        _totalPages = data.totalPages;
        _liked = data.mainPost?.isLiked ?? false;
      });
    } catch (e) {
      AppLogger.w('PAGE', 'reload main post error: $e');
    }
  }
}

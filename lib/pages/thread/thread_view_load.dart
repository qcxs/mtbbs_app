part of 'thread_view_page.dart';

/// 帖子浏览页 — 网络加载与分页（正常模式）。
///
/// 只读缓存模式的数据来源与分页边界见 thread_view_cache.dart。
extension on _ThreadViewPageState {
  // ==================== 加载逻辑 ====================

  /// 错误页「网页验证」：直接打开验证浏览器，通过后重新加载。
  ///
  /// 与自动恢复（Dio 拦截器）走同一套回流 / 探测逻辑，只是入口是用户手动点；
  /// 自动恢复失败时（挑战需要交互、或自解写错罐）才用得上。
  Future<void> _verifyFromErrorPage() async {
    final ok = await VerificationGate.instance.verifyManually(url: _threadUrl);
    if (!mounted) return;
    if (ok) {
      await _loadInitial();
    } else {
      showToast('网页验证未通过，请重试');
    }
  }

  /// 通过 redirect（允许重定向）获取 pid 对应的真实 page
  Future<int> _resolveRedirectPage() async {
    final pid = widget.pid;
    if (pid == null || pid.isEmpty) return 1;
    try {
      final dio = _dio;
      final response = await dio.get(
        '/forum.php?mod=redirect&goto=findpost&pid=$pid&ptid=${widget.tid}',
        options: Options(validateStatus: (status) => true),
      );
      for (final r in response.redirects.reversed) {
        final pageStr = r.location.queryParameters['page'];
        if (pageStr != null && pageStr.isNotEmpty) {
          final p = int.tryParse(pageStr) ?? 1;
          AppLogger.i('PAGE', 'redirect pid=$pid → page=$p');
          return p;
        }
      }
      return 1;
    } catch (e) {
      AppLogger.w('PAGE', 'resolve redirect page error: $e');
      return 1;
    }
  }

  /// 初始加载
  Future<void> _loadInitial() async {
    _setState(() {
      _loading = true;
      _error = null;
    });
    try {
      int targetPage = widget.initialPage;
      bool pidMode = false;
      if (widget.pid != null && widget.pid!.isNotEmpty) {
        targetPage = await _resolveRedirectPage();
        pidMode = true;
      }
      // 确保表情已加载，帖子内容里的表情才能还原为 [呵呵] 文本
      await EmojiService().load();
      final page1Result = await detail_api.getThreadDetail(
        _dio,
        tid: widget.tid,
        page: 1,
        authorid: widget.authorid,
      );
      if (page1Result['success'] != true) {
        throw Exception(page1Result['message']?.toString() ?? '加载失败');
      }
      final page1Data = ThreadViewData.fromMap(page1Result, widget.tid);
      if (!mounted) return;
      final d = page1Data;
      _totalPages = d.totalPages;
      _data = d;
      _liked = d.mainPost?.isLiked ?? false;

      final title = d.title.isNotEmpty ? d.title : '帖子${widget.tid}';
      _recordThreadHistory();

      _commentPages[1] = List<PostItem>.from(d.posts);
      _currentPage = targetPage.clamp(1, _totalPages);
      _mainPostLoaded = _currentPage == 1;

      // 新帖自动缓存：不 await，缓存 IO 不阻塞渲染
      _writeAutoCache(d);

      AppLogger.i(
        'PAGE',
        'ThreadViewPage init: tid=${widget.tid}, title=$title, '
            'totalPages=$_totalPages, targetPage=$_currentPage${pidMode ? ' (pid)' : ''}',
      );

      _setState(() {
        _loading = false;
      });
      if (_currentPage > 1) await _loadCommentPage(_currentPage);
      if (pidMode) _scrollToPid();
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final cleanMsg = msg.startsWith('Exception: ')
            ? msg.substring(11)
            : msg;
        AppLogger.w('PAGE', 'ThreadViewPage error: $cleanMsg');
        _setState(() {
          _error = cleanMsg.isEmpty ? '加载失败' : cleanMsg;
          _loading = false;
        });
        unawaited(_loadErrorCacheCandidates());
      }
    }
  }

  /// 只读缓存模式：从快照取页（实现见 thread_view_cache.dart）
  Future<bool> _loadCommentPage(
    int page, {
    bool force = false,
    bool switchPage = true,
  }) async {
    if (_isCacheMode) return _loadCachedCommentPage(page, switchPage: switchPage);
    if (_pageLoading) return false;
    if (!force && _commentPages.containsKey(page)) return true;
    _setState(() {
      _pageLoading = true;
    });
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        _dio,
        tid: widget.tid,
        page: page,
        authorid: widget.authorid,
      );
      if (raw['success'] != true) {
        throw Exception(raw['message']?.toString() ?? '加载失败');
      }
      final data = ThreadViewData.fromMap(raw, widget.tid);
      if (!mounted) return false;
      final actualPage = data.currentPage;
      _commentPages[actualPage] = List<PostItem>.from(data.posts);
      if (switchPage) _currentPage = actualPage;
      AppLogger.i(
        'PAGE',
        'loaded comment page $actualPage (${data.posts.length} posts)',
      );
      // 自动缓存只回写已加载页，不额外抓取
      unawaited(
        _writeCommentPageCache(actualPage, data.posts, data.totalPages),
      );
      if (mounted)
        _setState(() {
          _pageLoading = false;
        });
      return true;
    } catch (e) {
      AppLogger.w('PAGE', 'load comment page $page error: $e');
      if (mounted)
        _setState(() {
          _pageLoading = false;
        });
      return false;
    }
  }

  void _goToPage(int page) {
    // 只读缓存模式：只跳已缓存页（实现见 thread_view_cache.dart）
    if (_isCacheMode) {
      _goToCachedPage(page);
      return;
    }
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    _setState(() {
      _currentPage = page;
    });
    _recordThreadHistory();
    if (!_commentPages.containsKey(page)) _loadCommentPage(page);
    _scrollToFirstPostOfCurrentPage();
  }

  /// 翻页后把视图移到该页第一条评论
  void _scrollToFirstPostOfCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final posts = _commentPages[_currentPage];
      if (posts != null && posts.isNotEmpty) {
        final firstKey = _postKeys[posts.first.pid];
        if (firstKey?.currentContext != null) {
          Scrollable.ensureVisible(
            firstKey!.currentContext!,
            duration: const Duration(milliseconds: 200),
            alignment: 0.0,
          );
        }
      }
    });
  }

  /// 缓存模式下当前页的前/后一个已缓存页（无则返回 null）
  int? get _cachedPrevPage {
    final pages = _cacheSnapshot?.cachedPages ?? const <int>[];
    final i = pages.indexOf(_currentPage);
    return i > 0 ? pages[i - 1] : null;
  }

  int? get _cachedNextPage {
    final pages = _cacheSnapshot?.cachedPages ?? const <int>[];
    final i = pages.indexOf(_currentPage);
    return i >= 0 && i < pages.length - 1 ? pages[i + 1] : null;
  }

  /// 分页按钮：缓存模式按「已缓存页」判断边界
  bool get _canGoPrev =>
      _isCacheMode ? _cachedPrevPage != null : _currentPage > 1;

  bool get _canGoNext =>
      _isCacheMode ? _cachedNextPage != null : _currentPage < _totalPages;

  void _goPrevPage() {
    final page = _isCacheMode ? _cachedPrevPage : _currentPage - 1;
    if (page != null) _goToPage(page);
  }

  void _goNextPage() {
    final page = _isCacheMode ? _cachedNextPage : _currentPage + 1;
    if (page != null) _goToPage(page);
  }

  Future<void> _onRefresh() async {
    // 缓存模式：重新读快照即可，绝不走网络
    if (_isCacheMode) {
      await _loadCacheInitial();
      return;
    }
    AppLogger.i('PAGE', 'refresh: page1 + page$_currentPage');
    // 先请求第 1 页（主帖 + 第 1 页评论），成功才整体替换，失败保留旧内容
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        _dio,
        tid: widget.tid,
        page: 1,
        authorid: widget.authorid,
      );
      if (raw['success'] != true) {
        throw Exception(raw['message']?.toString() ?? '加载失败');
      }
      if (!mounted) return;
      final d = ThreadViewData.fromMap(raw, widget.tid);
      _setState(() {
        _commentPages[1] = List<PostItem>.from(d.posts);
        _totalPages = d.totalPages;
        _data = d;
        _liked = d.mainPost?.isLiked ?? false;
      });
      _writeAutoCache(d);
      AppLogger.i('PAGE', 'refresh page1 ok (${d.posts.length} posts)');
    } catch (e) {
      AppLogger.w('PAGE', 'refresh page1 failed: $e');
    }
    // 当前不在第 1 页时，强制刷新当前评论页（需要时由 _loadCommentPage 自行合并）
    if (_currentPage != 1 && mounted) {
      await _loadCommentPage(_currentPage, force: true);
    }
  }
}

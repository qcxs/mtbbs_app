import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:dio/dio.dart';
import 'package:mtbbs/widgets/common/page_actions.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/thread/thread_post_card.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/page_jump_dialog.dart';
import 'package:mtbbs/widgets/dialog/rate_dialog.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as detail_api;
import 'package:mtbbs/api/forum/viewthread/action/export.dart' as action_api;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'thread_view_comment_section.dart';
import 'thread_view_main_post.dart';

/// 帖子浏览页（渲染 BBCode）
///
/// 宽屏（> 600px）时评论显示在右侧，窄屏时显示在底部。
///
/// 参数组合：
/// - 只有 [tid]：显示帖子标题 + 主帖占位 + 第 1 页评论。
/// - [tid] + [initialPage]：加载指定页评论。
/// - [tid] + [pid]：通过 redirect 解析实际 page，自动跳到对应页。
/// - [authorid]：过滤只显示指定用户的评论。
class ThreadViewPage extends StatefulWidget {
  final String tid;
  final int initialPage;
  final String? pid;
  final String? authorid;

  const ThreadViewPage({
    super.key,
    required this.tid,
    this.initialPage = 1,
    this.pid,
    this.authorid,
  });

  @override
  State<ThreadViewPage> createState() => _ThreadViewPageState();
}

class _ThreadViewPageState extends State<ThreadViewPage> {
  // ---- 帖子基本信息（加载一次，来自第 1 页） ----
  ThreadViewData? _data;
  bool _loading = true;
  String? _error;

  // ---- 主帖 ----
  bool _mainPostLoaded = false;

  // ---- 评论分页 ----
  final Map<int, List<PostItem>> _commentPages = {};
  int _currentPage = 1;
  int _totalPages = 1;
  bool _pageLoading = false;

  // ---- 预加载 ----
  bool _preloading = false;

  // ---- 滚动 ----
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _commentAnchorKey = GlobalKey();

  // ---- pid 定位 ----
  final Map<String, GlobalKey> _postKeys = {};

  // ---- 操作状态 ----
  bool _liked = false;

  /// 当前帖子是否已收藏（收藏成功后置 true，仅本次会话有效）
  bool _favorited = false;

  /// 收藏提交中（禁用按钮）
  bool _favoriting = false;

  /// 顶栏"全局禁用样式"开关（作用于当前帖子页所有帖子）
  bool _globalDisableStyle = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== 加载逻辑 ====================

  /// 通过 redirect（允许重定向）获取 pid 对应的真实 page
  Future<int> _resolveRedirectPage() async {
    final pid = widget.pid;
    if (pid == null || pid.isEmpty) return 1;
    try {
      final dio = ApiService().dio;
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
    setState(() {
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
        ApiService().dio,
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

      AppLogger.i(
        'PAGE',
        'ThreadViewPage init: tid=${widget.tid}, title=$title, '
            'totalPages=$_totalPages, targetPage=$_currentPage${pidMode ? ' (pid)' : ''}',
      );

      setState(() {
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
        setState(() {
          _error = cleanMsg.isEmpty ? '加载失败' : cleanMsg;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadCommentPage(int page) async {
    if (_commentPages.containsKey(page) || _pageLoading) return;
    setState(() {
      _pageLoading = true;
    });
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: page,
        authorid: widget.authorid,
      );
      if (raw['success'] != true) {
        throw Exception(raw['message']?.toString() ?? '加载失败');
      }
      final data = ThreadViewData.fromMap(raw, widget.tid);
      if (!mounted) return;
      final actualPage = data.currentPage;
      _commentPages[actualPage] = List<PostItem>.from(data.posts);
      _currentPage = actualPage;
      AppLogger.i(
        'PAGE',
        'loaded comment page $actualPage (${data.posts.length} posts)',
      );
    } catch (e) {
      AppLogger.w('PAGE', 'load comment page $page error: $e');
    }
    if (mounted)
      setState(() {
        _pageLoading = false;
      });
  }

  void _preloadAdjacentPages() {
    if (_preloading) return;
    final next = _currentPage + 1;
    if (next <= _totalPages && !_commentPages.containsKey(next)) {
      _doPreload(next);
      return;
    }
    final prev = _currentPage - 1;
    if (prev >= 1 && !_commentPages.containsKey(prev)) _doPreload(prev);
  }

  void _doPreload(int page) {
    _preloading = true;
    // 先确保表情已加载，预加载的帖子内容才能还原表情（不会固化坏缓存）
    EmojiService()
        .load()
        .then(
          (_) => detail_api.getThreadDetail(
            ApiService().dio,
            tid: widget.tid,
            page: page,
            authorid: widget.authorid,
          ),
        )
        .then((raw) {
          if (raw['success'] == true && mounted) {
            final data = ThreadViewData.fromMap(raw, widget.tid);
            if (!mounted) return;
            _commentPages[data.currentPage] = List<PostItem>.from(data.posts);
            if (mounted) setState(() {});
          }
          _preloading = false;
        })
        .catchError((_) {
          _preloading = false;
        });
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    setState(() {
      _currentPage = page;
    });
    _recordThreadHistory();
    if (!_commentPages.containsKey(page)) _loadCommentPage(page);
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

  void _scrollToPid() {
    final pid = widget.pid;
    if (pid == null || pid.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _postKeys[pid];
      if (key?.currentContext == null) return;
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    });
  }

  Future<void> _onRefresh() async {
    if (_loading || _pageLoading) return;
    AppLogger.i('PAGE', 'refresh: page1 + page$_currentPage');
    if (_currentPage == 1) {
      _commentPages.remove(1);
      await _loadInitial();
      return;
    }
    _commentPages.remove(1);
    _data = null;
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: 1,
        authorid: widget.authorid,
      );
      if (raw['success'] == true && mounted) {
        final d = ThreadViewData.fromMap(raw, widget.tid);
        if (!mounted) return;
        _commentPages[1] = List<PostItem>.from(d.posts);
        _totalPages = d.totalPages;
        _data = d;
        _liked = d.mainPost?.isLiked ?? false;
      }
    } catch (_) {}
    _commentPages.remove(_currentPage);
    if (mounted) await _loadCommentPage(_currentPage);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 280) {
        _preloadAdjacentPages();
      }
    }
    return false;
  }

  // ==================== 帖子操作 ====================

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
      builder: (ctx) => _FavoriteNoteDialog(tid: widget.tid),
    );
    if (note == null || !mounted) return; // 取消

    setState(() => _favoriting = true);
    try {
      final result = await favorite_api.addFavorite(
        ApiService().dio,
        tid: widget.tid,
        note: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      setState(() {
        _favoriting = false;
        if (result['success'] == true) _favorited = true;
      });
      showToast(result['message']?.toString() ?? '收藏成功');
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'favorite error: $e');
      setState(() => _favoriting = false);
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
      if (result.success) setState(() => _liked = !_liked);
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
        id: 'thread_${widget.tid}',
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
    context.push(
      '/editor?type=${isOp ? 'editPost' : 'editReply'}&tid=${widget.tid}&pid=${post.pid}',
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
    context.push('/editor?type=comment&tid=${widget.tid}');
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

  /// 刷新当前评论页
  Future<void> _refreshCurrentPage() async {
    _commentPages.remove(_currentPage);
    await _loadCommentPage(_currentPage);
  }

  // ==================== Build ====================

  String get _threadUrl =>
      '${SiteStore.instance.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNarrow = MediaQuery.sizeOf(context).width <= 600;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          child: Text(
            _data?.title.isNotEmpty == true ? _data!.title : '帖子详情',
            style: const TextStyle(fontSize: 15),
          ),
        ),
        surfaceTintColor: cs.surface,
        actions: [
          if (isNarrow && _data != null && _commentPages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.forum_outlined, size: 20),
              tooltip: '滚动到评论区',
              onPressed: _scrollToComments,
            ),
          // 全局禁用样式 toggle（刷新按钮左侧）
          IconButton(
            icon: Text(
              _globalDisableStyle ? 'T̶' : 'T',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _globalDisableStyle ? cs.error : cs.onSurfaceVariant,
              ),
            ),
            tooltip: _globalDisableStyle ? '恢复样式渲染（全局）' : '全局禁用样式',
            onPressed: () =>
                setState(() => _globalDisableStyle = !_globalDisableStyle),
          ),
          PageActions(
            url: _threadUrl,
            onRefresh: () => _loadInitial(),
            loading: _loading,
            copyLabel: '复制帖子链接',
            extraItems: () {
              final tidNum = int.tryParse(widget.tid);
              if (tidNum == null) return <PopupMenuEntry<String>>[];
              return [
                PopupMenuItem<String>(
                  value: 'prev_thread',
                  enabled: tidNum > 1,
                  child: Row(
                    children: [
                      Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: tidNum > 1
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                      const SizedBox(width: 8),
                      const Text('上一篇'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'next_thread',
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_right, size: 18),
                      const SizedBox(width: 8),
                      const Text('下一篇'),
                    ],
                  ),
                ),
              ];
            }(),
            onExtraSelected: (action) {
              final tidNum = int.tryParse(widget.tid);
              if (tidNum == null) return;
              switch (action) {
                case 'prev_thread':
                  if (tidNum > 1) {
                    GoRouter.of(context).replace('/thread/${tidNum - 1}');
                  }
                case 'next_thread':
                  GoRouter.of(context).replace('/thread/${tidNum + 1}');
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_loading) return const LoadingView();
          if (_error != null)
            return PageErrorWidget(
              message: _error!,
              onRetry: () => _loadInitial(),
            );
          if (_data == null) return const EmptyView(text: '暂无数据');
          final isWide = constraints.maxWidth > 600;
          if (isWide) return _buildWideLayout();
          return _buildNarrowLayout();
        },
      ),
      bottomNavigationBar: _buildReplyBar(),
    );
  }

  // ==================== 布局 ====================

  Widget _buildWideLayout() {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (_data!.title.isNotEmpty) _buildTitleSection(),
              if (_data!.mainPost != null) _buildMainPostSection(),
            ],
          ),
        ),
        Container(width: 1, color: cs.outlineVariant),
        Expanded(flex: 2, child: _buildCommentColumn()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    final currentPosts = _commentPages[_currentPage];
    if ((currentPosts == null || currentPosts.isEmpty) &&
        _data!.mainPost == null &&
        !_pageLoading) {
      return const EmptyView(text: '暂无数据');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            if (_data!.title.isNotEmpty)
              SliverToBoxAdapter(child: _buildTitleSection()),
            if (_data!.mainPost != null) ...[
              SliverToBoxAdapter(child: _buildMainPostSection()),
              SliverToBoxAdapter(child: const Divider(height: 1)),
              // 评论区锚点 — 窄屏"滚动到评论区"的目标
              SliverToBoxAdapter(
                child: SizedBox(key: _commentAnchorKey, height: 1),
              ),
            ],
            SliverPersistentHeader(
              pinned: true,
              delegate: CommentHeaderDelegate(
                child: CommentSection.buildHeader(
                  context: context,
                  currentPage: _currentPage,
                  totalPages: _totalPages,
                  pageLoading: _pageLoading,
                  onPrev: _currentPage > 1
                      ? () => _goToPage(_currentPage - 1)
                      : null,
                  onNext: _currentPage < _totalPages
                      ? () => _goToPage(_currentPage + 1)
                      : null,
                  onPageTap: _showPagePicker,
                  onRefresh: _refreshCurrentPage,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildCommentContent()),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 评论区 ====================

  Widget _buildCommentContent() {
    final currentPosts = _commentPages[_currentPage];
    if (currentPosts == null && _pageLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return CommentSection(
      posts: currentPosts ?? [],
      postKeys: _postKeys,
      currentPage: _currentPage,
      totalPages: _totalPages,
      pageLoading: _pageLoading,
      tid: widget.tid,
      globalDisableStyle: _globalDisableStyle,
      onScrollNotification: _handleScrollNotification,
      onReply: (post) =>
          context.push('/editor?type=reply&tid=${widget.tid}&pid=${post.pid}'),
      onRecommend: _handleRecommend,
      onPopupAction: (action, post) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
          case PostCardAction.rate:
            _handleRate(post);
        }
      },
    );
  }

  Widget _buildCommentColumn() {
    return Column(
      children: [
        CommentSection.buildHeader(
          context: context,
          currentPage: _currentPage,
          totalPages: _totalPages,
          pageLoading: _pageLoading,
          onPrev: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          onNext: _currentPage < _totalPages
              ? () => _goToPage(_currentPage + 1)
              : null,
          onPageTap: _showPagePicker,
          onRefresh: _refreshCurrentPage,
        ),
        const Divider(height: 1),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: SingleChildScrollView(child: _buildCommentContent()),
          ),
        ),
      ],
    );
  }

  // ==================== 主帖 ====================

  Widget _buildMainPostSection() {
    final post = _data!.mainPost!;
    return MainPostSection(
      post: post,
      isLoaded: _mainPostLoaded,
      isLiked: _liked,
      tid: widget.tid,
      globalDisableStyle: _globalDisableStyle,
      onTap: () => setState(() => _mainPostLoaded = true),
      onRecommend: () => _handleRecommend(post),
      onPopupAction: (action) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
          case PostCardAction.rate:
            _handleRate(post);
        }
      },
    );
  }

  // ==================== 杂项组件 ====================

  Widget _buildReplyBar() {
    final cs = Theme.of(context).colorScheme;
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: _favoriting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _favorited ? Icons.bookmark : Icons.bookmark_border,
                    size: 20,
                    color: _favorited ? cs.primary : cs.onSurfaceVariant,
                  ),
            tooltip: _favorited ? '已收藏' : '收藏帖子（可备注）',
            onPressed: _favoriting ? null : _handleFavorite,
          ),
          // 点赞（对帖子的操作，移到收藏旁）
          IconButton(
            icon: Icon(
              _liked ? Icons.thumb_up : Icons.thumb_up_outlined,
              size: 20,
              color: _liked ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _liked ? '已点赞' : '点赞',
            onPressed: () {
              final mainPost = _data?.mainPost;
              if (mainPost != null) _handleRecommend(mainPost);
            },
          ),
          // 评分（文字入口，移到收藏旁）
          if (_data?.mainPost != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _handleRate(_data!.mainPost!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '评分',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Icon(Icons.reply_rounded, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _navigateComment,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '说点什么...',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.send_rounded, color: cs.onSurfaceVariant),
            onPressed: _navigateComment,
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Text(
        _data!.title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 收藏备注输入弹窗（仿手机端收藏弹窗，可填备注后提交）
///
/// 返回备注文本；用户取消返回 null；空备注返回空字符串（表示收藏但不备注）。
class _FavoriteNoteDialog extends StatefulWidget {
  final String tid;

  const _FavoriteNoteDialog({required this.tid});

  @override
  State<_FavoriteNoteDialog> createState() => _FavoriteNoteDialogState();
}

class _FavoriteNoteDialogState extends State<_FavoriteNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('收藏帖子 #${widget.tid}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 100,
        decoration: const InputDecoration(
          hintText: '备注（可选）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('收藏'),
        ),
      ],
    );
  }
}

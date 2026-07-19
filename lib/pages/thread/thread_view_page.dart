import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:dio/dio.dart';
import '../../widgets/page_actions.dart';
import '../../config/site_config.dart';
import '../../widgets/rate_dialog.dart';
import '../../widgets/kick_dialog.dart';
import '../../widgets/favorite_dialog.dart';
import '../../widgets/page_error_widget.dart';
import '../../widgets/thread_post_card.dart';
import '../../api/forum/viewthread/detail/export.dart' as detail_api;
import '../../api/forum/viewthread/action/export.dart' as action_api;
import '../../services/api_service.dart';
import '../../core/logger.dart';
import '../../models/thread_detail.dart';
import '../../models/browse_record.dart';
import '../../providers/history_provider.dart';
import '../../auth/providers/auth_provider.dart';
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
class ThreadViewPage extends StatefulWidget {
  final String tid;
  final int initialPage;
  final String? pid;

  const ThreadViewPage({
    super.key,
    required this.tid,
    this.initialPage = 1,
    this.pid,
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

  // ---- pid 定位 ----
  final Map<String, GlobalKey> _postKeys = {};

  // ---- 操作状态 ----
  bool _liked = false;
  bool _favorited = false;

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
      final page1Result = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: 1,
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
      context.read<HistoryProvider>().addRecord(
        BrowseRecord(
          id: 'thread_${widget.tid}',
          type: 'thread',
          title: title,
          routePath: '/thread/${widget.tid}',
          timestamp: DateTime.now(),
          info: {
            'tid': widget.tid,
            'title': d.title,
            'author': d.mainPost?.username ?? '',
            'authorUid': d.mainPost?.uid ?? '',
            'time': d.mainPost?.postTime ?? '',
            'url':
                '${SiteConfig.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}',
          },
        ),
      );

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
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: page,
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
    detail_api
        .getThreadDetail(ApiService().dio, tid: widget.tid, page: page)
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
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: 1,
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

  Future<void> _handleRecommend(PostItem post) async {
    if (post.recommendUrl.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    try {
      final result = await action_api.doRecommend(
        ApiService().dio,
        post.recommendUrl,
      );
      if (!mounted) return;
      if (result.success) setState(() => _liked = !_liked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message.isNotEmpty ? result.message : '操作成功'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _handleFavorite(PostItem post) async {
    if (post.favoriteUrl.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final result = await showFavoriteDialog(context, '', post.favoriteUrl);
    if (result == true && mounted) setState(() => _favorited = true);
  }

  Future<void> _handleRate(PostItem post) async {
    if (post.rateUrl.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    await showRateDialog(context, '', post.rateUrl);
  }

  Future<void> _handleKick(PostItem post) async {
    if (post.kickUrl.isEmpty) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    final result = await showKickDialog(context, '', post.kickUrl);
    if (result == true && mounted) _loadInitial();
  }

  void _showBbcodeDialog(PostItem post) {
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
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade800,
            height: 1.5,
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
        if (time.isNotEmpty)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('发表于 $time')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取详情失败: $e')));
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  void _showPagePicker() {
    final controller = TextEditingController(text: '$_currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳转页码'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入页码',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(controller.text);
              if (p != null && p >= 1 && p <= _totalPages) {
                Navigator.of(ctx).pop();
                _goToPage(p);
              }
            },
            child: const Text('跳转'),
          ),
        ],
      ),
    );
  }

  // ==================== 导航 ====================

  void _navigateComment() {
    if (_data == null) return;
    context.push('/editor?type=comment&tid=${widget.tid}');
  }

  // ==================== Build ====================

  String get _threadUrl =>
      '${SiteConfig.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _data?.title.isNotEmpty == true ? _data!.title : '帖子详情',
          style: const TextStyle(fontSize: 15),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          PageActions(
            url: _threadUrl,
            onRefresh: () => _loadInitial(),
            loading: _loading,
            copyLabel: '复制帖子链接',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_loading)
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          if (_error != null)
            return PageErrorWidget(
              message: _error!,
              onRetry: () => _loadInitial(),
            );
          if (_data == null) return const Center(child: Text('暂无数据'));
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
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(flex: 2, child: _buildCommentColumn()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    final currentPosts = _commentPages[_currentPage];
    if ((currentPosts == null || currentPosts.isEmpty) &&
        _data!.mainPost == null &&
        !_pageLoading) {
      return const Center(child: Text('暂无数据'));
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
            ],
            SliverPersistentHeader(
              pinned: true,
              delegate: CommentHeaderDelegate(
                child: CommentSection.buildHeader(
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
      onScrollNotification: _handleScrollNotification,
      onReply: (post) =>
          context.push('/editor?type=reply&tid=${widget.tid}&pid=${post.pid}'),
      onRecommend: _handleRecommend,
      onFavorite: _handleFavorite,
      onRate: _handleRate,
      onKick: _handleKick,
      onPopupAction: (action, post) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
        }
      },
    );
  }

  Widget _buildCommentColumn() {
    return Column(
      children: [
        CommentSection.buildHeader(
          currentPage: _currentPage,
          totalPages: _totalPages,
          pageLoading: _pageLoading,
          onPrev: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          onNext: _currentPage < _totalPages
              ? () => _goToPage(_currentPage + 1)
              : null,
          onPageTap: _showPagePicker,
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
      isFavorited: _favorited,
      tid: widget.tid,
      onTap: () => setState(() => _mainPostLoaded = true),
      onRecommend: () => _handleRecommend(post),
      onFavorite: () => _handleFavorite(post),
      onRate: () => _handleRate(post),
      onKick: () => _handleKick(post),
      onPopupAction: (action) {
        switch (action) {
          case PostCardAction.showBbcode:
            _showBbcodeDialog(post);
          case PostCardAction.editPost:
            _editPost(post);
          case PostCardAction.viewTime:
            _fetchPostDetailInfo(post);
        }
      },
    );
  }

  // ==================== 杂项组件 ====================

  Widget _buildReplyBar() {
    if (_data == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 16, color: Colors.grey.shade400),
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
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '说点什么...',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.send_rounded, color: Colors.deepPurple.shade400),
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

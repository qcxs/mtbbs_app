import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:html/parser.dart' as htmlParser;
import '../../widgets/page_actions.dart';
import '../../config/site_config.dart';
import '../../widgets/rate_dialog.dart';
import '../../widgets/kick_dialog.dart';
import '../../widgets/favorite_dialog.dart';
import '../../widgets/thread_post_card.dart';
import '../../widgets/thread_comment_list.dart';
import '../../widgets/page_error_widget.dart';
import '../../services/thread_detail_api.dart';
import '../../services/api_service.dart';
import '../../core/logger.dart';
import '../../models/thread_detail.dart';
import '../../models/browse_record.dart';
import '../../providers/history_provider.dart';
import '../../api/forum/viewthread/action/export.dart' as action_api;
import '../../auth/providers/auth_provider.dart';
import '../../providers/settings_provider.dart';

/// 帖子浏览页（渲染 BBCode）
///
/// 宽屏（> 600px）时评论显示在右侧，窄屏时显示在底部。
/// 加载策略：不论指定 [initialPage] 为何值，先加载第 1 页获取帖子信息和总页数，
/// 若 [initialPage] > 1 且不超过总页数，再加载该页的评论替换第 1 页的评论。
class ThreadViewPage extends StatefulWidget {
  final String tid;

  /// 目标页码。默认 1。
  /// 设为 > 1 时：先加载第 1 页获取帖子信息，再加载此页评论。
  final int initialPage;

  const ThreadViewPage({super.key, required this.tid, this.initialPage = 1});

  @override
  State<ThreadViewPage> createState() => _ThreadViewPageState();
}

class _ThreadViewPageState extends State<ThreadViewPage> {
  ThreadViewData? _data; // 帖子信息（来自第 1 页）
  List<PostItem> _allPosts = []; // 评论列表（来自目标页 + 加载更多）
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _error;

  /// 当前评论列表所在的页码（区别于 _data.currentPage 来自第 1 页）
  int _commentsPage = 0;

  // 操作状态
  bool _liked = false;
  bool _favorited = false;

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _navigateReply(String pid, String username) {
    if (_data == null) return;
    context.push('/editor?type=reply&tid=${widget.tid}&pid=$pid');
  }

  void _navigateComment() {
    if (_data == null) return;
    context.push('/editor?type=comment&tid=${widget.tid}');
  }

  /// 两步加载：
  /// 1. 始终加载第 1 页 → 获取帖子信息、总页数
  /// 2. 若 initialPage > 1 且 <= 总页数，加载对应页的评论
  Future<void> _loadThread() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1：加载第 1 页（帖子信息）
      final page1Data = await ThreadDetailApi.fetch(widget.tid, page: 1);
      if (!mounted) return;
      final d = page1Data!;

      // 保存帖子信息和浏览记录
      final title = d.title.isNotEmpty ? d.title : '帖子${widget.tid}';
      final routePath = widget.initialPage > 1
          ? '/thread/${widget.tid}?page=${widget.initialPage}'
          : '/thread/${widget.tid}';
      context.read<HistoryProvider>().addRecord(
        BrowseRecord(
          id: 'thread_${widget.tid}',
          type: 'thread',
          title: title,
          routePath: routePath,
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

      AppLogger.i(
        'PAGE',
        'ThreadViewPage loaded: tid=${widget.tid}, title=$title, totalPages=${d.totalPages}',
      );

      setState(() {
        _data = d;
        _liked = d.mainPost?.isLiked ?? false;
      });

      // Step 2：确定评论来自哪一页
      int targetPage;
      if (widget.initialPage > 1 && widget.initialPage <= d.totalPages) {
        targetPage = widget.initialPage;
      } else {
        targetPage = 1;
      }

      if (targetPage == 1) {
        // 直接使用第 1 页的评论
        setState(() {
          _allPosts = List<PostItem>.from(d.posts);
          _commentsPage = 1;
          _hasMore = d.totalPages > 1;
          _loading = false;
        });
      } else {
        // 加载目标页的评论（忽略第 1 页的评论）
        try {
          final targetData = await ThreadDetailApi.fetch(
            widget.tid,
            page: targetPage,
          );
          if (!mounted) return;

          // 论坛对超出范围的 page 会返回最后一页，用实际返回的 page 更新
          final actualPage = targetData!.currentPage;
          setState(() {
            _allPosts = List<PostItem>.from(targetData.posts);
            _commentsPage = actualPage;
            _hasMore = actualPage < targetData.totalPages;
            _loading = false;
          });

          AppLogger.i(
            'PAGE',
            'ThreadViewPage target page: requested=$targetPage, actual=$actualPage, ${targetData.posts.length} posts',
          );
        } catch (e) {
          // 目标页加载失败，回退到第 1 页的评论
          if (!mounted) return;
          AppLogger.w('PAGE', 'ThreadViewPage target page load failed: $e');
          setState(() {
            _allPosts = List<PostItem>.from(d.posts);
            _commentsPage = 1;
            _hasMore = d.totalPages > 1;
            _loading = false;
          });
        }
      }
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

  /// 刷新：重新执行完整两步加载
  Future<void> _onRefresh() => _loadThread();

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
      if (result.success) {
        setState(() => _liked = !_liked);
      }
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
    if (result == true && mounted) {
      setState(() => _favorited = true);
    }
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
    if (result == true && mounted) {
      _loadThread();
    }
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
    final type = isOp ? 'editPost' : 'editReply';
    context.push('/editor?type=$type&tid=${widget.tid}&pid=${post.pid}');
  }

  /// 通过 repquote 获取帖子/评论的详细时间信息
  Future<void> _fetchPostDetailInfo(PostItem post) async {
    final url =
        '/forum.php?mod=post&action=reply&fid=2&tid=${widget.tid}&repquote=${post.pid}&page=1';
    try {
      final resp = await ApiService().dio.get<String>(url);
      if (!mounted) return;
      final body = resp.data is String ? (resp.data as String) : '';
      final doc = htmlParser.parse(body);

      String? extractField(String name) {
        final el = doc.querySelector('input[name="$name"]');
        return el?.attributes['value'];
      }

      final noticetrimstr = extractField('noticetrimstr') ?? '';

      String? postTime;
      final timeMatch = RegExp(
        r'发表于\s+(\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2})',
      ).firstMatch(noticetrimstr);
      if (timeMatch != null) {
        postTime = timeMatch.group(1);
      }

      if (mounted) {
        final time = postTime ?? post.postTime;
        if (time.isNotEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('发表于 $time')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取详情失败: $e')));
    }
  }

  // ==================== 回复/编辑/动作 ====================

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)),
    );
  }

  void _onLoadMore() async {
    if (_isLoadingMore || !_hasMore || _data == null) return;
    final nextPage = _commentsPage + 1;
    if (nextPage > _data!.totalPages) return;

    setState(() => _isLoadingMore = true);

    try {
      final data = await ThreadDetailApi.fetch(widget.tid, page: nextPage);
      if (!mounted) return;
      final d = data!;
      setState(() {
        _allPosts.addAll(d.posts);
        _commentsPage = d.currentPage; // 使用实际返回的页码
        _hasMore = d.currentPage < d.totalPages;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        AppLogger.w('PAGE', 'ThreadViewPage load more error: $e');
        setState(() => _isLoadingMore = false);
      }
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      final metrics = notification.metrics;
      if (metrics.maxScrollExtent > 0 &&
          metrics.pixels >= metrics.maxScrollExtent - 280) {
        _onLoadMore();
      }
    }
    return false;
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
            onRefresh: () => _loadThread(),
            loading: _loading,
            copyLabel: '复制帖子链接',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (_loading) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (_error != null) {
            return PageErrorWidget(
              message: _error!,
              onRetry: () => _loadThread(),
            );
          }
          if (_data == null) return const Center(child: Text('暂无数据'));

          final isWide = constraints.maxWidth > 600;
          if (isWide) return _buildWideLayout();
          return _buildNarrowLayout();
        },
      ),
      bottomNavigationBar: _buildReplyBar(),
    );
  }

  // ==================== 宽屏布局 ====================

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
              if (_data!.mainPost != null) ...[
                _buildMainPostCard(_data!.mainPost!),
                const Divider(height: 1),
              ],
            ],
          ),
        ),
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(flex: 2, child: _buildCommentSection()),
      ],
    );
  }

  // ==================== 窄屏布局 ====================

  Widget _buildNarrowLayout() {
    if (_allPosts.isEmpty && _data!.mainPost == null) {
      return const Center(child: Text('暂无数据'));
    }

    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            if (_data!.title.isNotEmpty)
              SliverToBoxAdapter(child: _buildTitleSection()),
            if (_data!.mainPost != null) ...[
              SliverToBoxAdapter(child: _buildMainPostCard(_data!.mainPost!)),
              SliverToBoxAdapter(child: const Divider(height: 1)),
            ],
            SliverToBoxAdapter(
              child: ThreadCommentList(
                posts: _allPosts,
                tid: widget.tid,
                isLoadingMore: _isLoadingMore,
                hasMore: _hasMore,
                isLoggedIn: auth.isLoggedIn,
                currentUid: auth.uid,
                globalDisabledTags: settings.disabledBbcodeTags,
                scrollable: false,
                onRefresh: _onRefresh,
                onLoadMore: _onLoadMore,
                onReply: (post) => _navigateReply(post.pid, post.username),
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
              ),
            ),
            // 底部留白，避免被回复栏遮挡最后一条
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

  // ==================== 评论区组件（供宽屏使用）====================

  Widget _buildCommentSection() {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    return ThreadCommentList(
      posts: _allPosts,
      tid: widget.tid,
      isLoadingMore: _isLoadingMore,
      hasMore: _hasMore,
      isLoggedIn: auth.isLoggedIn,
      currentUid: auth.uid,
      globalDisabledTags: settings.disabledBbcodeTags,
      onRefresh: _onRefresh,
      onScrollNotification: _handleScrollNotification,
      onLoadMore: _onLoadMore,
      onReply: (post) => _navigateReply(post.pid, post.username),
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

  // ==================== 主帖卡片 ====================

  Widget _buildMainPostCard(PostItem post) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    return ThreadPostCard(
      post: post,
      index: 0,
      tid: widget.tid,
      isLiked: _liked,
      isFavorited: _favorited,
      isLoggedIn: auth.isLoggedIn,
      currentUid: auth.uid,
      globalDisabledTags: settings.disabledBbcodeTags,
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

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
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/dialog/page_jump_dialog.dart';
import 'package:mtbbs/widgets/dialog/rate_dialog.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as detail_api;
import 'package:mtbbs/api/forum/viewthread/action/export.dart' as action_api;
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/pages/editor/editor_session.dart';
import 'package:mtbbs/pages/editor/editor_draft_handoff.dart';
import 'package:mtbbs/pages/editor/forum_image_upload.dart';
import 'package:mtbbs/pages/editor/mt_image_sheet.dart';
import 'package:mtbbs/services/mt_image_hosting.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/widgets/editor/mini_editor_bar.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/pages/thread/thread_view_comment_section.dart';
import 'package:mtbbs/pages/thread/thread_view_main_post.dart';
import 'package:mtbbs/pages/thread/thread_favorite_note_dialog.dart';

part 'thread_view_actions.dart';
part 'thread_view_layout.dart';

/// Esc 在迷你编辑器展开时：先收起编辑器（不退出页面）
class _CollapseMiniEditorIntent extends Intent {
  const _CollapseMiniEditorIntent();
}

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

  // ---- 迷你编辑器（评论 / 回复某评论，共享内核） ----
  late final EditorSession _editorSession;
  final MtImageHosting _mtImageHosting = MtImageHosting();
  bool _editorExpanded = false;
  bool _editorSubmitting = false;

  /// 当前回复目标（null = 评论帖子；非空 = 回复该评论）
  String? _replyTargetName;
  String? _replyTargetPid;

  @override
  void initState() {
    super.initState();
    // 默认目标是"评论帖子"；用户点某条评论的"回复"会 switchTarget 到 reply
    _editorSession = EditorSession(
      editorType: EditorType.comment,
      tid: widget.tid,
    );
    _loadInitial();
  }

  @override
  void dispose() {
    _editorSession.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
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

  Future<void> _loadCommentPage(int page, {bool force = false}) async {
    if (_pageLoading) return;
    if (!force && _commentPages.containsKey(page)) return;
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

  Future<void> _onRefresh() async {
    AppLogger.i('PAGE', 'refresh: page1 + page$_currentPage');
    // 先请求第 1 页（主帖 + 第 1 页评论），成功才整体替换，失败保留旧内容
    try {
      await EmojiService().load();
      final raw = await detail_api.getThreadDetail(
        ApiService().dio,
        tid: widget.tid,
        page: 1,
        authorid: widget.authorid,
      );
      if (raw['success'] != true) {
        throw Exception(raw['message']?.toString() ?? '加载失败');
      }
      if (!mounted) return;
      final d = ThreadViewData.fromMap(raw, widget.tid);
      setState(() {
        _commentPages[1] = List<PostItem>.from(d.posts);
        _totalPages = d.totalPages;
        _data = d;
        _liked = d.mainPost?.isLiked ?? false;
      });
      AppLogger.i('PAGE', 'refresh page1 ok (${d.posts.length} posts)');
    } catch (e) {
      AppLogger.w('PAGE', 'refresh page1 failed: $e');
    }
    // 当前不在第 1 页时，强制刷新当前评论页（需要时由 _loadCommentPage 自行合并）
    if (_currentPage != 1 && mounted) {
      await _loadCommentPage(_currentPage, force: true);
    }
  }

  // ==================== Build ====================

  String get _threadUrl =>
      '${SiteStore.instance.baseUrl}/forum.php?mod=viewthread&tid=${widget.tid}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    // 双栏布局判定统一走 isWide（横屏且足够宽），与全项目语义一致
    final isWide = size.isWide;
    final isNarrow = !isWide;
    final page = Scaffold(
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
          // 全局禁用样式 toggle（刷新按钮左侧）。
          // 激活态用 primary（切换生效），不用 error（非错误语义）
          IconButton(
            icon: Text(
              _globalDisableStyle ? 'T̶' : 'T',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _globalDisableStyle ? cs.primary : cs.onSurfaceVariant,
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
          if (isWide) return _buildWideLayout();
          return _buildNarrowLayout();
        },
      ),
      bottomNavigationBar: _editorExpanded
          ? _buildMiniEditor()
          : _buildReplyBar(),
    );
    return _wrapBackToCollapse(page);
  }

  /// 迷你编辑器展开时：Esc / 手机返回**先收起编辑器**，再按才真正返回。
  ///
  /// - Esc：页面级 [Shortcuts] 覆盖全局 `GoBackIntent`（最近者优先），收起即可
  /// - Android 返回：`PopScope(canPop: false)` 拦下本次 pop 并收起
  /// 未展开时原样返回，交回全局 Esc / GoRouter 默认返回行为。
  Widget _wrapBackToCollapse(Widget child) {
    if (!_editorExpanded) return child;
    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.escape):
            const _CollapseMiniEditorIntent(),
      },
      child: Actions(
        actions: {
          _CollapseMiniEditorIntent: CallbackAction<_CollapseMiniEditorIntent>(
            onInvoke: (_) {
              _collapseEditor();
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _collapseEditor();
          },
          child: child,
        ),
      ),
    );
  }
}

import 'dart:async';

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
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';
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
import 'package:mtbbs/pages/editor/forum_image_drawer.dart';
import 'package:mtbbs/pages/editor/forum_image_controller.dart';
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
import 'package:mtbbs/pages/thread/thread_share_page.dart';
import 'package:mtbbs/services/thread_cache_service.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/core/utils/formatters.dart';

part 'thread_view_actions.dart';
part 'thread_view_cache.dart';
part 'thread_view_editor.dart';
part 'thread_view_layout.dart';
part 'thread_view_load.dart';
part 'thread_view_offline.dart';

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
/// - [cacheKey]：只读缓存模式（从 `threads.sembast` 读快照），
///   不发网络请求、不写缓存、不显示回复栏；布局与正常帖子页完全一致。
class ThreadViewPage extends StatefulWidget {
  final String tid;
  final int initialPage;
  final String? pid;
  final String? authorid;

  /// 快照存储键（`auto|...` / `offline|...`）；非空即只读缓存模式
  final String? cacheKey;

  const ThreadViewPage({
    super.key,
    required this.tid,
    this.initialPage = 1,
    this.pid,
    this.authorid,
    this.cacheKey,
  });

  /// 从缓存键构造只读页（键内含 tid，避免路由再传一份）
  factory ThreadViewPage.cached({Key? key, required String cacheKey}) {
    final parts = cacheKey.split('|');
    final tid = parts.length >= 5
        ? parts[3]
        : (parts.length == 3 ? parts[2] : '');
    return ThreadViewPage(key: key, tid: tid, cacheKey: cacheKey);
  }

  /// 打开只读缓存页（通过路由，支持深链）
  static Future<void> openCached(
    BuildContext context, {
    required String key,
  }) async {
    await context.push<void>(
      '/thread/cache?key=${Uri.encodeQueryComponent(key)}',
    );
  }

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

  // ---- 帖子缓存 ----
  /// 自动缓存键（写入成功后可用；评论页回写需要）
  String? _autoCacheKey;
  Future<String?>? _autoCachePending;

  /// 加载失败时可选的缓存快照
  List<ThreadSnapshotMeta> _errorCacheCandidates = const [];

  /// 只读缓存模式下当前快照
  ThreadSnapshot? _cacheSnapshot;

  /// 是否只读缓存模式（终态，不随运行变化）
  bool get _isCacheMode => widget.cacheKey != null;

  /// 当前帖子是否已收藏（收藏成功后置 true，仅本次会话有效）
  bool _favorited = false;

  /// 收藏提交中（禁用按钮）
  bool _favoriting = false;

  /// 顶栏"全局禁用样式"开关（作用于当前帖子页所有帖子）
  bool _globalDisableStyle = false;

  // ---- 迷你编辑器（评论 / 回复某评论，共享内核） ----
  late final EditorSession _editorSession;
  final MtImageHosting _mtImageHosting = MtImageHosting();

  /// 迷你编辑器图片管理（与完整编辑器共用同一实现；页面内持久，供工具栏角标）
  late final ForumImageController _images;
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
    _images = ForumImageController(
      contentCtl: _editorSession.contentCtl,
      pageData: () => _editorSession.pageData,
      uid: () => context.read<AuthProvider>().uid,
      fallbackTid: widget.tid,
    )..addListener(_onImagesChanged);
    if (_isCacheMode) {
      _loadCacheInitial();
    } else {
      _loadInitial();
    }
  }

  @override
  void dispose() {
    _images.removeListener(_onImagesChanged);
    _images.dispose();
    _editorSession.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 图片管理数据变更 → 重建（迷你编辑器工具栏角标随之刷新）
  void _onImagesChanged() => _setState(() {});

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
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
          onTap: _scrollToTop,
          child: Text(
            _data?.title.isNotEmpty == true
                ? _data!.title
                : (_isCacheMode ? '帖子缓存' : '帖子详情'),
            style: const TextStyle(fontSize: 15),
          ),
        ),
        surfaceTintColor: cs.surface,
        actions: [
          if (!_isCacheMode &&
              isNarrow &&
              _data != null &&
              _commentPages.isNotEmpty)
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
            onRefresh: _isCacheMode ? _loadCacheInitial : () => _loadInitial(),
            loading: _loading,
            copyLabel: '复制帖子链接',
            extraItems: () {
              if (_isCacheMode) {
                return <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'switch_version',
                    child: Row(
                      children: [
                        Icon(Icons.layers_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('切换版本'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'reload_latest',
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('重新加载最新'),
                      ],
                    ),
                  ),
                ];
              }
              final tidNum = int.tryParse(widget.tid);
              return <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'view_cache',
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 18),
                      const SizedBox(width: 8),
                      const Text('查看历史缓存'),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'save_offline',
                  enabled: _data?.mainPost != null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.download_outlined,
                        size: 18,
                        color: _data?.mainPost != null
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                      const SizedBox(width: 8),
                      const Text('保存离线副本'),
                    ],
                  ),
                ),
                if (tidNum != null) ...[
                  const PopupMenuDivider(),
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
                ],
              ];
            }(),
            onExtraSelected: (action) {
              if (_isCacheMode) {
                switch (action) {
                  case 'switch_version':
                    _switchCachedVersion();
                  case 'reload_latest':
                    _reloadLatestFromCache();
                }
                return;
              }
              switch (action) {
                case 'view_cache':
                  _handleViewCached();
                  return;
                case 'save_offline':
                  _handleSaveOffline();
                  return;
              }
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
      // 迷你编辑器 / 回复栏放在 body 的 Column 内（而非 bottomNavigationBar）：
      // Scaffold 的 bottomNavigationBar 不随键盘 viewInsets 上移，会被虚拟键盘遮挡；
      // 放进 body 后随 body 一起收缩，编辑器始终停在键盘上方。
      // 与私信页（pm_chat_page）保持同一范式。
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (_loading) return const LoadingView();
                if (_error != null)
                  return PageErrorWidget(
                    message: _error!,
                    onRetry: _isCacheMode
                        ? _loadCacheInitial
                        : () => _loadInitial(),
                    extraActions: [
                      if (!_isCacheMode &&
                          _errorCacheCandidates.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              _openCachedPicker(metas: _errorCacheCandidates),
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('查看缓存'),
                        ),
                      if (!_isCacheMode &&
                          ThreadCacheService.instance.isDisabled)
                        Text(
                          '缓存不可用',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  );
                if (_data == null) return const EmptyView(text: '暂无数据');
                if (isWide) {
                  return _isCacheMode
                      ? Column(
                          children: [
                            _buildCacheBanner(),
                            Expanded(child: _buildWideLayout()),
                          ],
                        )
                      : _buildWideLayout();
                }
                return _buildNarrowLayout();
              },
            ),
          ),
          if (!_isCacheMode)
            _editorExpanded ? _buildMiniEditor() : _buildReplyBar(),
        ],
      ),
    );
    return _wrapBackToCollapse(page);
  }

  /// 迷你编辑器展开时：Esc / 手机返回**先收起编辑器**，再按才真正返回。
  ///
  /// - Esc：页面级 [Shortcuts] 覆盖全局 `GoBackIntent`（最近者优先），收起即可
  /// - Android 返回：`PopScope(canPop: false)` 拦下本次 pop 并收起
  /// 收起时各层为空操作，交回全局 Esc / GoRouter 默认返回行为。
  ///
  /// **必须结构恒定**：不能"收起时直接 `return child`、展开时才包壳"——那样根 widget
  /// 类型在收起 ↔ 展开间变化，Flutter 会整棵子树重建，`ScrollView` 的 `ScrollPosition`
  /// 随之丢弃，帖子阅读进度归零（回到顶部）。这里改为始终返回同一套外壳，
  /// 只让快捷键表 / 动作表 / `canPop` 随 `_editorExpanded` 变化。
  Widget _wrapBackToCollapse(Widget child) {
    return Shortcuts(
      shortcuts: _editorExpanded
          ? {
              SingleActivator(LogicalKeyboardKey.escape):
                  const _CollapseMiniEditorIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: _editorExpanded
            ? {
                _CollapseMiniEditorIntent:
                    CallbackAction<_CollapseMiniEditorIntent>(
                      onInvoke: (_) {
                        _collapseEditor();
                        return null;
                      },
                    ),
              }
            : const <Type, Action<Intent>>{},
        child: PopScope(
          canPop: !_editorExpanded,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _collapseEditor();
          },
          child: child,
        ),
      ),
    );
  }
}

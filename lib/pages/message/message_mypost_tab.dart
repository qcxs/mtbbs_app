import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/app/notice_badge.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/models/post_preview.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/widgets/layout/load_more_footer.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';

/// 「我的帖子」分组配置（唯一数据源：lib/config/notice_config.dart）
final NoticeGroup _mypostGroup = noticeGroupOf('mypost')!;

/// 我的帖子 Tab
class MypostTab extends StatefulWidget {
  const MypostTab({super.key});

  @override
  State<MypostTab> createState() => _MypostTabState();
}

class _MypostTabState extends State<MypostTab> {
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;

  /// 当前请求的子类型；空串 = 尚未确定 → **不传 type**，交给站点挑
  /// 「第一个有未读的子类型」（Discuz 的 `$deftype`）。这样打开「我的帖子」
  /// 时看到的就是真正有新消息的那个子类型（可能是「点评」而不是「帖子」）。
  String _type = '';

  /// 用户是否手动点过子类型（点过就不再被站点默认值覆盖）
  bool _typePicked = false;

  final _nav = NoticeNavStore.instance;

  /// 子类型页控制器：**二级**子类型（帖子/评分/点评…）之间可左右滑动；
  /// 一级 Tab（我的消息/我的帖子…）只点击切换（见 message_page.dart）。
  /// 首次确定默认子类型后才创建，`initialPage` 直接落在该子类型上。
  PageController? _pc;

  /// 上一次的子类型集合（检测站点增删 → 对齐页位置）
  String _typesKey = '';

  List<NoticeType> get _types =>
      _nav.subtypesOf('mypost') ?? _mypostGroup.types;

  final Map<int, PostPreviewData?> _previews = {};
  final Set<int> _previewLoading = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(1);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pc?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final result = await mypost_api.getMypostList(
        ApiService().dio,
        page: page,
        type: _type,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() {
          _error = result['message'] as String? ?? '加载失败';
          _loading = false;
        });
        return;
      }
      _applyNav(result['nav']);
      if (!mounted) return;
      setState(() {
        _items = (result['items'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _page = result['currentPage'] as int? ?? page;
        _totalPages = result['totalPages'] as int? ?? 1;
        _hasMore = _page < _totalPages;
        _loading = false;
        _previews.clear();
        _previewLoading.clear();
      });
      // 自动触发预览请求
      for (int i = 0; i < _items.length; i++) {
        _tryFetchPreview(i);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final result = await mypost_api.getMypostList(
        ApiService().dio,
        page: next,
        type: _type,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        setState(() => _loadingMore = false);
        return;
      }
      final start = _items.length;
      setState(() {
        _items.addAll(
          (result['items'] as List<dynamic>).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        );
        _page = result['currentPage'] as int? ?? next;
        _totalPages = result['totalPages'] as int? ?? _totalPages;
        _hasMore = _page < _totalPages;
        _loadingMore = false;
      });
      // 只给新追加的条目拉预览
      for (int i = start; i < _items.length; i++) {
        _tryFetchPreview(i);
      }
    } catch (e) {
      if (!mounted) return;
      AppLogger.w('PAGE', 'MypostTab loadMore error: $e');
      setState(() => _loadingMore = false);
    }
  }

  /// 用页面自带的导航与计数校正 UI（站点会按权限/配置增删，见 NoticeNavStore）：
  /// - 尚未手动选过子类型 → 采用站点本次实际打开的那个（= 有未读的那个）
  /// - 分组徽标用页面的**权威计数**覆盖（不能"整组清零"猜：打开「帖子」时
  ///   未读可能全在「点评」上，服务端什么都没置已读）
  void _applyNav(Object? nav) {
    if (nav is! Map) return;
    _nav.syncFromPage(Map<String, dynamic>.from(nav), requestedView: 'mypost');
    final types = _types;
    if (!_typePicked) {
      final active = types.isEmpty ? '' : _nav.activeSubtypeFor('mypost');
      final next = active.isNotEmpty
          ? active
          : (types.isNotEmpty ? types.first.id : '');
      if (next.isNotEmpty && next != _type) {
        setState(() {
          _type = next;
          // 首次确定默认子类型 → 就地建页控制器（初始页 = 该子类型）
          _pc ??= PageController(initialPage: _indexOfType(types, next));
        });
      } else if (types.isEmpty && _type.isNotEmpty) {
        setState(() => _type = '');
      }
    }
    NoticeBadgeController.instance.applyViewCounts(_nav.viewCounts);
    // 本次拉取已把该子类型的条目置为已读 → 立刻清零它的未读。
    // （子类型计数只可能来自"打开过的提醒页"，header 探测给不到，不清就永远是旧值）
    final activeType = types.isEmpty
        ? ''
        : (_type.isNotEmpty ? _type : _nav.activeSubtypeFor('mypost'));
    if (activeType.isNotEmpty) {
      _nav.markSubtypeRead('mypost', activeType);
    } else if (types.isEmpty) {
      // 无子类型的视图：没有可求和的子类型，直接乐观清零本视图计数
      NoticeBadgeController.instance.markViewRead('mypost');
    }
  }

  void _switchType(String type) {
    if (type == _type) return;
    // 用户手动选过之后，不再被站点默认子类型覆盖
    _typePicked = true;
    setState(() {
      _type = type;
      // 兜底：首次加载尚未确定默认子类型时（_pc 还没建）用户就点了 chip →
      // 这里补建，保证之后二级仍可左右滑动
      if (_pc == null) {
        final types = _types;
        if (types.isNotEmpty) {
          _pc = PageController(initialPage: _indexOfType(types, type));
        }
      }
      _previews.clear();
      _previewLoading.clear();
    });
    _load(1);
  }

  /// 点 chip：优先用页控制器**滑动**过去（onPageChanged 里再真正切换+加载）；
  /// 无控制器（尚未确定默认子类型）时退化为直接切换。
  void _selectType(String type) {
    if (type == _type) return;
    _typePicked = true;
    final pc = _pc;
    final i = _indexOfType(_types, type);
    if (pc != null && pc.hasClients && i >= 0) {
      pc.animateToPage(
        i,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _switchType(type);
    }
  }

  int _indexOfType(List<NoticeType> types, String id) {
    final i = types.indexWhere((t) => t.id == id);
    return i < 0 ? 0 : i;
  }

  /// 当前展示的子类型在 [types] 中的下标（`_type` 未定时取 0）
  int _currentIndex(List<NoticeType> types) => _indexOfType(types, _type);

  // ==================== 预览逻辑 ====================

  Future<void> _tryFetchPreview(int index) async {
    if (index >= _items.length) return;
    if (_previews.containsKey(index)) return;

    final item = _items[index];
    final viewUrl = item['viewUrl'] as String? ?? '';
    final ids = parseViewUrl(viewUrl);
    if (ids == null) return;

    // 先查缓存
    final cached = PostPreviewManager.instance.getCached(ids.tid, ids.pid);
    if (cached != null) {
      if (mounted) setState(() => _previews[index] = cached);
      return;
    }

    setState(() => _previewLoading.add(index));
    final data = await PostPreviewManager.instance.fetch(ids.tid, ids.pid);
    if (!mounted) return;
    setState(() {
      _previews[index] = data;
      _previewLoading.remove(index);
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    // 订阅站点导航：子类型未读数变化（读完清零）时刷新 chip
    context.watch<NoticeNavStore>();
    // 子类型 chip 常驻：某个子类型为空时也要能切到别的类型（7 个子类型尤其需要）
    final types = _types;

    // 站点增删子类型 → 把页位置对齐到当前子类型
    final key = types.map((t) => t.id).join(',');
    if (key != _typesKey) {
      _typesKey = key;
      final pc0 = _pc;
      if (pc0 != null && types.isNotEmpty) {
        final target = _currentIndex(types);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && pc0.hasClients && pc0.page?.round() != target) {
            pc0.jumpToPage(target);
          }
        });
      }
    }

    final pc = _pc;
    // 无子类型，或默认子类型尚未确定 → 单块内容（含加载 / 错误 / 空态）
    if (types.isEmpty || pc == null) {
      return Column(
        children: [
          _buildHeader(),
          Expanded(child: _body()),
        ],
      );
    }

    // 二级子类型之间可左右滑动；一级 Tab 只点击（见 message_page.dart）
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: PageView.builder(
            controller: pc,
            itemCount: types.length,
            onPageChanged: (i) => _switchType(types[i].id),
            itemBuilder: (_, i) =>
                i == _currentIndex(types) ? _body() : const LoadingView(),
          ),
        ),
      ],
    );
  }

  /// 当前子类型的内容块：加载 / 错误 / 空 / 列表 + 分页
  Widget _body() {
    if (_loading) return const LoadingView();
    if (_error != null) {
      return PageErrorWidget(
        message: _error!,
        onRetry: () => _load(1),
        showBack: false,
      );
    }
    if (_items.isEmpty) {
      return const EmptyView(icon: Icons.forum_outlined, text: '暂无提醒');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification) _onScroll();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(1),
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: _items.length + (_loadingMore || !_hasMore ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= _items.length) {
              return LoadMoreFooter(loading: _loadingMore, hasMore: _hasMore);
            }
            return _buildItem(_items[i], i);
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(vertical: 4),
      // 7 个子类型窄屏放不下 → 横向可滚动
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final t in _types) ...[
              _subTab(t.label, t.id),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subTab(String label, String type) {
    final cs = Theme.of(context).colorScheme;
    final active = _type == type;
    // 子类型未读：来自页面子栏的权威计数（服务端置已读之后的值）
    final count = _nav.subtypeCount('mypost', type);
    return GestureDetector(
      onTap: () => _selectType(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? cs.surfaceContainerLow : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Badge(
          isLabelVisible: count > 0,
          label: Text(count > 99 ? '99+' : '$count'),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Item ====================

  Widget _buildItem(Map<String, dynamic> item, int index) {
    final cs = Theme.of(context).colorScheme;
    final uid = item['uid'] as String? ?? '';
    final username = item['username'] as String? ?? '';
    final time = item['time'] as String? ?? '';
    final timeTitle = item['timeTitle'] as String? ?? '';
    final segments = item['segments'] as List<dynamic>? ?? [];
    final viewUrl = item['viewUrl'] as String? ?? '';
    final ids = parseViewUrl(viewUrl);
    final isPreviewLoading = _previewLoading.contains(index);
    final preview = _previews[index];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：头像 + 用户名 + 时间
            Row(
              children: [
                UserAvatar(uid: uid, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    username,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (time.isNotEmpty)
                  Tooltip(
                    message: timeTitle.isNotEmpty ? timeTitle : time,
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // 通知消息体（结构化段落，标题可点击）
            if (segments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _buildSegments(segments),
              ),
            const SizedBox(height: 8),
            // 预览区
            if (isPreviewLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (preview != null && preview.bbcode.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PostHtmlWidget(
                  bbcode: preview.bbcode,
                  disabledTags: const {},
                  autoDetectUrls: context
                      .read<SettingsProvider>()
                      .autoDetectUrls,
                ),
              ),
            // 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 查看按钮
                if (viewUrl.isNotEmpty)
                  _actionBtn(
                    label: '查看',
                    onTap: () {
                      final fullUrl = normalizeUrl(viewUrl);
                      final result = UrlRouter.parse(fullUrl);
                      if (result.appPath != null && !result.isOtherSite) {
                        context.push(result.appPath!);
                      } else {
                        context.push(
                          '/browser?url=${Uri.encodeComponent(fullUrl)}&intercept=false',
                        );
                      }
                    },
                  ),
                const SizedBox(width: 6),
                // 回复按钮
                if (ids != null)
                  _actionBtn(
                    label: '回复',
                    onTap: () => context.push(
                      '/editor?type=reply&tid=${ids.tid}&pid=${ids.pid}',
                    ),
                  ),
                if (preview != null && preview.bbcode.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    onSelected: (v) {
                      if (v == 'showBbcode') {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            constraints: const BoxConstraints(
                              maxWidth: 500,
                              maxHeight: 400,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'BBCode - $username',
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
                            content: SingleChildScrollView(
                              child: SelectableText(
                                preview.bbcode,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'showBbcode',
                        child: Text(
                          '查看 BBCode',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegments(List<dynamic> segments) {
    final cs = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final style = TextStyle(fontSize: 13, color: cs.onSurface, height: 1.4);
    final linkStyle = TextStyle(
      fontSize: 13,
      color: cs.onSurfaceVariant,
      decoration: TextDecoration.underline,
      height: 1.4,
    );

    for (final seg in segments) {
      final map = seg as Map<String, dynamic>;
      final type = map['type'] as String;
      // 换行段没有文本，须在下面的 text.isEmpty 跳过之前处理
      if (type == 'br') {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      final text = map['text'] as String? ?? '';
      if (text.isEmpty) continue;

      switch (type) {
        case 'user':
          final uid = map['uid'] as String? ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: uid.isNotEmpty ? () => context.push('/user/$uid') : null,
                child: Text(text, style: linkStyle),
              ),
            ),
          );
        case 'thread':
          final url = map['url'] as String? ?? '';
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: url.isNotEmpty
                    ? () {
                        // 链接落地的唯一决策点（App 内优先，兜底内置浏览器）
                        final target = UrlRouter.resolveTarget(
                          normalizeUrl(url),
                        );
                        if (target != null) context.push(target);
                      }
                    : null,
                child: Text(text, style: linkStyle),
              ),
            ),
          );
        default:
          spans.add(TextSpan(text: text, style: style));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _actionBtn({required String label, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

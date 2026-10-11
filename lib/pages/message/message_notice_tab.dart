import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/api/home/notice/export.dart' as notice_api;
import 'package:mtbbs/config/notice_config.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/app/notice_badge.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/widgets/layout/page_error_widget.dart';
import 'package:mtbbs/widgets/layout/pagination_bar.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 提醒列表 Tab —— 承载 `do=notice` 的一个「分组」（系统提醒 / 管理工作 / 坛友互动…）
///
/// 分组与子类型来自 [noticeGroups]（唯一数据源）：
/// - 分组有子类型（如坛友互动：打招呼/好友/留言…）→ 顶部渲染子类型 chip，请求带 `type`
/// - 无子类型（系统提醒 / 管理工作）→ 直接列表，服务端一次返回全量
class NoticeTab extends StatefulWidget {
  const NoticeTab({super.key, this.view = 'system', this.emptyText = '暂无提醒'});

  /// 站内 `do=notice&view=*` 的视图名（= [NoticeGroup.id]）
  final String view;

  /// 无提醒时的空态文案
  final String emptyText;

  @override
  State<NoticeTab> createState() => _NoticeTabState();
}

class _NoticeTabState extends State<NoticeTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;

  late final NoticeGroup? _group = noticeGroupOf(widget.view);
  final _nav = NoticeNavStore.instance;

  /// 子类型页控制器：**二级**子类型之间用左右滑动切换（一级 Tab 只点击）。
  ///
  /// 首次拉到站点导航、确定默认子类型后才创建（`initialPage` 直接落在该子类型上，
  /// 避免先显示第 0 页再跳）。无子类型的视图（系统提醒/管理工作/应用提醒）恒为 null。
  PageController? _pc;

  /// 上一次的子类型集合（检测站点增删 → 对齐页位置）
  String _typesKey = '';

  /// 子类型：已同步过就用**站点返回的**（站点会按权限/配置增删），否则回退配置
  List<NoticeType> get _types =>
      _nav.subtypesOf(widget.view) ?? _group?.types ?? const [];

  /// 当前请求的子类型；空串 = 尚未确定 → **不传 type**，交给站点挑
  /// 「第一个有未读的子类型」（Discuz 的 `$deftype`，见 space_notice.php）。
  /// 这样打开分组时看到的就是真正有新消息的那个子类型。
  String _type = '';

  /// 用户是否手动点过子类型（点过就不再被站点默认值覆盖）
  bool _typePicked = false;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await notice_api.getNoticeList(
        ApiService().dio,
        page: page,
        view: widget.view,
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
      // 先按页面自带的导航/计数校正（可能 setState 子类型），再铺列表
      _applyNav(result['nav']);
      if (!mounted) return;
      setState(() {
        _items = (result['items'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _page = result['currentPage'] as int? ?? page;
        _totalPages = result['totalPages'] as int? ?? 1;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _goToPage(int p) {
    if (p < 1 || p > _totalPages || p == _page) return;
    _load(p);
  }

  /// 用页面自带的导航与计数校正 UI（站点会按权限/配置增删，见 NoticeNavStore）：
  /// - 尚未手动选过子类型 → 采用站点本次实际打开的那个（= 有未读的那个）
  /// - 分组徽标用页面的**权威计数**覆盖（不能"整组清零"猜：打开「帖子」时
  ///   未读可能全在「点评」上，服务端什么都没置已读）
  void _applyNav(Object? nav) {
    if (nav is! Map) return;
    _nav.syncFromPage(
      Map<String, dynamic>.from(nav),
      requestedView: widget.view,
    );
    if (!_typePicked) {
      final types = _types;
      final active = _nav.activeSubtype;
      final next = active.isNotEmpty
          ? active
          : (types.isNotEmpty ? types.first.id : '');
      if (next.isNotEmpty && next != _type) {
        setState(() {
          _type = next;
          // 首次确定默认子类型 → 就地建页控制器（初始页 = 该子类型），
          // 避免"先显示第 0 页再跳过去"
          _pc ??= PageController(initialPage: _indexOfType(types, next));
        });
      }
    }
    NoticeBadgeController.instance.applyViewCounts(_nav.viewCounts);
    // 本次拉取已把该子类型的条目置为已读 → 立刻清零它的未读。
    // （子类型计数只可能来自"打开过的提醒页"，header 探测给不到，不清就永远是旧值）
    final activeType = _type.isNotEmpty ? _type : _nav.activeSubtype;
    if (activeType.isNotEmpty) {
      _nav.markSubtypeRead(widget.view, activeType);
    } else if (_types.isEmpty) {
      // 无子类型的视图（系统提醒/管理工作/应用提醒）：没有可求和的子类型，
      // 直接乐观清零本视图计数（页面渲染的是读前的值）
      NoticeBadgeController.instance.markViewRead(widget.view);
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

  @override
  Widget build(BuildContext context) {
    // 订阅站点导航：子类型未读数变化（读完清零）时刷新 chip
    context.watch<NoticeNavStore>();
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
          if (types.isNotEmpty) _buildHeader(types),
          Expanded(child: _body()),
        ],
      );
    }

    // 二级子类型之间可左右滑动；一级 Tab 只点击（见 message_page.dart）
    return Column(
      children: [
        _buildHeader(types),
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
      return EmptyView(icon: Icons.notifications_none, text: widget.emptyText);
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(1),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: _items.length,
              itemBuilder: (_, i) => _buildItem(_items[i]),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context).colorScheme.surface,
          child: PaginationBar(
            page: _page,
            totalPages: _totalPages,
            onGoToPage: _goToPage,
          ),
        ),
      ],
    );
  }

  /// 子类型 chip 行（横向可滚动，适配「我的帖子」7 个子类型）
  Widget _buildHeader(List<NoticeType> types) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final t in types) ...[
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
    final count = _nav.subtypeCount(widget.view, type);
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

  Widget _buildItem(Map<String, dynamic> item) {
    final cs = Theme.of(context).colorScheme;
    final time = item['time'] as String? ?? '';
    final timeTitle = item['timeTitle'] as String? ?? '';
    final segments = item['segments'] as List<dynamic>? ?? [];
    final fromNum = item['fromNum'] == true;
    // 站点在 authorid 非空时渲染的是对方头像（坛友互动/我的帖子）；
    // 系统提醒/管理工作是 systempm.png 系统图标 → 这里用图标兜底
    final avatarUid = item['avatarUid'] as String? ?? '';

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
            Row(
              children: [
                if (avatarUid.isNotEmpty)
                  UserAvatar(uid: avatarUid, radius: 18)
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.notifications_active,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 10),
                const Spacer(),
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
            const SizedBox(height: 8),
            if (segments.isNotEmpty)
              _buildSegments(segments)
            else
              Text(
                item['message'] as String? ?? '',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
            if (fromNum)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '已折叠同类型提醒',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
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
    final quoteStyle = TextStyle(
      fontSize: 12,
      color: cs.onSurfaceVariant,
      height: 1.4,
      fontStyle: FontStyle.italic,
    );
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
        case 'quote':
          spans.add(TextSpan(text: '\n留言：', style: quoteStyle));
          spans.add(TextSpan(text: text, style: quoteStyle));
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
}

import 'package:flutter/material.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/app/notice_badge.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/pages/message/paged_list_state.dart';
import 'package:mtbbs/widgets/layout/state_views.dart';
import 'package:provider/provider.dart';

/// 提醒 / 我的帖子两类 Tab 的公共「子类型」逻辑：
/// - 子类型集合来自 [NoticeNavStore]（站点导航）优先，配置兜底
/// - 子类型之间可左右滑动（PageView），一级 Tab 只点击（见 message_page.dart）
/// - 首次拉取时采用站点实际打开的子类型（有未读的那个），用户手点后不再覆盖
///
/// 依赖 [PagedListStateMixin] 提供 `load` / `setState` 等公共分页能力。
mixin NoticeSubtypeStateMixin<T extends StatefulWidget>
    on PagedListStateMixin<T> {
  /// 站内视图名（`do=notice&view=*`；「我的帖子」为 `mypost`）
  String get noticeView;

  /// 站点导航缺失时的配置兜底
  List<NoticeType> get configuredTypes;

  List<NoticeType> get types =>
      NoticeNavStore.instance.subtypesOf(noticeView) ?? configuredTypes;

  /// 当前请求的子类型；空串 = 尚未确定 → **不传 type**，交给站点挑
  /// 「第一个有未读的子类型」（Discuz 的 `$deftype`）。
  String noticeType = '';

  /// 用户是否手动点过子类型（点过就不再被站点默认值覆盖）
  bool _typePicked = false;

  /// 二级子类型页控制器；首次确定默认子类型后才创建，
  /// `initialPage` 直接落在该子类型上（避免先显示第 0 页再跳）
  PageController? _pageController;

  /// 上一次的子类型集合（检测站点增删 → 对齐页位置）
  String _typesKey = '';

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  /// 用页面自带的导航与计数校正 UI（站点会按权限/配置增删，见 NoticeNavStore）：
  /// - 尚未手动选过子类型 → 采用站点本次实际打开的那个（= 有未读的那个）
  /// - 分组徽标用页面的**权威计数**覆盖（不能"整组清零"猜：打开「帖子」时
  ///   未读可能全在「点评」上，服务端什么都没置已读）
  void applyNoticeNav(Object? raw) {
    if (raw is! Map) return;
    final nav = NoticeNavStore.instance;
    nav.syncFromPage(Map<String, dynamic>.from(raw), requestedView: noticeView);
    final currentTypes = types;
    if (!_typePicked) {
      // 只有真的有子类型时才采用站点的 activeSubtype；无子类型视图
      // （system/manage/app）必须忽略它（按 view 取，见 NoticeNavStore）。
      final active = currentTypes.isEmpty
          ? ''
          : nav.activeSubtypeFor(noticeView);
      final next = active.isNotEmpty
          ? active
          : (currentTypes.isNotEmpty ? currentTypes.first.id : '');
      if (next.isNotEmpty && next != noticeType) {
        setState(() {
          noticeType = next;
          // 首次确定默认子类型 → 就地建页控制器（初始页 = 该子类型）
          _pageController ??= PageController(
            initialPage: _indexOfType(currentTypes, next),
          );
        });
      } else if (currentTypes.isEmpty && noticeType.isNotEmpty) {
        // 站点导航表明本视图没有子类型 → 清掉可能继承来的值
        setState(() => noticeType = '');
      }
    }
    NoticeBadgeController.instance.applyViewCounts(nav.viewCounts);
    // 本次拉取已把该子类型的条目置为已读 → 立刻清零它的未读。
    // （子类型计数只可能来自"打开过的提醒页"，header 探测给不到，不清就永远是旧值）
    final activeType = currentTypes.isEmpty
        ? ''
        : (noticeType.isNotEmpty
              ? noticeType
              : nav.activeSubtypeFor(noticeView));
    if (activeType.isNotEmpty) {
      nav.markSubtypeRead(noticeView, activeType);
    } else if (currentTypes.isEmpty) {
      // 无子类型的视图（系统提醒/管理工作/应用提醒）：没有可求和的子类型，
      // 直接乐观清零本视图计数（页面渲染的是读前的值）
      NoticeBadgeController.instance.markViewRead(noticeView);
    }
  }

  void switchType(String type) {
    if (type == noticeType) return;
    // 用户手动选过之后，不再被站点默认子类型覆盖
    _typePicked = true;
    setState(() {
      noticeType = type;
      // 兜底：首次加载尚未确定默认子类型时（_pageController 还没建）用户就点了
      // chip → 这里补建，保证之后二级仍可左右滑动
      if (_pageController == null) {
        final currentTypes = types;
        if (currentTypes.isNotEmpty) {
          _pageController = PageController(
            initialPage: _indexOfType(currentTypes, type),
          );
        }
      }
    });
    onSubtypeChanged(type);
    load(1);
  }

  /// 点 chip：优先用页控制器**滑动**过去（onPageChanged 里再真正切换+加载）；
  /// 无控制器（尚未确定默认子类型）时退化为直接切换。
  void selectType(String type) {
    if (type == noticeType) return;
    _typePicked = true;
    final pc = _pageController;
    final i = _indexOfType(types, type);
    if (pc != null && pc.hasClients && i >= 0) {
      pc.animateToPage(
        i,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      switchType(type);
    }
  }

  int _indexOfType(List<NoticeType> types, String id) {
    final i = types.indexWhere((t) => t.id == id);
    return i < 0 ? 0 : i;
  }

  /// 当前展示的子类型在 [types] 中的下标（`noticeType` 未定时取 0）
  int _currentIndex(List<NoticeType> types) => _indexOfType(types, noticeType);

  /// Tab 整体骨架：子类型 chip 行 + 二级子类型 PageView（或单块内容）。
  ///
  /// [body] 为当前子类型的内容块（加载/错误/空/列表）。
  /// [alwaysShowHeader] 为 true 时即使无子类型也保留 chip 行（「我的帖子」常驻）。
  Widget buildNoticeTab({
    required Widget Function() body,
    bool alwaysShowHeader = false,
  }) {
    // 订阅站点导航：子类型未读数变化（读完清零）时刷新 chip
    context.watch<NoticeNavStore>();
    final currentTypes = types;

    // 站点增删子类型 → 把页位置对齐到当前子类型
    final key = currentTypes.map((t) => t.id).join(',');
    if (key != _typesKey) {
      _typesKey = key;
      final pc0 = _pageController;
      if (pc0 != null && currentTypes.isNotEmpty) {
        final target = _currentIndex(currentTypes);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && pc0.hasClients && pc0.page?.round() != target) {
            pc0.jumpToPage(target);
          }
        });
      }
    }

    final pc = _pageController;
    // 无子类型，或默认子类型尚未确定 → 单块内容（含加载 / 错误 / 空态）
    if (currentTypes.isEmpty || pc == null) {
      return Column(
        children: [
          if (alwaysShowHeader || currentTypes.isNotEmpty)
            _buildHeader(currentTypes),
          Expanded(child: body()),
        ],
      );
    }

    // 二级子类型之间可左右滑动；一级 Tab 只点击（见 message_page.dart）
    return Column(
      children: [
        _buildHeader(currentTypes),
        Expanded(
          child: PageView.builder(
            controller: pc,
            itemCount: currentTypes.length,
            onPageChanged: (i) => switchType(currentTypes[i].id),
            itemBuilder: (_, i) =>
                i == _currentIndex(currentTypes) ? body() : const LoadingView(),
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
    final active = noticeType == type;
    // 子类型未读：来自页面子栏的权威计数（服务端置已读之后的值）
    final count = NoticeNavStore.instance.subtypeCount(noticeView, type);
    return GestureDetector(
      onTap: () => selectType(type),
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
}

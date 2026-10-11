import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/tab_retap.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/app/notice_badge.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/pages/message/message_pm_tab.dart';
import 'package:mtbbs/pages/message/message_mypost_tab.dart';
import 'package:mtbbs/pages/message/message_notice_tab.dart';

/// 消息页面 — 私人消息 + `do=notice` 的各提醒分组
///
/// 路径: /message
/// 分组与顺序来自 [noticeGroups]（唯一数据源）：新增一类提醒只需在配置里加一行，
/// 这里自动多出一个 Tab。
/// 每个 Tab 独立管理加载状态和分页，各自封装在独立的 Widget 中。
/// AppBar 由 AppShell 提供，此处只返回内容体。
class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage>
    // 消息页会随"站点实际视图"增删**重建 TabController**（见 [_syncTabController]），
    // 需要支持多个 ticker —— SingleTickerProviderStateMixin 只允许一个，
    // 第二次创建会直接抛 "multiple tickers were created"。
    with TickerProviderStateMixin {
  late TabController _tabCtl;
  final _nav = NoticeNavStore.instance;

  /// 主动探测进行中（按钮转圈）
  bool _checking = false;

  /// 分组页重建计数：手动刷新、或"探测发现新消息→子类型数据过期"时 +1，
  /// 通过 widget key 整体重建当前分组页（重新拉取）。
  int _reloadTick = 0;

  /// 已消费的 [NoticeNavStore.dropRevision]
  int _lastDropRev = 0;

  /// 重复点击「消息」Tab：整体没有统一主列表（各分组页各有自己的），故直接刷新当前分组
  late final Future<void> Function() _reTap = () async => _refreshCurrentTab();

  @override
  void initState() {
    super.initState();
    TabReTap.instance.register('/message', _reTap);
    _nav.addListener(_onNavChanged);
    _tabCtl = TabController(length: _tabs.length, vsync: this);
    _tabCtl.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    TabReTap.instance.unregister('/message', _reTap);
    _tabCtl.removeListener(_onTabChanged);
    _nav.removeListener(_onNavChanged);
    _tabCtl.dispose();
    super.dispose();
  }

  /// 记录一次 Tab 使用（「常用项自动前排」用）。跳跃过程中不记，稳定后记一次。
  void _onTabChanged() {
    if (_tabCtl.indexIsChanging) return;
    final tabs = _tabs;
    final i = _tabCtl.index;
    if (i < 0 || i >= tabs.length) return;
    unawaited(
      context.read<SettingsProvider>().recordTabUsage(
        kTabUsageNotice,
        tabs[i].id,
      ),
    );
  }

  /// 主动探测未读：绕过 [NoticeBadgeController.minInterval] 节流立刻拉一次。
  ///
  /// 除测试方便外，它也是"立即刷新"的入口——平时的检查只在冷启动/回前台/
  /// 返回主壳/切 Tab 时触发（最多 5 分钟一次）。
  Future<void> _probeNotices() async {
    if (_checking) return;
    if (!context.read<AuthProvider>().isLoggedIn) {
      showToast('请先登录');
      return;
    }
    setState(() => _checking = true);
    await NoticeBadgeController.instance.check(force: true);
    if (!mounted) return;
    setState(() => _checking = false);
    final c = NoticeBadgeController.instance;
    final total = c.byGroup.values.fold<int>(0, (a, b) => a + b);
    if (total == 0 && !c.hasNewPm) {
      showToast('暂无新提醒');
    } else {
      showToast('未读提醒 $total 条${c.hasNewPm ? '，有新私信' : ''}');
    }
  }

  /// 站点实际有的提醒视图（未同步前回退配置）
  List<NoticeType> get _availableViews {
    if (_nav.synced) return _nav.views;
    return [for (final g in noticeGroups) NoticeType(g.id, g.label)];
  }

  /// Tab 顺序的"冻结键"（用户设置 / 站点视图变化时才重排）
  String _tabOrderKey = '';
  List<NoticeType> _orderedTabs = const [];

  /// 消息页 Tab 列表：用户设置（顺序/显隐）+ 站点实际有的视图 + 常用项自动前排。
  ///
  /// - `pm` = 私信，恒可用
  /// - 设置里没有、站点新出现的视图 → 追加在后面（否则会"看不见"）
  /// - 「常用项自动前排」只重排**第 1 项之后**的（第 1 项是默认进入项，固定）；
  ///   且顺序**在挂载/设置变化时冻结**：否则点一下就把自己顶上来，
  ///   Tab 栏会在手指底下跳；累计的使用次数在下次进入时生效
  List<NoticeType> get _tabs {
    final s = context.read<SettingsProvider>();
    final available = _availableViews;
    final byId = <String, NoticeType>{
      'pm': const NoticeType('pm', '我的消息'),
      for (final t in available) t.id: t,
    };
    final setting = [
      for (final id in s.noticeTabOrder)
        if (byId.containsKey(id)) id,
    ];
    final base = [
      ...setting,
      for (final t in available)
        if (!setting.contains(t.id)) t.id,
    ];
    final key = '${base.join(',')}|${s.autoFrequentTabs}';
    if (key != _tabOrderKey) {
      _tabOrderKey = key;
      _orderedTabs = [
        for (final id in s.orderedTabIds(kTabUsageNotice, base)) byId[id]!,
      ];
    }
    return _orderedTabs;
  }

  /// 手动刷新当前分组：换 key 重建（重新拉取，回到站点默认子类型），
  /// 并顺带对一次未读 —— **自动探测与手动刷新并存**。
  void _refreshCurrentTab() {
    setState(() => _reloadTick++);
    unawaited(NoticeBadgeController.instance.check(force: true));
  }

  /// 站点导航变化：视图增删 / 子类型计数变化都可能发生 → 触发一次重建。
  ///
  /// **不在通知回调里创建 TabController**：各分组页会把各自的页面导航同步进
  /// [NoticeNavStore]，集合可能在不同页之间 5/6 交替；若在这里按"当前长度"
  /// 建控制器，会与随后 build 实际用的 Tab 列表脱节。长度对齐统一交给
  /// [build] 里的 [_syncTabController]。
  void _onNavChanged() {
    if (!mounted) return;
    if (_nav.dropRevision != _lastDropRev) {
      _lastDropRev = _nav.dropRevision;
      _reloadTick++;
    }
    setState(() {});
  }

  /// 保证 TabController 的长度 == 当前 Tab 列表长度（在 [build] 里调用）。
  ///
  /// 视图增删（不同分组页同步来的导航集合可能 5/6 交替）时若不对齐长度，
  /// TabBar / TabBarView 会直接抛 "Controller's length property (N) does not
  /// match the number of tabs (M)"。旧控制器延迟到帧末再 dispose，避免仍被本帧使用。
  TabController _syncTabController(int length) {
    if (_tabCtl.length == length) return _tabCtl;
    final old = _tabCtl;
    final idx = old.index.clamp(0, length - 1);
    old.removeListener(_onTabChanged);
    _tabCtl = TabController(length: length, vsync: this, initialIndex: idx);
    _tabCtl.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    return _tabCtl;
  }

  /// 视图 → 页面。我的帖子有「预览 / 回复」等额外能力，单独实现；
  /// 其余视图（坛友互动 / 系统提醒 / 管理工作 / 应用提醒）共用同一份列表实现。
  ///
  /// key 里带 [_reloadTick]：手动刷新或子类型数据过期时**整体重建**该页（重新拉取）。
  Widget _tabPage(NoticeType t) {
    if (t.id == 'pm') return const PmTab();
    final key = ValueKey('${t.id}#$_reloadTick');
    if (t.id == 'mypost') return MypostTab(key: key);
    return NoticeTab(key: key, view: t.id, emptyText: '暂无${t.label}');
  }

  /// Tab 标签；有未读时叠加徽标（数字封顶 99+）
  Widget _tabLabel(String label, int count) {
    if (count <= 0) return Tab(text: label);
    return Tab(
      child: Badge(
        label: Text(count > 99 ? '99+' : '$count'),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 各分组未读（来自 NoticeBadgeController 的非破坏性探测）
    final badge = context.watch<NoticeBadgeController>();
    // 分组徽标由子类型求和推导（数据驱动）→ 子类型计数变化也要重建
    context.watch<NoticeNavStore>();
    final enabled = context.watch<SettingsProvider>().noticeCheckEnabled;
    final tabs = _tabs;
    // 长度可能与上一帧不同（站点视图增删）→ 先对齐控制器再交给 TabBar/TabBarView
    final tabCtl = _syncTabController(tabs.length);
    return Column(
      children: [
        Container(
          color: cs.surface,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: tabCtl,
                  // 顶栏有 5 个分组，窄屏放不下 → 横向可滚动
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: cs.onSurfaceVariant,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  indicatorColor: cs.onSurfaceVariant,
                  tabs: [
                    for (final t in tabs)
                      t.id == 'pm'
                          // 私信只知"有/无"，故用红点（无数字）
                          ? Tab(
                              child: Badge(
                                isLabelVisible: enabled && badge.hasNewPm,
                                child: Text(t.label),
                              ),
                            )
                          : _tabLabel(
                              t.label,
                              enabled ? badge.countOf(t.id) : 0,
                            ),
                  ],
                ),
              ),
              // 主动探测：绕过 5 分钟节流立刻检查一次（方便测试，也是"立即刷新"入口）
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                        ),
                        tooltip: '立即检查新提醒',
                        visualDensity: VisualDensity.compact,
                        onPressed: _probeNotices,
                      ),
              ),
              // 手动刷新当前分组（重新拉取页面内容；与"自动探测未读"并存）
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新当前分组',
                visualDensity: VisualDensity.compact,
                onPressed: _refreshCurrentTab,
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabCtl,
            // 一级 Tab（我的消息 / 我的帖子…）**只点击切换**，不响应左右滑动；
            // 滑动留给分组内的二级子类型（帖子 / 评分 / 点评…，见 message_mypost_tab）。
            physics: const NeverScrollableScrollPhysics(),
            children: [for (final t in tabs) _tabPage(t)],
          ),
        ),
      ],
    );
  }
}

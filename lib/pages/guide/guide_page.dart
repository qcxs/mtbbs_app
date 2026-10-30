import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/event_bus.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/tab_retap.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:provider/provider.dart';
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/auth/widgets/login_sheet.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';
import 'package:mtbbs/controllers/thread_list_controller.dart';
import 'package:mtbbs/widgets/thread/thread_grid.dart';

/// 导读首页
///
/// 由 _AppShell 提供 Scaffold 外壳，本组件只返回 Column(tab条 + PageView)。
class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  final _pageController = PageController();

  /// 当前选中 Tab；初始为空串，首次构建时回退到第一个可见 Tab，
  /// 避免顺序变化后仍停留在旧 Tab 导致 PageView 错位不加载。
  String _focusView = '';
  static final Map<String, ThreadListController> _ctrlMap = {};

  /// [_ctrlMap] 里的控制器属于哪个站点。
  ///
  /// 静态表比页面实例活得久，切站后必须按站点整体作废（见 [_ensureCtrls]），
  /// 否则再进导读页会直接复用另一个站点的列表 / 页码。
  static String _ctrlHost = '';

  StreamSubscription<AppEvent>? _siteSub;

  /// 重复点击「导读」Tab：对**当前子 Tab 的列表**回顶 / 刷新（规则见 TabReTap）
  late final Future<void> Function() _reTap = () async {
    final c = _ctrlMap[_focusView];
    if (c == null) return;
    await ThreadGrid.scrollControllers[c].toTopOrRefresh(c.refresh);
  };

  @override
  void initState() {
    super.initState();
    TabReTap.instance.register('/guide', _reTap);
    _siteSub = EventBus.stream
        .where((e) => e is SiteChangedEvent)
        .listen(_onSiteChanged);
  }

  @override
  void dispose() {
    TabReTap.instance.unregister('/guide', _reTap);
    _siteSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  /// 切换站点：导读列表按站点抓取，旧列表（含页码 / 滚动位置）属于另一个站点，
  /// 不能继续展示。丢掉控制器并更换 PageView 的 key，让每个 ThreadGrid 重新
  /// `loadInitial`（新列表从第 1 页开始、滚动回到顶部）。
  void _onSiteChanged(AppEvent _) {
    if (!mounted) return;
    // 空串 → build 时回退到第一个可见 Tab（与 Tab 顺序变化时的处理一致）；
    // 控制器与 PageView 的作废在 [_ensureCtrls] / PageView key 里按站点完成。
    setState(() => _focusView = '');
    // 新站点的列表从第一个 Tab 开始，别停在旧站点翻到的页上
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) _pageController.jumpToPage(0);
    });
  }

  /// Tab 顺序的"冻结键"（用户设置变化时才重排）
  String _orderKey = '';
  List<String> _orderedViews = const [];

  /// 可见 Tab（按用户顺序）；开启「常用项自动前排」时把**第 1 项之后的**按使用次数重排
  /// （第 1 项 = 默认进入项，固定）。
  ///
  /// 重排只在挂载/设置变化时发生 —— 否则点一下 Tab 就把自己顶上来，
  /// Tab 栏会在手指底下跳；累计的使用次数在下次进入时生效。
  List<String> _views(bool loggedIn) {
    final s = context.read<SettingsProvider>();
    final base = List<String>.from(s.tabOrder);
    if (loggedIn && !base.contains('my')) base.add('my');
    final key = '${base.join(',')}|${s.autoFrequentTabs}';
    if (key != _orderKey) {
      _orderKey = key;
      _orderedViews = s.orderedTabIds(kTabUsageGuide, base);
    }
    return _orderedViews;
  }

  void _ensureCtrls(Iterable<String> views) {
    final host = SiteStore.instance.host;
    if (host != _ctrlHost) {
      _ctrlMap.clear();
      _ctrlHost = host;
    }
    for (final v in views) {
      _ctrlMap.putIfAbsent(
        v,
        () => ThreadListController(
          fetchFn: ({required int page}) =>
              guide_api.getThreadList(ApiService().dio, view: v, page: page),
        ),
      );
    }
  }

  void _showOrderDialog() {
    final settings = context.read<SettingsProvider>();
    final before = settings.tabOrder;
    showManagedListDialog(
      context: context,
      title: 'Tab 排序',
      items: settings.guideTabs,
      allowAdd: false,
      allowDelete: false,
      allowEdit: false,
      allowReorder: true,
      allowToggleVisibility: true,
      onReorder: (from, to) => settings.moveTab(from, to),
      onToggleVisibility: (id) => settings.toggleTab(id),
      emptyHint: '暂无 Tab',
    ).then((_) {
      if (!context.mounted) return;
      final views = _views(context.read<AuthProvider>().isLoggedIn);
      // 顺序/显隐有变化，或当前 Tab 已不可见 → 回到第一个 Tab
      if (!listEquals(before, settings.tabOrder) ||
          !views.contains(_focusView)) {
        final target = views.isNotEmpty ? views.first : '';
        setState(() => _focusView = target);
        final idx = views.indexOf(target);
        // 同步 PageView 位置，避免 _focusView 与显示页错位导致内容不加载
        if (idx >= 0 && _pageController.hasClients) {
          _pageController.jumpToPage(idx);
        }
      }
    });
  }

  void _selectView(String view) {
    final views = _views(context.read<AuthProvider>().isLoggedIn);
    final i = views.indexOf(view);
    if (i < 0 || view == _focusView) return;
    setState(() => _focusView = view);
    _pageController.jumpToPage(i);
    // 记录使用（「常用项自动前排」用）
    unawaited(
      context.read<SettingsProvider>().recordTabUsage(kTabUsageGuide, view),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final views = _views(auth.isLoggedIn);
    _ensureCtrls(views);
    if (!views.contains(_focusView))
      _focusView = views.isNotEmpty ? views.first : '';
    final focusIdx = views.indexOf(_focusView);
    final hasTabs = views.isNotEmpty;

    final shortcutsMap = <ShortcutActivator, Intent>{};
    final actionsList = <Type, Action<Intent>>{};

    final _refreshKey = ShortcutHelper.parse(settings.shortcut('refresh'));
    if (_refreshKey != null) {
      shortcutsMap[_refreshKey] = RefreshIntent();
      actionsList[RefreshIntent] = CallbackAction<RefreshIntent>(
        onInvoke: (_) {
          _ctrlMap[_focusView]?.refresh();
          return null;
        },
      );
    }
    if (views.isNotEmpty) {
      final nextKey = ShortcutHelper.parse(settings.shortcut('switchTabNext'));
      if (nextKey != null) {
        shortcutsMap[nextKey] = SwitchTabNextIntent();
        actionsList[SwitchTabNextIntent] = CallbackAction<SwitchTabNextIntent>(
          onInvoke: (_) {
            final i = views.indexOf(_focusView);
            _selectView(views[(i + 1) % views.length]);
            return null;
          },
        );
      }
    }
    if (views.length > 1) {
      final prevKey = ShortcutHelper.parse(settings.shortcut('switchTabPrev'));
      if (prevKey != null) {
        shortcutsMap[prevKey] = SwitchTabPrevIntent();
        actionsList[SwitchTabPrevIntent] = CallbackAction<SwitchTabPrevIntent>(
          onInvoke: (_) {
            final i = views.indexOf(_focusView);
            _selectView(views[(i - 1 + views.length) % views.length]);
            return null;
          },
        );
      }
    }

    return Actions(
      actions: actionsList,
      child: Shortcuts(
        shortcuts: shortcutsMap,
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              // === Tab 条 ===
              if (hasTabs)
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: views
                                .asMap()
                                .entries
                                .map(
                                  (e) => _chip(
                                    SettingsProvider.tabLabels[e.value] ??
                                        e.value,
                                    e.key == focusIdx,
                                    () => _selectView(e.value),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.tune,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        tooltip: 'Tab 排序',
                        onPressed: _showOrderDialog,
                      ),
                    ],
                  ),
                ),
              // === 内容 ===
              Expanded(
                child: !hasTabs
                    ? const Center(child: Text('暂无可用标签'))
                    : PageView(
                        // 站点也在 key 里：切站后整棵树重建，ThreadGrid 才会重新
                        // loadInitial（否则旧 State 的 _everLoaded=true 会跳过加载）
                        key: ValueKey('$_ctrlHost|${views.join(',')}'),
                        controller: _pageController,
                        onPageChanged: (i) {
                          if (i >= 0 && i < views.length) {
                            setState(() => _focusView = views[i]);
                            // 记录使用（「常用项自动前排」用）
                            unawaited(
                              context.read<SettingsProvider>().recordTabUsage(
                                kTabUsageGuide,
                                views[i],
                              ),
                            );
                          }
                        },
                        children: views.map((v) {
                          final ctrl = _ctrlMap[v];
                          if (ctrl == null) return const SizedBox.shrink();
                          if (v == 'my' && !auth.isLoggedIn)
                            return _buildLoginPrompt();
                          return ThreadGrid(
                            controller: ctrl,
                            visible: v == _focusView,
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? cs.onSurfaceVariant.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? cs.onSurfaceVariant : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 12),
            Text(
              '登录后可查看自己的帖子',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => showLoginSheet(context),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('立即登录'),
            ),
          ],
        ),
      ),
    );
  }
}

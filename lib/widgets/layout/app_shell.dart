import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/nav_config.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/notice_badge.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';
import 'package:mtbbs/core/app/tab_retap.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/pages/home/home_page.dart';
import 'package:mtbbs/pages/guide/guide_page.dart';
import 'package:mtbbs/pages/message/message_page.dart';
import 'package:mtbbs/pages/user/my_profile_page.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/thread_cache_database.dart';
import 'package:mtbbs/services/thread_cache_service.dart';

/// 响应式外壳（底部导航栏 + 侧边栏）
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  /// 页面缓存：首次切换到某 Tab 时才创建，创建后永久缓存。
  final Map<int, Widget> _tabPageCache = {};

  /// 上一次的「站点 + 账号」；变化说明缓存页面属于旧身份
  String _identity = '';

  /// 上次点击"当前 Tab"的时间（识别 500ms 内连点 → 直接刷新）
  int _lastTabTapAt = 0;

  /// 帖子缓存损坏提示：每个 App 会话只弹一次
  bool _threadCacheToastShown = false;

  @override
  void initState() {
    super.initState();
    ThreadCacheService.instance.health.addListener(_onThreadCacheHealth);
  }

  @override
  void dispose() {
    ThreadCacheService.instance.health.removeListener(_onThreadCacheHealth);
    super.dispose();
  }

  void _onThreadCacheHealth() {
    if (_threadCacheToastShown) return;
    if (ThreadCacheService.instance.health.value !=
        ThreadCacheHealth.corrupted) {
      return;
    }
    _threadCacheToastShown = true;
    showToast(
      '帖子缓存文件损坏，缓存功能已禁用；请在缓存管理中导出备份或重建。',
      duration: const Duration(seconds: 4),
    );
  }

  /// 切换账号/站点时，缓存里的 Tab 页面全是**旧身份**的数据，而它们"永久缓存"着，
  /// 不清就会"换了账号还显示上一个账号的消息"。整体丢弃，下次进入重新创建并拉取。
  void _checkIdentity() {
    final auth = context.read<AuthProvider>();
    final id = '${SiteStore.instance.host}|${auth.uid}|${auth.username}';
    if (_identity.isEmpty || id == _identity) {
      _identity = id;
      return;
    }
    _identity = id;
    _tabPageCache.clear();
    AppLogger.i('SHELL', '身份变化 → 丢弃 Tab 页面缓存（$id）');
  }

  Widget _createPage(int index) {
    switch (index) {
      case 0:
        return const HomePage();
      case 1:
        return const MessagePage();
      case 2:
        return const GuidePage();
      case 3:
        return const ProfilePage();
      default:
        return const SizedBox.shrink();
    }
  }

  /// 按当前活跃索引生成 Tab 页面列表。
  /// 只创建当前 Tab 的页面，其余用占位符；首次创建后缓存，IndexedStack 保持存活。
  List<Widget> _buildTabPages() {
    _tabPageCache.putIfAbsent(_currentIndex, () => _createPage(_currentIndex));
    return List.generate(
      navItems.length,
      (i) => _tabPageCache[i] ?? const SizedBox.shrink(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // build 里 watch 了 AuthProvider → 切账号/站点会走到这里
    _checkIdentity();
    _syncIndex();
    _checkOnRouteChange();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncIndex();
    _checkOnRouteChange();
  }

  /// 上一次的路由位置（用于识别"从子页返回主壳"）
  String _lastLocation = '';

  /// 从子页（帖子 / 设置 / 浏览器…）返回主壳时检查一次未读。
  ///
  /// 等价于 RouteAware 的 `didPopNext`，但用**路由位置差**判断：ShellRoute 下
  /// 子路由是替换 shell 的 child、不会 push 到 shell 之上，RouteAware 收不到回调。
  /// 与其他触发点一样受 [NoticeBadgeController] 的 5 分钟节流。
  void _checkOnRouteChange() {
    final loc = GoRouterState.of(context).uri.toString();
    final wasShell = navItems.any((e) => e.path == _lastLocation);
    final isShell = navItems.any((e) => e.path == loc);
    _lastLocation = loc;
    if (!wasShell && isShell) _checkUnread();
  }

  /// 同步当前路由到 tab 索引。
  void _syncIndex() {
    final uri = GoRouterState.of(context).uri.toString();
    final newIndex = navItems.indexWhere((e) => e.path == uri);
    if (newIndex == -1) return;
    _currentIndex = newIndex;
  }

  void _onTap(int i) {
    if (_currentIndex == i) {
      // 重复点击当前 Tab（规则照 PiliPlus 的 setIndex）：
      // 500ms 内**连点** → 直接刷新；否则「不在顶部回顶、已在顶部刷新」
      final now = DateTime.now().millisecondsSinceEpoch;
      final path = navItems[i].path;
      if (now - _lastTabTapAt < 500) {
        unawaited(TabReTap.instance.refresh(path));
      } else {
        unawaited(TabReTap.instance.toTopOrRefresh(path));
      }
      _lastTabTapAt = now;
      return;
    }
    _lastTabTapAt = 0;
    // 离开「消息」= 视为"读完了" → 立刻与服务器对一次账（**强制**，不受 5 分钟节流；
    // 因为此时节流会被"页面计数校正"刚重置过，不强制就永远不触发）
    if (navItems[_currentIndex].path == '/message') _checkUnread(force: true);
    // 切到「消息」时顺手检查未读（受 NoticeBadgeController 的 5 分钟节流）
    if (navItems[i].path == '/message') _checkUnread();
    context.go(navItems[i].path);
  }

  void _checkUnread({bool force = false}) {
    final s = context.read<SettingsProvider>();
    if (!s.noticeCheckEnabled || !context.read<AuthProvider>().isLoggedIn) {
      NoticeBadgeController.instance.clear();
      return;
    }
    NoticeBadgeController.instance.check(force: force);
  }

  /// 底栏 / 侧栏图标；「消息」按设置叠加未读徽标（隐藏 / 红点 / 数字）
  Widget _navIcon(
    NavItem item,
    bool selected,
    SettingsProvider s,
    NoticeBadgeController badge, {
    double? size,
    Color? color,
  }) {
    final icon = Icon(
      selected ? item.iconFilled : item.icon,
      size: size,
      color: color,
    );
    if (item.path != '/message') return icon;
    final mode = s.noticeBadgeMode;
    if (mode == NoticeBadgeMode.hidden || !s.noticeCheckEnabled) return icon;
    final count = badge.countFor(s.noticeBadgeGroups);
    final visible = count > 0 || badge.hasNewPm;
    return Badge(
      isLabelVisible: visible,
      // 数字模式：有数字显示数字，否则退化成红点（如只有未读私信）
      label: (mode == NoticeBadgeMode.number && count > 0)
          ? Text(count > 99 ? '99+' : '$count')
          : null,
      child: icon,
    );
  }

  /// 当前路由是否为主 Tab 页面
  bool get _isTabRoute {
    final uri = GoRouterState.of(context).uri.toString();
    return navItems.any((e) => e.path == uri);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // 分组徽标按"子类型求和"推导（数据驱动）→ 子类型计数变化也要重建底栏徽标
    context.watch<NoticeNavStore>();
    final item = navItems[_currentIndex];

    // 统一按宽度比判断（与页面级 isPortrait 语义一致），
    // 避免"竖屏平板底部导航 + 宽屏双栏内容"的矛盾组合
    final useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    return useBottomNav
        ? _buildBottomNav(context, auth, item)
        : _buildSideRail(context, auth, item);
  }

  Widget _buildBottomNav(
    BuildContext context,
    AuthProvider auth,
    NavItem item,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.edit_outlined,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            tooltip: '发帖',
            onPressed: () {
              final forums = SiteStore.instance.forums;
              if (forums.isEmpty) {
                showToast('无可发帖的版块');
                return;
              }
              if (forums.length == 1) {
                context.push('/editor?type=post&fid=${forums.keys.first}');
                return;
              }
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('选择版块'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: SiteStore.instance.defaultForumOrder
                          .where((fid) => forums.containsKey(fid))
                          .map(
                            (fid) => ListTile(
                              leading: const Icon(Icons.forum),
                              title: Text(forums[fid] ?? fid),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                context.push('/editor?type=post&fid=$fid');
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.search, size: 22, color: cs.onSurfaceVariant),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: UserAvatar(
              uid: auth.uid,
              nickname: auth.username,
              radius: 16,
              tapAction: AvatarTapAction.custom,
              onTap: () => showDialog(
                context: context,
                builder: (_) => const UserManagementDialog(),
              ),
            ),
          ),
        ],
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      body: _isTabRoute
          ? IndexedStack(index: _currentIndex, children: _buildTabPages())
          : widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTap,
        destinations: navItems
            .map(
              (e) => NavigationDestination(
                icon: _navIcon(
                  e,
                  false,
                  context.watch<SettingsProvider>(),
                  context.watch<NoticeBadgeController>(),
                ),
                selectedIcon: _navIcon(
                  e,
                  true,
                  context.watch<SettingsProvider>(),
                  context.watch<NoticeBadgeController>(),
                ),
                label: e.label,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildSideRail(BuildContext context, AuthProvider auth, NavItem item) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部固定区域（头像/发帖/搜索）
                  _buildSideRailLeading(context, auth),
                  const Divider(height: 1),
                  // 导航项（可滚动）
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < navItems.length; i++)
                            _buildSideRailDestination(i, navItems[i]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, color: cs.outlineVariant),
          Expanded(
            child: SafeArea(
              left: false,
              child: _isTabRoute
                  ? IndexedStack(
                      index: _currentIndex,
                      children: _buildTabPages(),
                    )
                  : widget.child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideRailLeading(BuildContext context, AuthProvider auth) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        UserAvatar(
          uid: auth.uid,
          nickname: auth.username,
          radius: 18,
          tapAction: AvatarTapAction.custom,
          onTap: () => showDialog(
            context: context,
            builder: (_) => const UserManagementDialog(),
          ),
        ),
        const SizedBox(height: 4),
        IconButton(
          icon: Icon(Icons.edit_outlined, size: 20, color: cs.onSurfaceVariant),
          tooltip: '发帖',
          onPressed: () {
            final forums = SiteStore.instance.forums;
            if (forums.isEmpty) {
              showToast('无可发帖的版块');
              return;
            }
            if (forums.length == 1) {
              context.push('/editor?type=post&fid=${forums.keys.first}');
              return;
            }
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('选择版块'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(
                    shrinkWrap: true,
                    children: SiteStore.instance.defaultForumOrder
                        .where((fid) => forums.containsKey(fid))
                        .map(
                          (fid) => ListTile(
                            leading: const Icon(Icons.forum),
                            title: Text(forums[fid] ?? fid),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              context.push('/editor?type=post&fid=$fid');
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            );
          },
        ),
        IconButton(
          icon: Icon(Icons.search, color: cs.onSurfaceVariant),
          tooltip: '搜索',
          onPressed: () => context.push('/search'),
        ),
      ],
    );
  }

  Widget _buildSideRailDestination(int index, NavItem item) {
    final cs = Theme.of(context).colorScheme;
    final selected = index == _currentIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: () => _onTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _navIcon(
                item,
                selected,
                context.watch<SettingsProvider>(),
                context.watch<NoticeBadgeController>(),
                size: 24,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected ? cs.onSurfaceVariant : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

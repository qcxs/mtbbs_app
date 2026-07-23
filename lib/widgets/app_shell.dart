import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../config/nav_config.dart';
import '../core/site_store.dart';
import '../auth/providers/auth_provider.dart';
import '../widgets/user_avatar.dart';
import '../pages/settings/user_management_dialog.dart';
import '../pages/home/home_page.dart';
import '../pages/guide/guide_page.dart';
import '../pages/message/message_page.dart';
import '../pages/user/my_profile_page.dart';

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
    _syncIndex();
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncIndex();
  }

  /// 同步当前路由到 tab 索引。
  void _syncIndex() {
    final uri = GoRouterState.of(context).uri.toString();
    final newIndex = navItems.indexWhere((e) => e.path == uri);
    if (newIndex == -1) return;
    _currentIndex = newIndex;
  }

  void _onTap(int i) {
    if (_currentIndex == i) return;
    context.go(navItems[i].path);
  }

  /// 当前路由是否为主 Tab 页面
  bool get _isTabRoute {
    final uri = GoRouterState.of(context).uri.toString();
    return navItems.any((e) => e.path == uri);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final item = navItems[_currentIndex];

    return OrientationBuilder(
      builder: (context, orientation) {
        final useBottomNav = orientation == Orientation.portrait;
        return useBottomNav
            ? _buildBottomNav(context, auth, item)
            : _buildSideRail(context, auth, item);
      },
    );
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('无可发帖的版块')));
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
                icon: Icon(e.icon),
                selectedIcon: Icon(e.iconFilled),
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
            child: _isTabRoute
                ? IndexedStack(index: _currentIndex, children: _buildTabPages())
                : widget.child,
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('无可发帖的版块')));
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
              Icon(
                selected ? item.iconFilled : item.icon,
                size: 24,
                color: selected ? cs.onSurfaceVariant : cs.onSurfaceVariant,
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

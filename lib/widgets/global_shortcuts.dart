import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../config/nav_config.dart';
import '../providers/settings_provider.dart';
import '../core/shortcut_helper.dart';

/// 包裹所有路由，提供全局快捷键（Esc 返回）。
/// 独立于 AppShell，确保设置页、帖子详情、编辑器等所有页面都能响应。
class GlobalShortcutsWrapper extends StatefulWidget {
  final Widget child;
  const GlobalShortcutsWrapper({super.key, required this.child});

  @override
  State<GlobalShortcutsWrapper> createState() => _GlobalShortcutsWrapperState();
}

class _GlobalShortcutsWrapperState extends State<GlobalShortcutsWrapper>
    with WidgetsBindingObserver {
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 仅拦截 Tab 页面返回（非 Tab 页面放行给 GoRouter 默认处理），
  /// 避免 GoRouter shell navigatorKey.currentState 为 null 时崩溃。
  @override
  Future<bool> didPopRoute() async {
    final uri = GoRouterState.of(context).uri.toString();
    final tabIdx = navItems.indexWhere((e) => e.path == uri);
    if (tabIdx < 0) return false; // 非 Tab 页面，放行给 GoRouter
    _handleAndroidBack(context);
    return true;
  }

  /// Android 返回键 — 栈后退 + tab 切换 + 双击退出
  void _handleAndroidBack(BuildContext context) {
    if (_backStack(context)) return;
    // 无导航可返回 → 判断 Tab 页面行为
    final uri = GoRouterState.of(context).uri.toString();
    final tabIdx = navItems.indexWhere((e) => e.path == uri);
    if (tabIdx < 0) return; // 非 tab 页面，忽略
    if (tabIdx != 0) {
      // 非默认 tab → 切回默认
      context.go(navItems[0].path);
      return;
    }
    // 默认 tab → 双击退出
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!).inMilliseconds < 2000) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('再按一次退出'), duration: Duration(seconds: 2)),
    );
  }

  /// Esc 键 — 只做栈式后退，不做页面级行为
  Object? _handleEscBack(BuildContext context) {
    _backStack(context);
    return null;
  }

  /// 通用栈后退：Navigator → rootNavigator → GoRouter
  bool _backStack(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: false);
    if (navigator.canPop()) {
      navigator.pop();
      return true;
    }
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
      return true;
    }
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    final shortcuts = <ShortcutActivator, Intent>{};
    final backKey = ShortcutHelper.parse(settings.shortcut('goBack'));
    if (backKey != null) shortcuts[backKey] = GoBackIntent();

    return Actions(
      actions: {
        GoBackIntent: CallbackAction<GoBackIntent>(
          onInvoke: (_) => _handleEscBack(context),
        ),
      },
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Focus(autofocus: true, child: widget.child),
      ),
    );
  }
}

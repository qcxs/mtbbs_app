import 'package:flutter/widgets.dart';

/// 主 Tab 页注册「回到顶部 / 刷新」入口，供**重复点击当前 Tab**时调用。
///
/// 规则照 PiliPlus（`pages/main/controller.dart` 的 `setIndex` +
/// `ScrollOrRefreshMixin.toTopOrRefresh`）：
/// - 列表**不在顶部** → 带动画回到顶部
/// - **已在顶部** → 刷新
/// - 500ms 内**连点两次** → 直接刷新（这条由 AppShell 判断，本类负责节流与派发）
///
/// 之所以做成注册表：各 Tab 页自己持有列表控制器（有的是页面私有），
/// AppShell 够不着，只能由页面登记"我该怎么回顶 / 刷新"。
class TabReTap {
  TabReTap._();

  static final TabReTap instance = TabReTap._();

  final Map<String, Future<void> Function()> _handlers = {};

  /// 上次刷新派发时间，用于节流（连点不要连刷）
  final Map<String, int> _lastFireAt = {};

  void register(String path, Future<void> Function() handler) =>
      _handlers[path] = handler;

  /// 只移除**确实是自己注册的那个**（同名重建时旧实例的 dispose 可能晚于
  /// 新实例的 initState，不加 identical 判断会把新注册的顶掉）
  void unregister(String path, Future<void> Function() handler) {
    if (identical(_handlers[path], handler)) _handlers.remove(path);
  }

  /// 回顶或刷新；该 Tab 未注册时返回 false（调用方自行兜底）
  Future<bool> toTopOrRefresh(String path) async {
    final h = _handlers[path];
    if (h == null) return false;
    await h();
    return true;
  }

  /// 直接刷新（连点路径）；500ms 节流，与 PiliPlus 的 EasyThrottle 对齐
  Future<void> refresh(String path) async {
    final h = _handlers[path];
    if (h == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastFireAt[path] ?? 0) < 500) return;
    _lastFireAt[path] = now;
    await h();
  }
}

/// 单列表页面的通用实现：不在顶部回顶，已在顶部刷新。
/// （[this] 为 null 表示该页没有可回顶的主列表 → 直接刷新）
extension TabReTapAction on ScrollController? {
  Future<void> toTopOrRefresh(Future<void> Function() refresh) async {
    final s = this;
    if (s != null && s.hasClients && s.position.pixels > 0) {
      await s.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }
    await refresh();
  }
}

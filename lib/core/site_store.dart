import 'package:flutter/foundation.dart';
import '../config/site_config.dart';
import 'event_bus.dart';

/// 站点状态存储 — 可观察的 ChangeNotifier
///
/// 替代 [SiteConfig] 的可变静态，通过 Provider 注入 Widget 树。
/// Widget 通过 `context.watch<SiteStore>()` 订阅变化，站点切换后自动重建。
///
/// 非 Widget 层通过事件总线 [SiteChangedEvent] 响应切换。
class SiteStore extends ChangeNotifier {
  SiteStore._();
  static final SiteStore _instance = SiteStore._();

  /// 全局单例，供非 Widget 层直接读取
  static SiteStore get instance => _instance;

  List<Site> _sites = [];
  int _currentIndex = 0;

  // ==================== 只读状态 ====================

  /// 所有站点列表
  List<Site> get sites => List.unmodifiable(_sites);

  /// 当前站点索引
  int get currentIndex => _currentIndex;

  /// 当前活跃站点
  Site get current => _sites[_currentIndex];

  /// 当前站点域名
  String get host => current.host;

  /// 当前站点 baseUrl
  String get baseUrl => current.baseUrl;

  /// 当前站点 CDN URL
  String get cdnUrl => current.cdnUrl;

  /// 当前站点登录页路径
  String get loginPagePath => current.loginPagePath;

  /// 当前站点板块列表 (fid → 名称)
  Map<String, String> get forums => current.forums;

  /// 当前站点板块排序
  List<String> get defaultForumOrder => current.defaultForumOrder;

  // ==================== 操作 ====================

  /// 初始化默认站点
  void init({int defaultIndex = 0}) {
    _sites = SiteConfig.defaultSites();
    _currentIndex = defaultIndex.clamp(0, _sites.length - 1);
    notifyListeners();
  }

  /// 替换完整站点列表
  void replaceSites(List<Site> newSites) {
    _sites = List.from(newSites);
    _currentIndex = _currentIndex.clamp(0, _sites.length - 1);
    notifyListeners();
  }

  /// 切换到指定索引的站点
  void switchTo(int index) {
    if (index == _currentIndex) return;
    if (index < 0 || index >= _sites.length) return;
    final prev = current;
    _currentIndex = index;
    notifyListeners();
    EventBus.fire(SiteChangedEvent(previous: prev, current: current));
  }

  /// 更新当前站点的板块列表
  void replaceForums(Map<String, String> newForums) {
    final old = _sites[_currentIndex];
    final newOrder = old.defaultForumOrder
        .where((fid) => newForums.containsKey(fid))
        .toList();
    for (final fid in newForums.keys) {
      if (!newOrder.contains(fid)) newOrder.add(fid);
    }
    _sites[_currentIndex] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      cdn: old.cdn,
      loginPagePath: old.loginPagePath,
      forums: Map.from(newForums),
      defaultForumOrder: newOrder,
    );
    notifyListeners();
  }
}

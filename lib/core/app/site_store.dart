import 'package:flutter/foundation.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/event_bus.dart';
import 'package:mtbbs/core/app/site_cdn.dart';

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

  /// 该站点是否由服务端原生渲染 `[md]…[/md]`。
  ///
  /// 目前只有 52pojie 装了 Markdown 插件；其它站点（含 MT）把 `[md]` 当普通
  /// 文本，解析与渲染都必须按「不支持」处理，否则 App 内会出现只有本机才能
  /// 理解的 Markdown 效果。解析层（`html2markdown`）与渲染层
  /// （`BBCode2Html.supportsMd`）共用这一处判定。
  static bool supportsMdTag(String host) => host == 'www.52pojie.cn';

  /// 该站点是否支持 Discuz 群组（圈子）入口。
  ///
  /// 目前只在 MT 论坛实测到圈子（`group.php`），其它论坛未适配，首页不显示入口。
  static bool supportsGroups(String host) => host == 'bbs.binmt.cc';

  /// 当前站点 baseUrl
  String get baseUrl => current.baseUrl;

  /// 当前站点 CDN URL
  ///
  /// 取自动识别的结果（[SiteCdnStore]），未识别到时回退站点 baseUrl。
  String get cdnUrl => SiteCdnStore.instance.cdnFor(host) ?? baseUrl;

  /// 当前站点登录页路径
  String get loginPagePath => current.loginPagePath;

  /// 当前站点有效 UA
  String get userAgent => current.effectiveUserAgent;

  /// 当前站点是否使用移动端 UA
  bool get isMobileUA => current.isMobileUA;

  /// 当前站点请求参数编码（GBK 站点为 `gbk`）
  String get charset => current.effectiveCharset;

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
  ///
  /// 与 SettingsProvider 的「版块管理」写入口等价，但只改内存并通知。
  /// 需要持久化时仍走 `SettingsProvider.replaceForums`。
  void replaceForums(Map<String, String> newForums) {
    final old = _sites[_currentIndex];
    final newOrder = old.defaultForumOrder
        .where((fid) => newForums.containsKey(fid))
        .toList();
    for (final fid in newForums.keys) {
      if (!newOrder.contains(fid)) newOrder.add(fid);
    }
    _sites[_currentIndex] = old.copyWith(
      forums: Map.from(newForums),
      defaultForumOrder: newOrder,
    );
    notifyListeners();
  }
}

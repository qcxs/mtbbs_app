import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_scope.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/url_util.dart';

part 'url_router_php.dart';
part 'url_router_static.dart';

/// URL 路由解析结果
class UrlRouteResult {
  /// App 内路由路径，null 表示不支持
  final String? appPath;

  /// 匹配到的页面名称
  final String label;

  /// URL 所属的站点 host，非空表示属于其他站点
  final String? siteHost;

  /// URL 所属的站点名称
  final String? siteName;

  const UrlRouteResult({
    this.appPath,
    required this.label,
    this.siteHost,
    this.siteName,
  });

  /// 是否属于其他站点（非当前站点）
  bool get isOtherSite => siteHost != null;
}

/// Discuz URL → App 路由映射器
///
/// 将论坛 URL 解析为 App 内路由路径，支持在浏览器中"用 App 打开"。
///
/// 同时检测 URL 是否属于当前站点，若属于其他站点则标记但不阻止返回路由路径。
///
/// 支持的 URL 模式：
/// - 帖子详情：      `forum.php?mod=viewthread&tid=123` / `thread-123-1-1.html`
/// - 帖子定位回复：  `forum.php?mod=redirect&goto=findpost&pid=X&ptid=Y`
/// - 用户主页：      `home.php?mod=space&uid=456` / `space-uid-456.html`
/// - 用户资料：      `home.php?mod=space&do=profile` / `home.php?mod=space&do=profile&uid=123`
/// - 我的帖子/回复：  `home.php?mod=space[&uid=X]&do=thread[&type=reply]`
/// - 我的收藏：      `home.php?mod=space&do=favorite[&view=me][&type=all|thread|forum]`
/// - 好友 / 留言板：  `home.php?mod=space[&uid=X]&do=friend|wall[&page=N]`
/// - 板块列表：      `forum.php?mod=forumdisplay&fid=42` / `forum-42-1.html` / `forum-42.html`
/// - 发新帖：        `forum.php?mod=post&action=newthread&fid=41`
/// - 回复帖子：      `forum.php?mod=post&action=reply&tid=123`（评论）
/// - 引用回复：      `forum.php?mod=post&action=reply&tid=123&pid=456`
/// - 编辑帖子：      `forum.php?mod=post&action=edit&tid=123&pid=456`
///
/// 页码处理：
/// - `thread-{tid}-{page}-{ordertype}.html` → 从路径提取 page
/// - `forum.php?mod=viewthread&tid=123&page=N` → 从查询参数提取 page
/// - 外部查询参数 `?page=N` 优先级高于路径中的 page
/// - page > 1 时 appPath 包含 `?page=N`
class UrlRouter {
  /// App 自有深链 scheme（桌面长按快捷方式等），与论坛 http(s) 链接相区分
  static const String appScheme = 'mtbbs';

  /// 解析 Discuz URL，返回 App 路由结果
  ///
  /// [url] 可以是完整 URL 或部分路径。
  /// 会自动检测 URL 所属的站点，若与当前站点不同则标记 [siteHost]/[siteName]。
  static UrlRouteResult parse(String url) {
    // 先检测 URL 是否属于其他站点
    final host = _extractHost(url);
    String? otherSiteHost;
    String? otherSiteName;

    if (host != null) {
      final currentHost = Uri.tryParse(SiteStore.instance.baseUrl)?.host;
      if (currentHost != null && host != currentHost) {
        // 查找匹配的站点名称
        for (final site in SiteStore.instance.sites) {
          final siteHost = Uri.tryParse(site.baseUrl)?.host;
          if (siteHost == host) {
            otherSiteHost = host;
            otherSiteName = site.name;
            break;
          }
        }
        // 未在已配置站点中找到，但确实不是当前站点
        if (otherSiteHost == null) {
          otherSiteHost = host;
          otherSiteName = host;
        }
      }
    }

    // 提取 path + query
    final parsed = _parseNormalized(url);
    if (parsed == null) {
      return UrlRouteResult(
        label: '不支持的页面',
        appPath: null,
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }

    final path = parsed.path;
    final query = parsed.queryParameters;
    final site = (host: otherSiteHost, name: otherSiteName);

    // ==================== 帖子详情 ====================
    if (path.endsWith('/forum.php') || path.endsWith('forum.php')) {
      final result = _matchForumPhp(query, site);
      if (result != null) return result;
    }

    // ==================== 圈子（群组） ====================
    if (path.endsWith('/group.php') || path.endsWith('group.php')) {
      return _matchGroupPhp(query, site);
    }

    // ==================== 用户主页 ====================
    if (path.endsWith('/home.php') || path.endsWith('home.php')) {
      final result = _matchHomePhp(query, site);
      if (result != null) return result;
    }

    // ==================== 用户空间短链 ====================
    // `https://bbs.binmt.cc/?100`：查询串为纯数字，视为 uid → 个人空间
    if (path.isEmpty || path == '/') {
      final result = _matchBareUidSpace(query, site);
      if (result != null) return result;
    }

    // ==================== 排行榜 ====================
    if (path.endsWith('/misc.php') || path.endsWith('misc.php')) {
      final result = _matchMiscPhp(query, site);
      if (result != null) return result;
    }

    // ==================== 伪静态格式 ====================
    final staticResult = _matchPseudoStatic(url, query, site);
    if (staticResult != null) return staticResult;

    // ==================== 站内搜索 ====================
    final searchResult = _matchSearchPhp(path, query, site);
    if (searchResult != null) return searchResult;

    // ==================== 不支持的页面 ====================
    return UrlRouteResult(
      label: '不支持的页面',
      appPath: null,
      siteHost: otherSiteHost,
      siteName: otherSiteName,
    );
  }

  /// 决定一个链接的落地位置 —— **链接 → 页面的唯一决策点**。
  ///
  /// - 能映射到 App 内页面、且属于当前站点 → 返回 App 内路由路径
  /// - 属于**其他已配置站点**、且该页面已支持跨站点访问 → 返回带 `site=<host>`
  ///   的 App 内路径，由页面以"该站默认账号/游客"的临时身份打开
  /// - 解析不出、属于未配置站点、或其他尚未迁移的页面 → 返回内置浏览器兜底路径
  /// - 空串 → 返回 null（调用方不跳转）
  ///
  /// 兜底路径带 `intercept=false`：内置浏览器不再二次拦截，否则会出现
  /// "App 打开 → 又被浏览器接管"的往返。
  ///
  /// 首页链接点击、帖子正文里的链接、系统「打开方式」入站链接都走这里，
  /// 保证行为一致（此前各处各写一份，兜底参数还漏过）。
  static String? resolveTarget(String url) {
    final text = url.trim();
    if (text.isEmpty) return null;
    // App 自定义 scheme（桌面长按快捷方式等自有深链）：
    // `mtbbs://settings/cache` → `/settings/cache`
    if (text.startsWith('$appScheme://')) {
      final uri = Uri.tryParse(text);
      final rest = '${uri?.host ?? ''}${uri?.path ?? ''}';
      return rest.isEmpty ? null : '/$rest';
    }
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      // 已经是 App 内路径
      return text;
    }
    final result = parse(text);
    if (result.appPath != null) {
      if (!result.isOtherSite) return result.appPath;
      // 跨站点：已配置 + 页面已支持作用域访问 → 直接进 App 内（临时身份）
      final host = result.siteHost!;
      if (SessionRegistry.instance.baseUrlForHost(host) != null &&
          supportsCrossSite(result.appPath!)) {
        return withSiteParam(result.appPath!, host);
      }
    }
    return '/browser?url=${Uri.encodeComponent(text)}&intercept=false';
  }

  /// 已迁移到"作用域会话（SiteScope）"的页面。
  ///
  /// 逐步扩大：新增页面接入后把它加进来；未加入的跨站链接仍走内置浏览器，
  /// 避免"页面用全局身份打开别的站点 → 看到错误数据"。
  static const Set<String> crossSitePages = {
    'thread',
    'user',
    'online',
    'ranklist',
    'darkroom',
    'search',
  };

  /// 该 App 内路径是否支持以别的站点身份打开
  static bool supportsCrossSite(String appPath) {
    final path = appPath.split('?').first;
    // 只读缓存页没有站内地址，不参与
    if (path == '/thread/cache') return false;
    if (path.startsWith('/thread/')) return crossSitePages.contains('thread');
    // 用户主页：仅资料页只读；留言板（/user/x/wall）与本人(self)有写操作/本地语义，不参与
    if (path.startsWith('/user/')) {
      if (path.endsWith('/wall')) return false;
      if (path == '/user/self') return false;
      return crossSitePages.contains('user');
    }
    // 纯只读列表页：在线用户 / 用户排行 / 小黑屋
    if (path == '/online' || path == '/ranklist' || path == '/darkroom') {
      return crossSitePages.contains(path.substring(1));
    }
    // 搜索结果页（只读）
    if (path == '/search/result') return crossSitePages.contains('search');
    return false;
  }

  /// 从 URL 中提取主机名
  static String? _extractHost(String url) {
    final fullUrl = url.contains('://') ? url : 'https://$url';
    final uri = Uri.tryParse(fullUrl);
    return uri?.host;
  }

  /// 标准化 URL：提取 path 和 query，去掉 baseUrl 前缀
  static ({String path, Map<String, String> queryParameters})? _parseNormalized(
    String url,
  ) {
    try {
      final fullUrl = url.contains('://') ? url : 'https://$url';
      final uri = Uri.parse(fullUrl);
      // 不能直接用 uri.queryParameters：它会按 UTF-8 解码整串参数，
      // GBK 站点的 highlight=%B5%E3%C6%C0 会抛 FormatException，
      // 导致带搜索高亮参数的帖子链接被判为"不支持的页面"。
      return (path: uri.path, queryParameters: parseQueryLenient(uri.query));
    } catch (_) {
      return null;
    }
  }
}

import '../config/site_config.dart';

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
      final currentHost = Uri.tryParse(SiteConfig.baseUrl)?.host;
      if (currentHost != null && host != currentHost) {
        // 查找匹配的站点名称
        for (final site in SiteConfig.sites) {
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

    // ==================== 帖子详情 ====================

    if (path.endsWith('/forum.php') || path.endsWith('forum.php')) {
      final mod = query['mod'];
      if (mod == 'viewthread') {
        final tid = query['tid'];
        if (tid != null && tid.isNotEmpty) {
          final page = _resolvePage(query['page']);
          return UrlRouteResult(
            label: '帖子详情',
            appPath: _threadPath(tid, page),
            siteHost: otherSiteHost,
            siteName: otherSiteName,
          );
        }
        return UrlRouteResult(
          label: '帖子详情（缺少 tid）',
          appPath: null,
          siteHost: otherSiteHost,
          siteName: otherSiteName,
        );
      }

      if (mod == 'redirect') {
        final goto = query['goto'];
        if (goto == 'findpost') {
          final pid = query['pid'];
          final ptid = query['ptid'];
          if (pid != null &&
              pid.isNotEmpty &&
              ptid != null &&
              ptid.isNotEmpty) {
            return UrlRouteResult(
              label: '帖子详情（定位回复）',
              appPath: '/thread/$ptid?pid=$pid',
              siteHost: otherSiteHost,
              siteName: otherSiteName,
            );
          }
        }
        return UrlRouteResult(
          label: '帖子详情（缺少参数）',
          appPath: null,
          siteHost: otherSiteHost,
          siteName: otherSiteName,
        );
      }

      if (mod == 'forumdisplay') {
        final fid = query['fid'];
        if (fid != null && fid.isNotEmpty) {
          final page = _resolvePage(query['page']);
          final pageSuffix = page > 1 ? '&page=$page' : '';
          return UrlRouteResult(
            label: '板块',
            appPath: '/forum?fid=$fid$pageSuffix',
            siteHost: otherSiteHost,
            siteName: otherSiteName,
          );
        }
        return UrlRouteResult(
          label: '板块（缺少 fid）',
          appPath: null,
          siteHost: otherSiteHost,
          siteName: otherSiteName,
        );
      }

      if (mod == 'post') {
        final postResult = _parsePostUrl(query);
        return UrlRouteResult(
          label: postResult.label,
          appPath: postResult.appPath,
          siteHost: otherSiteHost,
          siteName: otherSiteName,
        );
      }
    }

    // ==================== 用户主页 ====================

    if (path.endsWith('/home.php') || path.endsWith('home.php')) {
      final mod = query['mod'];
      if (mod == 'space') {
        final uid = query['uid'];
        if (uid != null && uid.isNotEmpty) {
          return UrlRouteResult(
            label: '用户主页',
            appPath: '/user/$uid',
            siteHost: otherSiteHost,
            siteName: otherSiteName,
          );
        }
        // home.php?mod=space&do=profile — 当前用户个人资料页（无 uid）
        if (query['do'] == 'profile') {
          return UrlRouteResult(
            label: '我的主页',
            appPath: '/user/self',
            siteHost: otherSiteHost,
            siteName: otherSiteName,
          );
        }
        return UrlRouteResult(
          label: '用户主页（缺少 uid）',
          appPath: null,
          siteHost: otherSiteHost,
          siteName: otherSiteName,
        );
      }
    }

    // ==================== 伪静态格式 ====================

    // thread-{tid}-{page}-{ordertype}.html
    // 示例：thread-169246.html → tid=169246（无 page）
    //       thread-169246-5-1.html → tid=169246, page=5
    //       支持外部 ?page=N 覆盖，如 thread-169246-1-1.html?page=2
    final threadFull = RegExp(r'thread-(\d+)-(\d+)').firstMatch(url);
    if (threadFull != null) {
      final tid = threadFull.group(1)!;
      final pathPage = int.tryParse(threadFull.group(2)!) ?? 1;
      // 外部查询参数 page 优先级高于路径中的 page
      final page = _resolvePage(query['page'], fallback: pathPage);
      return UrlRouteResult(
        label: '帖子详情',
        appPath: _threadPath(tid, page),
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }
    // thread-{tid}.html（无 page/ordertype 的简写格式）
    final threadSimple = RegExp(r'thread-(\d+)').firstMatch(url);
    if (threadSimple != null) {
      final tid = threadSimple.group(1)!;
      final page = _resolvePage(query['page']);
      return UrlRouteResult(
        label: '帖子详情',
        appPath: _threadPath(tid, page),
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }

    // space-uid-456.html
    final spaceMatch = RegExp(r'space-uid-(\d+)').firstMatch(url);
    if (spaceMatch != null) {
      final uid = spaceMatch.group(1)!;
      return UrlRouteResult(
        label: '用户主页',
        appPath: '/user/$uid',
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }

    // ==================== 板块（伪静态） ====================

    // forum-{fid}-{page}.html
    // 示例：forum-42-1.html → fid=42, page=1
    final forumFull = RegExp(r'forum-(\d+)-(\d+)').firstMatch(url);
    if (forumFull != null) {
      final fid = forumFull.group(1)!;
      final page = int.tryParse(forumFull.group(2)!) ?? 1;
      final pageSuffix = page > 1 ? '&page=$page' : '';
      return UrlRouteResult(
        label: '板块',
        appPath: '/forum?fid=$fid$pageSuffix',
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }
    // forum-{fid}.html（无 page 的简写格式）
    final forumSimple = RegExp(r'forum-(\d+)').firstMatch(url);
    if (forumSimple != null) {
      final fid = forumSimple.group(1)!;
      return UrlRouteResult(
        label: '板块',
        appPath: '/forum?fid=$fid',
        siteHost: otherSiteHost,
        siteName: otherSiteName,
      );
    }

    // ==================== 不支持的页面 ====================

    return UrlRouteResult(
      label: '不支持的页面',
      appPath: null,
      siteHost: otherSiteHost,
      siteName: otherSiteName,
    );
  }

  /// 构建帖子路由路径，page > 1 时附加 ?page=N
  static String _threadPath(String tid, int page) {
    if (page > 1) return '/thread/$tid?page=$page';
    return '/thread/$tid';
  }

  /// 解析 page 参数。先尝试外部查询参数，失败时使用[fallback]（默认 1）。
  static int _resolvePage(String? externalPage, {int fallback = 1}) {
    if (externalPage != null) {
      final p = int.tryParse(externalPage);
      if (p != null && p > 1) return p;
    }
    return fallback;
  }

  /// 从 URL 中提取主机名
  static String? _extractHost(String url) {
    final fullUrl = url.contains('://') ? url : 'https://$url';
    final uri = Uri.tryParse(fullUrl);
    return uri?.host;
  }

  /// 解析 forum.php?mod=post 类型的 URL
  static ({String label, String? appPath}) _parsePostUrl(
    Map<String, String> query,
  ) {
    final action = query['action'];
    final tid = query['tid'];
    final pid = query['pid'];
    final fid = query['fid'];

    switch (action) {
      case 'newthread':
        if (fid != null && fid.isNotEmpty) {
          return (label: '发新帖', appPath: '/editor?type=post&fid=$fid');
        }
        return (label: '发新帖（缺少 fid）', appPath: null);

      case 'reply':
        if (tid == null || tid.isEmpty) {
          return (label: '回复帖子（缺少 tid）', appPath: null);
        }
        if (pid != null && pid.isNotEmpty) {
          // 引用回复
          return (
            label: '回复评论',
            appPath: '/editor?type=reply&tid=$tid&pid=$pid',
          );
        }
        // 普通评论
        return (label: '评论帖子', appPath: '/editor?type=comment&tid=$tid');

      case 'edit':
        if (tid != null && tid.isNotEmpty && pid != null && pid.isNotEmpty) {
          return (
            label: '编辑帖子',
            appPath: '/editor?type=editPost&tid=$tid&pid=$pid',
          );
        }
        return (label: '编辑帖子（缺少参数）', appPath: null);

      default:
        return (label: '不支持的页面', appPath: null);
    }
  }

  /// 标准化 URL：提取 path 和 query，去掉 baseUrl 前缀
  static ({String path, Map<String, String> queryParameters})? _parseNormalized(
    String url,
  ) {
    try {
      final fullUrl = url.contains('://') ? url : 'https://$url';
      final uri = Uri.parse(fullUrl);
      return (path: uri.path, queryParameters: uri.queryParameters);
    } catch (_) {
      return null;
    }
  }
}

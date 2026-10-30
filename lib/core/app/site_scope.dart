import 'package:flutter/widgets.dart';
import 'package:mtbbs/core/app/site_session.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 页面级「站点会话」作用域。
///
/// 路由层根据 location 上的 `site=<host>`（可选 `as=<账号>`）参数注入；
/// 页面用 `SiteScope.of(context)` 取代 `ApiService().dio` / `SiteStore.instance`
/// 的全局读取，从而让同一个页面既能打开当前站点，也能打开别的站点。
///
/// 没有作用域（或没有 `site` 参数）时返回主会话，行为与旧版完全一致。
class SiteScope extends InheritedWidget {
  final SiteSession session;

  const SiteScope({super.key, required this.session, required super.child});

  static SiteSession of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SiteScope>();
    return scope?.session ?? const GlobalSiteSession();
  }

  /// 不建立依赖的读取（异步回调里用，避免无谓重建）
  static SiteSession read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SiteScope>();
    return scope?.session ?? const GlobalSiteSession();
  }

  /// 当前 location 是否指向"别的站点"
  static bool isCrossSiteLocation(Uri uri) {
    final site = uri.queryParameters['site'];
    return site != null &&
        site.isNotEmpty &&
        site != SiteStore.instance.host;
  }

  /// 在当前作用域下打开 App 内路径：跨站页面自动续接 `site=`，
  /// 全局页面原样返回。页面内部跳转（如用户主页 → 另一个用户）用它，
  /// 否则会把"目标站点"丢掉、退回全局身份。
  static String pathFor(BuildContext context, String appPath) {
    final session = read(context);
    if (session.temporary) return withSiteParam(appPath, session.host);
    return appPath;
  }

  @override
  bool updateShouldNotify(SiteScope oldWidget) =>
      oldWidget.session != session;
}

/// 给 App 内路径附加站点参数（跨站跳转传播用）。
///
/// 已有查询参数时用 `&` 续接；`/thread/1` → `/thread/1?site=52pojie.com`。
String withSiteParam(String appPath, String host, {String? account}) {
  if (host.isEmpty) return appPath;
  final sep = appPath.contains('?') ? '&' : '?';
  final base = '$appPath$sep'
      'site=${Uri.encodeQueryComponent(host)}';
  if (account == null || account.isEmpty) return base;
  return '$base&as=${Uri.encodeQueryComponent(account)}';
}

/// 从 App 内路径里去掉站点参数（拼站内 URL / 复制链接时用）
String withoutSiteParam(String appPath) {
  final uri = Uri.tryParse(appPath);
  if (uri == null) return appPath;
  final q = Map<String, String>.from(uri.queryParameters);
  if (!q.containsKey('site') && !q.containsKey('as')) return appPath;
  q.remove('site');
  q.remove('as');
  final query = q.isEmpty
      ? ''
      : '?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  return '${uri.path}$query';
}

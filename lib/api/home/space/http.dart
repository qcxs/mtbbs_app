import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/settings/settings_repository.dart';

/// 用户空间主页 HTTP 请求 — 基于 Dio
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供。
///
/// UA 默认跟随站点「浏览模式」（移动→克米移动模板；桌面→标准 PC 模板），
/// 但本页支持**站点级覆盖**：用户可在空间页菜单或站点设置里单独切换数据源。
/// 两类模板结构不同，由 parse 层按 DOM 分流（见 parse.dart）。

/// 本页请求实际使用的 UA：请求级覆盖（探针 / MCP）> 站点设置 > 站点「浏览模式」。
///
/// 数据源是**目标站点的站点设置**（`SiteSettings.content.spaceSource`），
/// 跨站点空间页也按该站点自己的配置取，不跟随当前站点。
String _resolvedUserAgent(Dio dio) {
  if (browseModeOverrideActive()) return resolveRequestUserAgent();
  final host = Uri.tryParse(dio.options.baseUrl)?.host ?? '';
  final source = SettingsRepository.instance.site(host).content.spaceSource;
  switch (source) {
    case 'mobile':
      return Site.uaAndroid;
    case 'desktop':
      return Site.uaPc;
    default:
      return SiteStore.instance.userAgent;
  }
}

/// 获取用户个人资料页面
///
/// 查询优先级：[uid] > [username] > 当前登录用户自己
/// - [uid] 不为空 → 按 uid 查询
/// - [username] 不为空 → 按用户名查询
/// - 两者都为空 → 返回当前登录用户自己的资料
///
/// [options] 由调用方追加请求级配置（如 `extra` 标记），站点 UA 仍由本函数写入。
Future<Response<String>> getUserProfile(
  Dio dio, {
  String uid = '',
  String username = '',
  Options? options,
}) {
  final path = _buildPath(uid, username);
  final opts = options ?? Options();
  opts.headers = {...?opts.headers, 'User-Agent': _resolvedUserAgent(dio)};
  return dio.get<String>(path, options: opts);
}

String _buildPath(String uid, String username) {
  if (uid.isNotEmpty) {
    return '/home.php?mod=space&uid=$uid&do=profile';
  }
  if (username.isNotEmpty) {
    return '/home.php?mod=space&username=${Uri.encodeComponent(username)}&do=profile';
  }
  return '/home.php?mod=space&do=profile';
}

import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 用户空间主页 HTTP 请求 — 基于 Dio
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供。
///
/// UA 默认跟随站点「浏览模式」（移动→克米移动模板；桌面→标准 PC 模板），
/// 但本页支持**页面级覆盖**（见 [spaceSourceOverride]）：用户可在空间页菜单里
/// 单独切换数据源，不影响导读/板块等其它页面。两类模板结构不同，由 parse 层
/// 按 DOM 分流（见 parse.dart）。

/// 个人空间数据源覆盖：`''` = 跟随站点「浏览模式」；`'mobile'`/`'desktop'` = 本页强制。
///
/// 放在模块级（同 `_simulateBrowserHeaders`）：`SettingsProvider.load()` 在请求之前
/// 执行且需同步读取；持久化由 `SettingsProvider` 负责写入。
String _sourceOverride = '';

/// 写入覆盖值（由 SettingsProvider 在加载/修改时调用）
void applySpaceSourceOverride(String value) => _sourceOverride = value;

/// 当前覆盖设置（`''` 表示未覆盖，跟随「浏览模式」）
String get spaceSourceOverride => _sourceOverride;

/// 本页请求实际使用的 UA：有覆盖则强制，否则跟随站点「浏览模式」
String _resolvedUserAgent() {
  switch (_sourceOverride) {
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
  opts.headers = {...?opts.headers, 'User-Agent': _resolvedUserAgent()};
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

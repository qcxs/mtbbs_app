import 'dart:async';

import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/session_registry.dart';
import 'package:mtbbs/core/app/site_session.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';
import 'package:mtbbs/services/api_service.dart';

/// MCP 单次调用的「站点 + 身份」作用域。
///
/// 默认（未传 `site` / `account`）不存在作用域，工具沿用全局当前站点与当前账号。
/// `site` 属于公开信息，默认允许；`account` 会以其它账号的登录态读取，默认关闭，
/// 只有用户在设置里手动开启后才允许传。
///
/// 作用域放在 Zone 里而不是全局变量：MCP 允许并发调用，全局开关会串味。
/// 工具层统一读 [McpScope.effectiveDio] / [McpScope.effectiveHost] /
/// [McpScope.effectiveUid]，不再直接取全局单例。
class McpScope {
  const McpScope({
    required this.host,
    required this.baseUrl,
    required this.siteName,
    required this.charset,
    required this.userAgent,
    required this.isMobileUA,
    required this.dio,
    required this.uid,
    required this.username,
    required this.isLoggedIn,
    required this.crossSite,
  });

  /// 目标站点域名
  final String host;

  /// 目标站点 baseUrl（不带末尾 `/`）
  final String baseUrl;

  /// 目标站点显示名
  final String siteName;

  /// 目标站点请求编码
  final String charset;

  /// 目标站点 UA
  final String userAgent;

  final bool isMobileUA;

  /// 绑定到目标站点 + 目标账号的 Dio
  final Dio dio;

  final String uid;
  final String username;
  final bool isLoggedIn;

  /// 是否为「另一个站点」（false = 当前站点但换了个账号视角）
  final bool crossSite;

  /// 换算成 MCP 登录态快照（`get_app_info` 用）
  McpAccountInfo get account => McpAccountInfo(
    isLoggedIn: isLoggedIn,
    username: username,
    uid: uid,
    userGroup: isLoggedIn ? (crossSite ? '跨站只读视角' : '当前站点账号视角') : '游客',
  );

  /// 传给 API 层的请求级站点上下文（UA / 字符集等）
  RequestSiteOverride get requestSite => RequestSiteOverride(
    host: host,
    baseUrl: baseUrl,
    charset: charset,
    userAgent: userAgent,
    isMobileUA: isMobileUA,
  );

  /// 当前调用链上的作用域（无覆盖返回 null）
  static McpScope? get current => Zone.current[kMcpScopeZoneKey] as McpScope?;

  /// 工具层统一入口：本次调用应使用的 Dio
  static Dio get effectiveDio => current?.dio ?? ApiService().dio;

  /// 本次调用应使用的站点域名（本地缓存按它隔离）
  static String get effectiveHost => current?.host ?? SiteStore.instance.host;

  /// 本次调用应使用的查看者 uid（缓存 viewer / 当前账号判定）
  static String get effectiveUid =>
      current?.uid ?? SessionRegistryIdentity.current.uid;

  /// 解析 `site` / `account` 参数。
  ///
  /// 返回 null 表示"没有覆盖，沿用全局当前站点与当前账号"。
  /// 权限未开启或参数无法解析时抛 [ArgumentError]，由调用包装转成可读的 MCP 错误。
  static Future<McpScope?> resolve({
    required Map<String, dynamic> args,
    required bool allowCrossSite,
    required bool allowAccountSwitch,
  }) async {
    final siteArg = McpArgs.str(args, 'site');
    final accountArg = McpArgs.str(args, 'account');
    if (siteArg.isEmpty && accountArg.isEmpty) return null;

    if (siteArg.isNotEmpty && !allowCrossSite) {
      throw ArgumentError(
        '跨站点访问未开启：用户需先在「设置 → MCP 服务 → 跨站点与身份」里'
        '开启「允许跨站点访问」',
      );
    }
    if (accountArg.isNotEmpty && !allowAccountSwitch) {
      throw ArgumentError(
        '切换用户视角未开启：用户需先在「设置 → MCP 服务 → 跨站点与身份」里'
        '开启「允许切换用户视角」',
      );
    }

    final target = siteArg.isEmpty
        ? SiteStore.instance.current
        : _findSite(siteArg);
    if (target == null) {
      throw ArgumentError(
        '未找到站点「$siteArg」。可用的站点：${_siteChoices()}',
      );
    }

    final account = accountArg.isEmpty ? null : accountArg;
    if (target.host == SiteStore.instance.host) {
      return _forCurrentSite(target, account: account);
    }
    return _forOtherSite(target, account: account);
  }

  // ==================== 内部 ====================

  /// 当前站点只换账号：与全局身份相同时直接沿用全局 Dio，避免两份 CookieJar
  /// 指向同一个磁盘目录（见 docs/27「当前站点不建作用域会话」）。
  static Future<McpScope?> _forCurrentSite(
    Site site, {
    required String? account,
  }) async {
    if (account == null) return null;

    final active = SessionRegistryIdentity.current;
    if (active.username == account) return null;

    final match = _accountNamed(site.host, account);
    if (match == null) {
      throw ArgumentError(
        '当前站点没有已登录账号「$account」。可用账号：${_accountChoices(site.host)}',
      );
    }
    final dio = await ApiService().scopedDio(
      host: site.host,
      baseUrl: site.baseUrl,
      account: account,
    );
    return McpScope(
      host: site.host,
      baseUrl: site.baseUrl,
      siteName: site.name,
      charset: site.effectiveCharset,
      userAgent: site.effectiveUserAgent,
      isMobileUA: site.isMobileUA,
      dio: dio,
      uid: match.uid,
      username: match.username,
      isLoggedIn: true,
      crossSite: false,
    );
  }

  /// 其它已配置站点：走 [SessionRegistry] 预建的作用域会话
  static Future<McpScope> _forOtherSite(
    Site site, {
    required String? account,
  }) async {
    if (account != null && _accountNamed(site.host, account) == null) {
      throw ArgumentError(
        '站点「${site.name}」没有已登录账号「$account」。可用账号：${_accountChoices(site.host)}',
      );
    }
    final session = SessionRegistry.instance.resolve(site.host, account: account);
    if (session == null) {
      throw StateError(
        '站点「${site.name}」的会话尚未就绪（App 可能仍在启动或该站点刚被修改），请稍后重试',
      );
    }
    return McpScope(
      host: session.host,
      baseUrl: session.baseUrl,
      siteName: site.name,
      charset: session.charset,
      userAgent: site.effectiveUserAgent,
      isMobileUA: site.isMobileUA,
      dio: session.dio,
      uid: session.uid,
      username: session.username,
      isLoggedIn: session.isLoggedIn,
      crossSite: true,
    );
  }

  /// 按域名 / baseUrl 域名 / 站点名匹配已配置站点（大小写不敏感）
  static Site? _findSite(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(
      text.contains('://') ? text : 'https://$text',
    );
    final host = (uri?.host ?? text).toLowerCase();
    for (final site in SiteStore.instance.sites) {
      final baseHost =
          Uri.tryParse(site.baseUrl)?.host.toLowerCase() ?? site.host;
      if (site.host.toLowerCase() == host ||
          baseHost == host ||
          site.name.trim() == text) {
        return site;
      }
    }
    return null;
  }

  static SiteAccount? _accountNamed(String host, String username) {
    for (final account in SessionRegistry.instance.accountsFor(host)) {
      if (account.username == username) return account;
    }
    return null;
  }

  static String _accountChoices(String host) {
    final names = SessionRegistry.instance.accountNamesFor(host);
    return names.isEmpty ? '（该站点暂无已登录账号）' : names.join(' / ');
  }

  static String _siteChoices() =>
      SiteStore.instance.sites.map((s) => '${s.name}(${s.host})').join(' / ');
}

/// Zone 覆盖键（值：[McpScope]）
const Symbol kMcpScopeZoneKey = #mtbbsMcpScope;

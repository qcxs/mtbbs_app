/// 请求级「浏览模式」覆盖（UA 换用）。
///
/// - **默认**：所有请求跟随站点「浏览模式」（`SiteStore.userAgent`；空 = 移动 UA）。
/// - **覆盖**：探针（进程级，一次运行固定）与 MCP 工具调用（Zone 级，仅本次调用）
///   可临时指定 `mobile` / `desktop`，用于"某套模板解析出问题时换 UA 复测"，
///   也为探针补齐桌面模板分支的覆盖能力。
///
/// 为什么 MCP 侧用 Zone 而不是全局变量：MCP 可能被并发调用，全局开关会串味；
/// Zone 把覆盖绑在本次异步调用链上，天然隔离。探针是单进程一次性运行，用进程级
/// 覆盖最省事（其后任意调用点都读到同一个值）。
library;

import 'dart:async';

import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// Zone 覆盖键（值：`'mobile'` | `'desktop'`）
const Symbol kBrowseModeZoneKey = #mtbbsBrowseModeOverride;

/// 请求级「站点上下文」覆盖键（值：[RequestSiteOverride]）。
///
/// MCP 单次调用可临时以另一个已配置站点（乃至另一个账号）的身份读取，
/// 这里承载不随 Dio 变化的站点元信息，让 `resolveRequestUserAgent` /
/// `resolveRequestCharset` 等调用点在跨站时仍拿到**目标站点**的值。
const Symbol kRequestSiteZoneKey = #mtbbsRequestSiteOverride;

/// 进程级覆盖（探针用；null = 未覆盖）
String? _stickyOverride;

/// 请求级站点上下文（MCP 跨站点调用用；仅本次调用有效）
class RequestSiteOverride {
  const RequestSiteOverride({
    required this.host,
    required this.baseUrl,
    required this.charset,
    required this.userAgent,
    required this.isMobileUA,
  });

  final String host;
  final String baseUrl;
  final String charset;
  final String userAgent;
  final bool isMobileUA;
}

/// 当前生效的请求级站点上下文（无覆盖返回 null）
RequestSiteOverride? currentRequestSite() =>
    Zone.current[kRequestSiteZoneKey] as RequestSiteOverride?;

/// 本次请求应使用的参数编码：站点上下文覆盖优先，否则跟随全局站点。
String resolveRequestCharset() =>
    currentRequestSite()?.charset ?? SiteStore.instance.charset;

/// 归一浏览模式：`mobile`/`m` → `mobile`；`desktop`/`pc`/`d` → `desktop`；
/// 其它（含空串 / `default` / `auto`）→ null，表示不覆盖、跟随站点浏览模式。
String? normalizeBrowseMode(String? mode) {
  switch ((mode ?? '').trim().toLowerCase()) {
    case 'mobile':
    case 'm':
      return 'mobile';
    case 'desktop':
    case 'pc':
    case 'd':
      return 'desktop';
    default:
      return null;
  }
}

/// 设置 / 清除进程级覆盖（探针在一次运行开始时调用；传空即清除）
void applyStickyBrowseMode(String? mode) =>
    _stickyOverride = normalizeBrowseMode(mode);

/// 当前生效的覆盖值（Zone 优先于进程级）；无覆盖返回 null
String? currentBrowseModeOverride() =>
    (Zone.current[kBrowseModeZoneKey] as String?) ?? _stickyOverride;

/// 是否处于"覆盖"状态（供 [ApiService] 决定是否改写请求 UA）
bool browseModeOverrideActive() => currentBrowseModeOverride() != null;

/// 本次请求应使用的 UA：浏览模式覆盖 > 站点上下文 > 全局站点「浏览模式」。
///
/// 供 API 层（`api/**/http.dart`）与 [ApiService] 的覆盖拦截器共用。
String resolveRequestUserAgent() {
  switch (currentBrowseModeOverride()) {
    case 'mobile':
      return Site.uaAndroid;
    case 'desktop':
      return Site.uaPc;
    default:
      return currentRequestSite()?.userAgent ?? SiteStore.instance.userAgent;
  }
}

/// 在指定浏览模式下执行 [body]（仅本次调用有效；MCP 工具用）。
///
/// [mode] 归一失败（空 / 非法 / `default`）时直接执行，不覆盖。
Future<T> runWithBrowseMode<T>(String? mode, Future<T> Function() body) {
  final normalized = normalizeBrowseMode(mode);
  if (normalized == null) return body();
  return runZoned(body, zoneValues: {kBrowseModeZoneKey: normalized});
}

/// 同时套用「浏览模式」与「站点上下文」的 Zone 覆盖（MCP 单次调用用）。
///
/// 两者都为 null 时直接执行；任一存在时只设置存在的键，CPU 开销可忽略。
Future<T> runWithRequestContext<T>({
  String? browseMode,
  RequestSiteOverride? site,
  required Future<T> Function() body,
}) {
  final mode = normalizeBrowseMode(browseMode);
  final zoneValues = <Symbol, Object>{};
  if (mode != null) zoneValues[kBrowseModeZoneKey] = mode;
  if (site != null) zoneValues[kRequestSiteZoneKey] = site;
  if (zoneValues.isEmpty) return body();
  return runZoned(body, zoneValues: zoneValues);
}

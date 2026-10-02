import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 本次探测是否命中"非论坛页"（人机验证 / 防火墙拦截页）。
///
/// 入口层据此追加 `reminder`，告诉调用方"怎么过验证"，而不是丢一堆挑战页 HTML。
bool probeInterstitialHit = false;

/// Windows 证书补丁（与 main.dart 的 _WindowsCertOverride 同款）
///
/// Flutter/Dart 在 Windows 上使用 BoringSSL，某些环境无法读取根证书，
/// 导致 HTTPS 握手失败。此处绕过校验，信任交由上层处理。
class WindowsCertOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

/// 模拟 App 初始化序列（复刻 main.dart，去掉 UI 与数据库层）
///
/// 顺序：
/// 1. 初始化测试绑定（rootBundle 可用，defaults.json 可加载）
/// 2. 恢复真实网络（flutter_test 默认 mock 掉 HttpClient 返回 400）
///    + 套用 Windows 证书补丁
/// 3. 加载默认配置 → 初始化站点 → 初始化 ApiService（复用 App 的 Cookie 目录）
/// 4. 切换 Cookie：指定 [account] 用其登录态，否则用游客态
///
/// [site] 指定站点（索引数字或站点名，空 = 默认第一个站点），
/// 用于跨站点测试（如吾爱破解与 MT 论坛使用同一套 API 层）。
///
/// [baseUrl] 指定任意站点 URL（测试站等不在默认列表中的站点）。
/// 传入时替换站点列表为单站（name 用 [siteName] 或域名），
/// Cookie 目录自动跟随 host（`%APPDATA%\qcxs\mtbbs_debug\cookies\{host}`）。
///
/// [cookie] / [header] 是**临时注入**的额外凭证与请求头，用于站点开启
/// 人机验证 / 防盗链等防护时的自保（详见 docs/10 与下方 [_applyProbeExtras]）。
Future<void> bootstrap({
  String account = '',
  String site = '',
  String baseUrl = '',
  String siteName = '',
  String cookie = '',
  String header = '',
}) async {
  probeInterstitialHit = false;
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 会安装 _MockHttpOverrides（所有请求返回 400），
  // 必须用真实 HttpOverrides 覆盖才能发真实网络请求。
  HttpOverrides.global = WindowsCertOverride();

  await DefaultConfig.instance.load();
  if (baseUrl.isNotEmpty) {
    // 动态站点：替换为单站列表（测试站不在 defaults.json 中）
    SiteStore.instance.replaceSites([
      Site(
        name: siteName.isNotEmpty ? siteName : Uri.parse(baseUrl).host,
        baseUrl: baseUrl,
        loginPagePath: '/member.php?mod=logging&action=login',
        forums: const {},
        defaultForumOrder: const [],
      ),
    ]);
  } else {
    SiteStore.instance.init();
    if (site.isNotEmpty) {
      final byIndex = int.tryParse(site);
      final target =
          byIndex ?? SiteStore.instance.sites.indexWhere((s) => s.name == site);
      if (target > 0) SiteStore.instance.switchTo(target);
    }
  }
  await ApiService().init(baseUrl: SiteStore.instance.baseUrl);
  if (account.isNotEmpty) {
    await ApiService().switchToAccount(account);
  } else {
    await ApiService().switchToGuest();
  }
  // 注入要在切换 CookieJar 之后：cookie 写进的是"当前活跃"那个 jar
  await _applyProbeExtras(cookie: cookie, header: header);
  _installInterstitialProbe();
}

/// 注入临时请求头 / Cookie
///
/// - `header=Name:Value,Name2:Value2` → 加到 Dio 默认头，对所有场景生效
/// - `cookie=k=v,k2=v2`（也兼容浏览器复制出来的 `k=v; k2=v2`）→ 写进当前活跃
///   CookieJar。**必须显式指定 domain**：`dart:io` 的 `Cookie` 默认没有 domain，
///   cookie_jar 按 domain 归档，不指定就永远不会随请求发出
///   （App 自身存 Cookie 也用同样的前导点号写法，见 cookie_sync.dart）
Future<void> _applyProbeExtras({
  required String cookie,
  required String header,
}) async {
  if (header.isNotEmpty) {
    final headers = parseHeaderPairs(header);
    if (headers.isNotEmpty) {
      ApiService().dio.options.headers.addAll(headers);
      AppLogger.i('DIO', '探针注入请求头: ${headers.keys.join(', ')}');
    }
  }
  if (cookie.isEmpty) return;

  final pairs = parseCookiePairs(cookie);
  if (pairs.isEmpty) return;
  final jar = ApiService().activeCookieJar;
  if (jar == null) return;
  final uri = Uri.tryParse(SiteStore.instance.baseUrl);
  if (uri == null || uri.host.isEmpty) return;

  final list = <Cookie>[];
  for (final e in pairs.entries) {
    try {
      list.add(
        Cookie(e.key, e.value)
          ..domain = '.${uri.host}'
          ..path = '/',
      );
    } catch (err) {
      // 值含逗号等非法字符时 dart:io 的 Cookie 会抛（见 docs/07 #26），
      // 跳过该条而不是让整次探测失败
      AppLogger.w('DIO', '探针注入 cookie「${e.key}」被跳过: $err');
    }
  }
  if (list.isEmpty) return;
  await jar.saveFromResponse(uri, list);
  AppLogger.i('DIO', '探针注入临时 cookie: ${list.map((c) => c.name).join(', ')}');
}

/// `k=v,k2=v2` → {k: v}（兼容浏览器复制出来的 `k=v; k2=v2`）
Map<String, String> parseCookiePairs(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(RegExp(r'[;,]'))) {
    final s = part.trim();
    if (s.isEmpty) continue;
    final i = s.indexOf('=');
    if (i <= 0) continue;
    final name = s.substring(0, i).trim();
    if (name.isEmpty) continue;
    out[name] = s.substring(i + 1).trim();
  }
  return out;
}

/// `Name:Value,Name2:Value2` → {Name: Value}
Map<String, String> parseHeaderPairs(String raw) {
  final out = <String, String>{};
  for (final part in raw.split(',')) {
    final s = part.trim();
    if (s.isEmpty) continue;
    final i = s.indexOf(':');
    if (i <= 0) continue;
    final name = s.substring(0, i).trim();
    if (name.isEmpty) continue;
    out[name] = s.substring(i + 1).trim();
  }
  return out;
}

/// 挂一个"非论坛页"探测器
///
/// 探针没有 JS 引擎、也没有界面，过不了人机验证；但至少要**说清楚**：
/// 命中时标记 [probeInterstitialHit]，由入口层给出"复制 acw_sc__v2 重试"的提示，
/// 而不是让调用方对着一堆挑战页 HTML 猜。
void _installInterstitialProbe() {
  ApiService().dio.interceptors.add(
    InterceptorsWrapper(
      onResponse: (response, handler) {
        final body = response.data;
        if (body is String &&
            looksLikeInterstitialPage(
              body,
              response.headers.value('content-type'),
            )) {
          probeInterstitialHit = true;
          AppLogger.w(
            'DIO',
            '${response.requestOptions.path} 命中非论坛页（人机验证/防火墙拦截）',
          );
        }
        handler.next(response);
      },
    ),
  );
}

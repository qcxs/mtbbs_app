import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'acw_challenge.dart';

/// 本次探测是否命中"非论坛页"（人机验证 / 防火墙拦截页）。
///
/// 入口层据此追加 `reminder`，告诉调用方"怎么过验证"，而不是丢一堆挑战页 HTML。
bool probeInterstitialHit = false;

/// 本次探测里成功自解人机验证的次数（入口层输出，用于量化"会不会反复验证"）
int probeAcwSolved = 0;

/// 自解在请求上的标记位（值为已尝试次数），防止无解时无限重放
const String _kAcwSolveFlag = 'probeAcwSolveAttempts';

/// 单次请求最多自解重放几次 —— 正常一次即过；连续失败说明算法/接口已变
const int _kAcwMaxAttempts = 3;

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
/// 1. 初始化测试绑定（rootBundle 可用，配置文件可加载）
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
  probeAcwSolved = 0;
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test 会安装 _MockHttpOverrides（所有请求返回 400），
  // 必须用真实 HttpOverrides 覆盖才能发真实网络请求。
  HttpOverrides.global = WindowsCertOverride();

  await DefaultConfig.instance.load();
  if (baseUrl.isNotEmpty) {
    // 动态站点：替换为单站列表（测试站不在 sites.json 中）
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

/// 挂一个「非论坛页」探测器，并**尝试自解人机验证**。
///
/// 站点（MT 论坛）前置阿里云 ESA：未过挑战时返回 200 + 几 KB 挑战页（内含
/// `arg1`），浏览器靠页面 JS 算出 `acw_sc__v2` 写 Cookie 后重载。探针没有 JS
/// 引擎，但该算法是固定的，Dart 侧可原样复现（见 [acwScV2]）——于是：
///
/// 1. 命中挑战页 → 从正文取 `arg1`，算出 `acw_sc__v2` 写进当前罐
///    （同一响应的 `Set-Cookie` 已由 CookieManager 把 `acw_tc`/`cdn_sec_tc`
///    落罐，三者必须配对，且必须都是**本客户端**这一轮拿到的）；
/// 2. 原样重放该请求 → 正常拿到真页，对上层场景完全透明。
///
/// 自解失败（认不出 `arg1`、或连解 [_kAcwMaxAttempts] 次仍被拦）才置
/// [probeInterstitialHit]，由入口层给出人工处理提示。
void _installInterstitialProbe() {
  final dio = ApiService().dio;
  dio.interceptors.add(
    InterceptorsWrapper(
      onResponse: (response, handler) async {
        final body = response.data;
        if (body is! String ||
            !looksLikeInterstitialPage(
              body,
              response.headers.value('content-type'),
            )) {
          handler.next(response);
          return;
        }

        final options = response.requestOptions;
        final attempts = (options.extra[_kAcwSolveFlag] as int?) ?? 0;
        final arg1 = extractAcwArg1(body);
        if (arg1 == null || attempts >= _kAcwMaxAttempts) {
          probeInterstitialHit = true;
          AppLogger.w(
            'DIO',
            arg1 == null
                ? '${options.path} 命中非论坛页（非 acw 类挑战，无法自解）'
                : '${options.path} 自解 $attempts 次仍被拦，放弃',
          );
          handler.next(response);
          return;
        }

        final value = acwScV2(arg1);
        await _saveProbeCookies({'acw_sc__v2': value});
        probeAcwSolved++;
        options.extra[_kAcwSolveFlag] = attempts + 1;
        AppLogger.i(
          'DIO',
          '${options.path} 命中人机验证，已自算 acw_sc__v2 并重放（第 ${attempts + 1} 次）',
        );
        try {
          handler.resolve(await dio.fetch<void>(options));
        } catch (e) {
          AppLogger.w('DIO', '${options.path} 自解后重放失败: $e');
          handler.next(response);
        }
      },
    ),
  );
}

/// 把若干 cookie 写进当前活跃罐（与 [_applyProbeExtras] 同款：显式带前导点号
/// 的 domain，否则 `cookie_jar` 按 domain 归档时不会随请求发出）
Future<void> _saveProbeCookies(Map<String, String> pairs) async {
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
      AppLogger.w('DIO', '自解 cookie「${e.key}」写入被跳过: $err');
    }
  }
  if (list.isEmpty) return;
  await jar.saveFromResponse(uri, list);
}

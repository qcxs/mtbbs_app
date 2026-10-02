import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:mtbbs/core/utils/logger.dart';

// ==================== 核心 / 临时 Cookie ====================
//
// Cookie 分两类：
//   · **核心 cookie** —— 站点自己的会话 / 身份（Discuz 的 `{cookiepre}auth`、`sid`…）
//   · **临时 cookie** —— 边缘下发的防护 cookie（人机验证、CDN）与站点配置类
//
// 只有核心 cookie 会被持久化成"登录态"（`Account.cookieString`）。临时 cookie 有效期
// 极短（实测 `acw_tc` 只有 1 小时），一旦进了登录态，就会被每次启动 / 切账号 / 导入
// 导出反复"复活"；服务端收到过期的它只肯回挑战页，于是那条值永远刷不新，形成
// "每次冷启动都要验证"的死锁（见 docs/07 #73）。临时 cookie 留在 CookieJar 里，
// 由服务端响应按需刷新即可。

/// 从 cookie 名列表推断**站点核心 cookie 前缀**（Discuz 的 `cookiepre`）。
///
/// ① Discuz 用 `{cookiepre}auth` 判定是否登录，所以形如 `cQWy_2132_auth` 的名字去掉
///    末尾 `auth` 就是前缀——有它时以此为准；
/// ② 没有 `auth` 时退化为统计：取出现 ≥2 次的"下划线前缀"里最多的那个；
/// ③ 都推不出则返回空串，此时 [isCoreCookie] 不筛选（保持旧行为）。
String inferCookiePrefix(Iterable<String> names) {
  final list = names.where((n) => n.isNotEmpty).toList();
  const authSuffix = 'auth';
  for (final n in list) {
    if (n.length > authSuffix.length && n.endsWith(authSuffix)) {
      return n.substring(0, n.length - authSuffix.length);
    }
  }

  final counts = <String, int>{};
  for (final n in list) {
    final i = n.lastIndexOf('_');
    if (i <= 0) continue;
    final p = n.substring(0, i + 1);
    counts[p] = (counts[p] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return best.value >= 2 ? best.key : '';
}

/// 该 cookie 名是否属于核心 cookie（`prefix` 为空 = 未识别出前缀，一律视为核心）。
bool isCoreCookie(String name, String prefix) =>
    prefix.isEmpty || name.startsWith(prefix);

/// 过滤 cookie 串，只留核心 cookie（用于登录态持久化与注入 WebView）。
String coreCookiesOf(String cookieStr) {
  final pairs = cookieStr
      .split(';')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (pairs.isEmpty) return cookieStr;
  final prefix = inferCookiePrefix(pairs.map((p) => p.split('=').first.trim()));
  if (prefix.isEmpty) return cookieStr;
  return pairs
      .where((p) => isCoreCookie(p.split('=').first.trim(), prefix))
      .join('; ');
}

// ==================== Dio → WebView ====================

/// 将账号 Cookie 字符串同步到 WebView 原生 CookieManager
///
/// 每次打开内置浏览器或切换账号时调用，确保 WebView 携带与 API 请求相同的 Cookie。
/// cookieStr 格式：`name1=value1; name2=value2`
///
/// 注意：重复调用会覆盖同名 Cookie（domain/path/name 相同），不会产生重复条目。
Future<void> syncCookieStringToWebView(
  String? cookieStr,
  String baseUrl,
) async {
  final url = webview.WebUri(baseUrl);
  if (cookieStr == null || cookieStr.isEmpty) {
    // 空 Cookie = 游客态：只清本站点，不动其他站点
    await clearCookiesForHost(baseUrl);
    return;
  }

  final host = Uri.parse(baseUrl).host;
  // 只注入核心 cookie：临时 cookie（防护类）由站点自己下发，把手里那条旧值灌回去
  // 只会让挑战继续基于旧值进行（见 docs/07 #73）
  for (final pair in coreCookiesOf(cookieStr).split(';')) {
    final trimmed = pair.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq);
    final value = trimmed.substring(eq + 1);
    await webview.CookieManager.instance().setCookie(
      url: url,
      name: name,
      value: value,
      domain: host, // 不使用前导点号，某些平台不支持带前导点号的 domain
      path: '/',
    );
  }
}

/// 清除指定站点的 WebView Cookie，**不影响其他站点**。
///
/// WebView 的 CookieManager 是平台级单例：`deleteAllCookies()` 会清掉所有
/// 站点的 Cookie，多站点下会出现「登录/切游客 A 站，把 B 站的 WebView 登录态
/// 一起清掉」。这里改为只清当前站点。
///
/// **不要用 `getAllCookies()`**：Windows 端未实现——底层
/// `PlatformCookieManager.getAllCookies()` 直接 `throw UnimplementedError`。
/// 改用 `getCookies(url:)`（Windows / Android 都已实现），它天然只返回该 URL
/// 适用的 Cookie，等于已经按站点隔离，无需再按 domain 过滤（Android 上
/// domain 还可能因缺 `WebViewFeature.GET_COOKIE_INFO` 而为 null）。
///
/// 本函数**尽力而为、不抛异常**：它是 Cookie 注入前的清理步骤，失败只能记日志，
/// 绝不能连累后面的注入（否则浏览器会变成"未登录"）。
Future<void> clearCookiesForHost(String baseUrl) async {
  final host = Uri.tryParse(baseUrl)?.host ?? '';
  if (host.isEmpty) return;

  final manager = webview.CookieManager.instance();
  var scanned = 0;
  var deleted = 0;
  try {
    final cookies = await manager.getCookies(url: webview.WebUri(baseUrl));
    for (final cookie in cookies) {
      scanned++;
      // 一条 Cookie 要按多个 domain 写法各删一次，原因见 [_domainCandidates]
      for (final domain in _domainCandidates(cookie.domain, host)) {
        try {
          await manager.deleteCookie(
            url: webview.WebUri(baseUrl),
            name: cookie.name,
            path: cookie.path ?? '/',
            domain: domain,
          );
          deleted++;
        } catch (e) {
          AppLogger.d(
            'PAGE',
            'delete webview cookie "${cookie.name}" failed: $e',
          );
        }
      }
    }
  } catch (e) {
    AppLogger.w('PAGE', 'clear webview cookies for $host failed: $e');
  }
  AppLogger.d(
    'PAGE',
    'clear webview cookies for $host: 扫描 $scanned 条 / 删除调用 $deleted 次',
  );
}

/// 删除某条 Cookie 时应当尝试的 domain 候选值（按序执行）。
///
/// 平台 API 的坑（`flutter_inappwebview_android` 的 `MyCookieManager.java`）：
/// - `getCookies` **只在 WebView 支持 `GET_COOKIE_INFO` 时才回填 `domain`**，
///   否则一律为 null（`cookieMap.put("domain", null)`）；
/// - 原生 `deleteCookie` 在 `domain == null` 时**不写 `Domain=` 属性**，
///   于是只会命中 host-only 的那条。
///
/// 两者叠加的结果：Discuz 那种 `Domain=.bbs.binmt.cc` 的**域 Cookie 永远删不掉**，
/// 且删除接口照样返回成功（静默）。登录页因此一直带着上一个账号的登录态，
/// 用户无法登录其他账号。
///
/// 这里把三种存储形态都试一遍：
/// - `null`    → 不带 Domain，命中 host-only 形态
/// - `.{host}` → 命中最常见的 `Domain=.bbs.binmt.cc`
/// - 平台回填的 `cookie.domain`（可能是不带点号或父域写法）
///
/// 删除不存在的 Cookie 是无副作用的空操作，多试几次的代价可以接受。
List<String?> _domainCandidates(String? cookieDomain, String host) {
  final out = <String?>[null, '.$host'];
  final raw = (cookieDomain ?? '').trim();
  if (raw.isNotEmpty && !out.contains(raw)) out.add(raw);
  return out;
}

// ==================== WebView → Dio（反向同步） ====================

/// 把 WebView 的 Cookie 转换为可写入 [CookieJar] 的 `dart:io` Cookie。
///
/// - domain：统一成**前导点号**形式，与 App 自身存 Cookie 的写法一致
///   （见 AuthProvider._parseCookieString）。不一致会因 domain 键不同而
///   与已有条目**共存**，同一个 Cookie 名被发两次。
///   某些 Android 设备取不到 domain（依赖 `WebViewFeature.GET_COOKIE_INFO`），
///   此时回退到站点 host。
/// - 单条非法（`dart:io` 的 Cookie 按 RFC 6265 严格校验 name/value，值含 `,`
///   会抛 FormatException，见 docs/07 #26）时跳过该条，不让整次回流失败。
///
/// **一律不带 expires**（当作会话 cookie）。两个原因（见 docs/07 #73）：
/// - 各端 `expiresDate` 的单位/含义都不可信：Windows 给的是 CDP 的 `expires`
///   （**秒**）；Android 在支持 `GET_COOKIE_INFO` 时算
///   `currentTimeMillis() + maxAge`，而 `maxAge` 是**秒**，于是得到
///   "现在 + N 毫秒"这种瞬时过期值
/// - App 所有罐都是 `ignoreExpires: true`（本就不按过期丢 cookie），过期值的唯一
///   实际作用，是让 `cookie_jar` 在**落盘**时静默丢弃该条
///   （`PersistCookieJar._filterPathEntries` 无视 `ignoreExpires`）
///
/// 带上它只会制造"内存有、磁盘没有"的失效 —— 重启后又弹人机验证。
List<Cookie> toJarCookies(List<webview.Cookie> webCookies, Uri siteUri) {
  final result = <Cookie>[];
  for (final wc in webCookies) {
    if (wc.name.isEmpty) continue;
    try {
      final rawDomain = (wc.domain ?? '').trim();
      final domain = rawDomain.isEmpty
          ? '.${siteUri.host}'
          : (rawDomain.startsWith('.') ? rawDomain : '.$rawDomain');

      result.add(
        Cookie(wc.name, wc.value)
          ..domain = domain
          ..path = wc.path ?? '/'
          ..secure = wc.isSecure ?? (siteUri.scheme == 'https')
          ..httpOnly = wc.isHttpOnly ?? false,
      );
    } catch (e) {
      AppLogger.d('PAGE', 'skip invalid cookie "${wc.name}": $e');
    }
  }
  return result;
}

/// WebView → Dio：把 WebView 里属于 [baseUrl] 站点的 Cookie 写回 [jar]。
///
/// 场景：在内置浏览器/登录页里过了验证码、重新登录，或站点刷新了会话 Cookie——
/// 这些 Cookie 只落在 WebView 的 CookieManager 里。不回流的话，App 后续请求仍带
/// 旧 Cookie，表现为「浏览器里明明验证通过了，App 里还是失败」。
///
/// 用 `getCookies(url:)` 而不是 `getAllCookies()`：前者天然按 URL 过滤（只返回
/// 会发给该 URL 的 Cookie），不依赖 domain 字段（Android 上可能取不到）。
///
/// **返回本次「账号罐里原本没有」的 Cookie** —— 即验证 / 防火墙新下发的客户端级
/// cookie。调用方用它们补写到本站点的其它罐（见
/// `ApiService.mirrorToAllJarsForHost`）：这类 cookie 与账号无关，而罐按
/// `{host}/{账号}` 隔离，只写活跃罐的话，切账号 / 切游客 / 重启落到别的罐就要
/// 重新验证。
Future<List<Cookie>> syncWebViewCookiesToJar({
  required CookieJar jar,
  required String baseUrl,
}) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return const [];

  final webCookies = await webview.CookieManager.instance().getCookies(
    url: webview.WebUri(baseUrl),
  );
  if (webCookies.isEmpty) return const [];

  final cookies = toJarCookies(webCookies, uri);
  if (cookies.isEmpty) return const [];

  // 「账号罐里已有哪些名字」必须在写入前取快照：写入之后这些 cookie 也算已有，
  // 差集就永远为空了。
  Set<String>? existingNames;
  try {
    existingNames = (await jar.loadForRequest(uri)).map((c) => c.name).toSet();
  } catch (e) {
    AppLogger.w('PAGE', '读取账号罐 cookie 失败: $e');
  }

  // saveFromResponse 按 (domain, path, name) 覆盖同名条目，不会重复累积
  await jar.saveFromResponse(uri, cookies);

  // 快照失败时不补写：宁可不扩散，也不能把整份（含账号登录态）灌进别的罐
  final extras = existingNames == null
      ? const <Cookie>[]
      : cookies.where((c) => !existingNames!.contains(c.name)).toList();
  AppLogger.i(
    'PAGE',
    'WebView → Dio 回流 ${uri.host}: ${cookies.length} 条'
        '${extras.isEmpty ? '' : '（新增 ${extras.length}: ${extras.map((c) => c.name).join(', ')}）'}',
  );
  return extras;
}

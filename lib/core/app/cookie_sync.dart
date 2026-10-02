import 'dart:io' show Cookie;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
import 'package:mtbbs/core/utils/logger.dart';

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
  for (final pair in cookieStr.split(';')) {
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

/// CookieJar → WebView：把 App 当前 Cookie 同步进 WebView。
///
/// 供"全局人机验证弹窗"这类**非页面**场景使用——它拿不到 AuthProvider，
/// 但可以直接读当前活跃的 CookieJar。
///
/// 语义是"替换本站点 Cookie"：先清本站点（只清当前站点，见
/// [clearCookiesForHost]），再按 jar 注入，避免上一轮验证残留的旧 Cookie
/// 让 WebView 显示出错误的登录态。
///
/// 「清理」与「注入」两步互相独立：清理失败只记日志，绝不连累注入
/// （见 docs/07 #67 静默失败教训）。
Future<void> syncJarCookiesToWebView({
  required CookieJar jar,
  required String baseUrl,
}) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return;

  try {
    await clearCookiesForHost(baseUrl);
  } catch (e) {
    AppLogger.w('PAGE', 'clear webview cookies failed: $e');
  }

  List<Cookie> cookies;
  try {
    cookies = await jar.loadForRequest(uri);
  } catch (e) {
    AppLogger.w('PAGE', 'read jar cookies failed: $e');
    return;
  }
  final str = cookies
      .where((c) => c.name.isNotEmpty)
      .map((c) => '${c.name}=${c.value}')
      .join('; ');
  await syncCookieStringToWebView(str, baseUrl);
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
/// **过期时间只认"确实在将来"的值**，其余一律当作会话 cookie（不带 expires）。
/// 原因：`cookie_jar` 的 `PersistCookieJar._filterPathEntries` 在**落盘**时会
/// 无视 `ignoreExpires` 直接丢掉"已过期"条目 —— 而 App 的罐全部用
/// `ignoreExpires: true`（本就不按过期丢弃 cookie）。一旦 WebView 报出的
/// `expiresDate` 落在这个陷阱里（Windows 端曾见非毫秒量级的值），这条 cookie
/// 就会"内存里有、磁盘上没有"，重启后消失、人机验证反复出现。
List<Cookie> toJarCookies(List<webview.Cookie> webCookies, Uri siteUri) {
  final result = <Cookie>[];
  for (final wc in webCookies) {
    if (wc.name.isEmpty) continue;
    try {
      final rawDomain = (wc.domain ?? '').trim();
      final domain = rawDomain.isEmpty
          ? '.${siteUri.host}'
          : (rawDomain.startsWith('.') ? rawDomain : '.$rawDomain');

      final cookie = Cookie(wc.name, wc.value)
        ..domain = domain
        ..path = wc.path ?? '/'
        ..secure = wc.isSecure ?? (siteUri.scheme == 'https')
        ..httpOnly = wc.isHttpOnly ?? false;

      final expires = wc.expiresDate;
      if (expires != null && expires > 0) {
        final at = DateTime.fromMillisecondsSinceEpoch(expires);
        if (at.isAfter(DateTime.now())) {
          cookie.expires = at;
        } else {
          AppLogger.d('PAGE', '忽略异常过期时间 "${wc.name}": $expires（按会话 cookie 处理）');
        }
      }
      result.add(cookie);
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
/// 传了 [sharedJar] 时，额外把「账号罐里没有的」那部分写进站点共享罐（见
/// [SiteCookieJar]）——人机验证 / 防火墙下发的 cookie 是客户端级的，只有落进
/// 共享罐才能在切账号、切游客、重启后继续生效。
///
/// 返回实际写回的 Cookie 条数。
Future<int> syncWebViewCookiesToJar({
  required CookieJar jar,
  required String baseUrl,
  CookieJar? sharedJar,
}) async {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return 0;

  final webCookies = await webview.CookieManager.instance().getCookies(
    url: webview.WebUri(baseUrl),
  );
  if (webCookies.isEmpty) return 0;

  final cookies = toJarCookies(webCookies, uri);
  if (cookies.isEmpty) return 0;

  // 「账号罐里已有哪些名字」必须在写入前取快照：写入之后这些 cookie 也算已有，
  // 差集就永远为空了。
  Set<String>? existingNames;
  if (sharedJar != null) {
    try {
      existingNames = (await jar.loadForRequest(
        uri,
      )).map((c) => c.name).toSet();
    } catch (e) {
      AppLogger.w('PAGE', '读取账号罐 cookie 失败: $e');
    }
  }

  // saveFromResponse 按 (domain, path, name) 覆盖同名条目，不会重复累积
  await jar.saveFromResponse(uri, cookies);

  // 共享罐只收「账号罐里没有的」——即验证 / 防火墙新下发的客户端级 cookie。
  // 全量写入会把 syncJarCookiesToWebView 注入进 WebView 的账号登录态也灌进去，
  // 切到其他账号 / 游客时就会串号。
  if (sharedJar != null && existingNames != null) {
    final extras = cookies
        .where((c) => !existingNames!.contains(c.name))
        .toList();
    if (extras.isNotEmpty) {
      try {
        await sharedJar.saveFromResponse(uri, extras);
        AppLogger.i(
          'PAGE',
          '站点共享罐写入 ${extras.length} 条: ${extras.map((c) => c.name).join(', ')}',
        );
      } catch (e) {
        AppLogger.w('PAGE', '写入站点共享罐失败: $e');
      }
    }
  }

  AppLogger.i('PAGE', 'WebView → Dio 回流 ${uri.host}: ${cookies.length} 条');
  return cookies.length;
}

// ==================== 站点共享罐 ====================

/// 站点 Cookie 罐：把「账号罐」与「站点共享罐」合成一个视图交给 CookieManager。
///
/// **为什么需要**：人机验证 / 防火墙下发的 cookie 是**客户端级**的（按 IP / UA
/// 下发），与登录账号无关；而 App 的 Cookie 罐按 `{host}/{账号}` 隔离，游客态还会
/// 换成游客罐。验证通过后只往「当时活跃的那个罐」里写，重启 / 切账号 / 切站点后
/// 请求走的是另一只罐，验证 cookie 就丢了，于是反复被挑战。
///
/// - **读**：两罐合并；同名时**账号罐优先** —— 保证账号隔离不被共享罐破坏
/// - **写**：只写账号罐。服务端下发的会话 cookie（`auth` 等）属于当前账号，
///   绝不能落进共享罐，否则会串号；共享罐只由验证流程显式写入
///   （见 [syncWebViewCookiesToJar] 的 `sharedJar` 参数）
class SiteCookieJar implements CookieJar {
  SiteCookieJar({required this.accountJar, required this.sharedJar});

  /// 当前活跃的账号 / 游客罐
  final CookieJar accountJar;

  /// 站点级共享罐（客户端级 cookie）
  final CookieJar sharedJar;

  /// 本视图不参与过期过滤 —— 实际过滤由两个真实罐各自负责
  @override
  bool get ignoreExpires => false;

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async {
    final account = await accountJar.loadForRequest(uri);
    final names = account.map((c) => c.name).toSet();
    final shared = await sharedJar.loadForRequest(uri);
    return [...account, ...shared.where((c) => !names.contains(c.name))];
  }

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) =>
      accountJar.saveFromResponse(uri, cookies);

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) async {
    await accountJar.delete(uri, withDomainSharedCookie);
    await sharedJar.delete(uri, withDomainSharedCookie);
  }

  @override
  Future<void> deleteAll() async {
    await accountJar.deleteAll();
    await sharedJar.deleteAll();
  }
}

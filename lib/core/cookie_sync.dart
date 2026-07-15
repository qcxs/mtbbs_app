import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 将账号 Cookie 字符串同步到 WebView 原生 CookieManager
///
/// 每次打开内置浏览器或切换账号时调用，确保 WebView 携带与 API 请求相同的 Cookie。
/// cookieStr 格式：`name1=value1; name2=value2`
///
/// 注意：重复调用会覆盖同名 Cookie（domain/path/name 相同），不会产生重复条目。
Future<void> syncCookieStringToWebView(String? cookieStr, String baseUrl) async {
  final url = WebUri(baseUrl);
  if (cookieStr == null || cookieStr.isEmpty) {
    await CookieManager.instance().deleteAllCookies();
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
    await CookieManager.instance().setCookie(
      url: url,
      name: name,
      value: value,
      domain: host, // 不使用前导点号，某些平台不支持带前导点号的 domain
      path: '/',
    );
  }
}

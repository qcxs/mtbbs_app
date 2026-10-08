/// 从页面 HTML 中解析站点 CDN（Discuz 模板头部内联的 `STATICURL`）。
///
/// 返回值为 `scheme://host`（**不带** `static/` 路径），与 `SiteStore.cdnUrl`
/// 的语义一致——调用方按 `{cdn}/static/image/smiley/…` 拼接。
///
/// 返回 null 的情形（调用方回退 `baseUrl`）：
/// - 页面里没有 `STATICURL`（inajax 片段 / 非 Discuz 页 / 拦截页）
/// - 值不是绝对地址（站点未配置 `staticurl` 时 Discuz 用相对值 `static/`）
String? parseCdn(String body) {
  if (body.isEmpty) return null;
  final match = RegExp(
    r"""STATICURL\s*=\s*['"]([^'"]+)['"]""",
  ).firstMatch(body);
  final raw = match?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  // 协议相对 //host/path → https://host/path
  final absolute = raw.startsWith('//') ? 'https:$raw' : raw;
  final uri = Uri.tryParse(absolute);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
  // 保留显式端口（非常规端口部署的 CDN），默认端口不写出来
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

/// 解析探测页响应 → `{success, cdn}` 或 `{success:false, message}`
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }
  final cdn = parseCdn(body);
  if (cdn == null) return {'success': false, 'message': '页面中未找到 STATICURL'};
  return {'success': true, 'cdn': cdn};
}

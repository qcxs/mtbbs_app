import 'package:charset/charset.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// URL 统一工具
///
/// 使用 Dart 标准库 [Uri.resolve] 实现完整的 URL 解析，
/// 行为与浏览器一致。
///
/// 用法：
/// ```dart
/// normalizeUrl('forum.php?mod=image&aid=2')
/// // → http://discuz.qcxs.top/forum.php?mod=image&aid=2
///
/// normalizeUrl('//cdn.com/a.jpg')
/// // → https://cdn.com/a.jpg
///
/// normalizeUrl('./template/none.png')
/// // → http://discuz.qcxs.top/template/none.png
///
/// normalizeUrl('https://host.com/a.jpg')
/// // → https://host.com/a.jpg
/// ```
/// [base] 可覆盖默认站点 baseUrl（用于注入自定义 base，如 BBCode2Html）。
String normalizeUrl(String url, {String? base}) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  if (parsed.isAbsolute) return url;
  // 协议相对 //host/path → https://host/path
  if (url.startsWith('//')) return 'https:$url';
  // 相对路径 → 基于 baseUrl（缺省为站点 baseUrl）解析
  final baseUrl = base ?? SiteStore.instance.baseUrl;
  return Uri.parse(baseUrl).resolve(url).toString();
}

/// 补全正文里的「网页相对地址」（如 `forum.php?mod=viewthread&tid=1`）。
///
/// 解析层刻意保留作者原文不补域名；这里由**处理层**按页面所属站点补全。
/// 以下情况原样返回，避免误伤：
/// - 绝对地址（`http:` / `https:` / `mailto:` / `javascript:` 等任意 scheme）
/// - App 深链（`mtbbs://`）与 App 内路径（`/thread/123` 等，不含 `.php`）
/// - 空串
///
/// [base] 必须是**当前页面所属站点**的 baseUrl（跨站页面用临时会话的地址），
/// 不能取全局 `SiteStore`，否则跨站帖子会被补成当前站点。
String resolveContentUrl(String url, {required String base}) {
  final text = url.trim();
  if (text.isEmpty) return text;
  if (text.startsWith('mtbbs://')) return text;
  final parsed = Uri.tryParse(text);
  if (parsed != null && parsed.hasScheme) return text;
  // 以 / 开头的 Discuz 脚本路径按站点相对地址处理；其余 / 路径视为 App 内路径
  // （`//cdn/...` 是协议相对地址，不能按 App 路径处理）
  if (text.startsWith('/') && !text.startsWith('//')) {
    final path = text.split('?').first.split('#').first;
    if (!path.endsWith('.php')) return text;
  }
  final b = base.trim();
  if (b.isEmpty) return text;
  // 浏览器按文档 URL 解析相对地址；站点 base 补尾斜杠才能保留子目录
  final baseUri = Uri.parse(b.endsWith('/') ? b : '$b/');
  return baseUri.resolve(text).toString();
}

/// 宽松解析 URL 查询串。
///
/// [Uri.queryParameters] 会把**整串**参数值按 UTF-8 解码，GBK 站点（如 52pojie）
/// 常见 `highlight=%B5%E3%C6%C0` 这类非 UTF-8 字节，会直接抛
/// `FormatException: Unexpected extension byte`，导致整条链接被判为"不支持的页面"。
///
/// 这里逐个参数解码：UTF-8 失败时按 GBK 兜底，仍失败则保留原文，保证
/// `mod` / `tid` 等 ASCII 参数永远可读。
Map<String, String> parseQueryLenient(String query) {
  final result = <String, String>{};
  if (query.isEmpty) return result;
  for (final part in query.split('&')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    final key = decodeQueryComponentLenient(eq < 0 ? part : part.substring(0, eq));
    final value = eq < 0 ? '' : decodeQueryComponentLenient(part.substring(eq + 1));
    if (key.isNotEmpty) result[key] = value;
  }
  return result;
}

/// 解码单个查询参数；UTF-8 失败时按 GBK 兜底（GBK 站点如 52pojie）。
String decodeQueryComponentLenient(String raw) {
  try {
    return Uri.decodeQueryComponent(raw);
  } catch (_) {
    final text = raw.replaceAll('+', ' ');
    final bytes = <int>[];
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0x25 && i + 2 < text.length) {
        final value = int.tryParse(text.substring(i + 1, i + 3), radix: 16);
        if (value != null) {
          bytes.add(value);
          i += 2;
          continue;
        }
      }
      // 非 ASCII 原字符（如已被上层解码的中文）无法安全混入 GBK 字节流
      if (c > 0x7E) return raw;
      bytes.add(c);
    }
    try {
      return gbk.decode(bytes);
    } catch (_) {
      return raw;
    }
  }
}

/// 按站点字符集对查询参数值做百分号编码。
///
/// [Uri.encodeQueryComponent] 固定按 UTF-8 编码；而 Discuz 会按站点字符集
/// 解码 GET 参数。GBK 站点（如 52pojie）收到 UTF-8 字节的中文关键词时，
/// 会把「公式」读成「鍏紡」，搜索必然无结果（见 `docs/18`）。
///
/// [charset] 为 `gbk` / `gb2312` 时按 GBK 编码（GBK 兼容 GB2312）；其余
/// （空 / `utf-8` / 未知值）保持 UTF-8。空格统一编码为 `%20`。
String encodeQueryComponentForSite(String value, {String? charset}) {
  final cs = (charset ?? '').trim().toLowerCase();
  if (cs != 'gbk' && cs != 'gb2312') {
    return Uri.encodeQueryComponent(value);
  }
  final buf = StringBuffer();
  for (final b in gbk.encode(value)) {
    // ASCII 可见字符保留原样，其余（含中文 / 空格 / 保留字符）转 %XX
    final unreserved =
        (b >= 0x30 && b <= 0x39) || // 0-9
        (b >= 0x41 && b <= 0x5A) || // A-Z
        (b >= 0x61 && b <= 0x7A) || // a-z
        b == 0x2D ||
        b == 0x2E ||
        b == 0x5F ||
        b == 0x7E; // - . _ ~
    if (unreserved) {
      buf.writeCharCode(b);
    } else {
      buf.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buf.toString();
}

/// 按站点字符集编码 `application/x-www-form-urlencoded` 请求体。
///
/// Dio 对 `Map` 形式的 data 固定按 UTF-8 编码，而 Discuz 按**站点字符集**
/// 解码 POST 字段：GBK 站点（52pojie）提交中文会变成乱码（实测评论正文）。
/// 手工拼成 query 串后以 String 发送，Dio 不再二次编码。
String encodeFormBodyForSite(
  Map<String, dynamic> fields, {
  String? charset,
}) {
  return fields.entries
      .map(
        (e) =>
            '${encodeQueryComponentForSite(e.key, charset: charset)}='
            '${encodeQueryComponentForSite(e.value?.toString() ?? '', charset: charset)}',
      )
      .join('&');
}

/// 图片"占位图"特征（文件名片段）：URL 含其中任一即视为没有真实图片。
///
/// 用于过滤懒加载占位图（克米 `comiis_loadimages`、`none.png` 等）——
/// 克米列表解析与 HTML→BBCode 共用这一份，避免两处清单漂移（docs/07 #79）。
const imagePlaceholderMarkers = [
  'none.png',
  'nophoto.gif',
  'nophoto.png',
  'loading.gif',
  'loading.png',
];

/// [url] 是否为占位图（按小写文件名片段匹配）。
bool isPlaceholderImageUrl(String url) {
  final lower = url.toLowerCase();
  return imagePlaceholderMarkers.any(lower.contains);
}

/// 把 CDN 地址还原成**等价的原站地址**；不是该 CDN 下的地址时返回 null。
///
/// CDN 与原站共用同一套路径（表情 `/static/image/smiley/…`、头像模板里的
/// `{cdn}` 等），因此前缀替换即可得到等价地址。用于 CDN 不可用时的回退重试。
///
/// 返回 null 的两种情况：
/// - 站点没配 CDN（[cdn] 为空或与 [base] 相同）—— 本来就是直连原站，无处可退
/// - 地址不属于该 CDN（如帖子附件在 OSS 域名上）—— 没有等价的原站地址
String? originUrlForCdn(
  String url, {
  required String cdn,
  required String base,
}) {
  final c = cdn.trim();
  final b = base.trim();
  if (c.isEmpty || b.isEmpty) return null;
  // 尾斜杠只影响拼接、不影响语义，统一去掉再做前缀比较
  final cNorm = c.endsWith('/') ? c.substring(0, c.length - 1) : c;
  final bNorm = b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  if (cNorm == bNorm || !url.startsWith(cNorm)) return null;
  final rest = url.substring(cNorm.length);
  // 前缀必须停在主机名边界上：`https://cdn.com` 不该匹配 `https://cdn.com.cn/…`
  if (rest.isNotEmpty && rest[0] != '/' && rest[0] != '?') return null;
  // cdn 带尾斜杠时（历史配置如 'https://static.52pojie.cn/'）会拼出 '//'，
  // 这里收敛成单斜杠，避免回退地址出现双斜杠路径
  return bNorm + (rest.startsWith('//') ? rest.substring(1) : rest);
}

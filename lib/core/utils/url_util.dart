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

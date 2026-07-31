/// Discuz 头像 URL 模板解析。
///
/// 统一处理两种头像获取方案：
/// - API 方案（默认模板）：`{baseurl}/uc_server/avatar.php?uid={uid}&size={size}`
/// - 路径方案：直接拼接站点头像静态路径，例如
///   `https://avatar.xxx.com/data/avatar/{dir}/{tail}_avatar_{size}.jpg`
///
/// 占位符说明：
/// - `{baseurl}` 站点 baseUrl
/// - `{cdn}`     站点 CDN，为空时回退 baseUrl
/// - `{uid}`     用户 uid（原样，未补零）
/// - `{size}`    small / middle / big
/// - `{d1}` `{d2}` `{d3}`  uid 9 位补零后的 3-2-2 拆分目录段
/// - `{tail}`    uid 9 位补零后的最后两位（Discuz 头像文件名前缀）
/// - `{dir}`     `{d1}/{d2}/{d3}` 的便捷形式
///
/// 模板中未识别的字面量原样保留，可表达任意 Discuz fork 的目录规则。
library;

/// 默认头像模板（API 方案），与历史实现等价
const String kDefaultAvatarTemplate =
    '{baseurl}/uc_server/avatar.php?uid={uid}&size={size}';

/// 解析头像模板，生成指定用户/尺寸的头像 URL。
///
/// [template] 为空时回退到 [kDefaultAvatarTemplate]。
/// Discuz 路径算法：`sprintf("%09d", uid)` 后按 3-2-2 拆目录，
/// 最后两位作为文件名前缀，例如 uid=123 → `000/00/01/23_avatar_middle.jpg`。
String resolveAvatarUrl({
  required String template,
  required String baseUrl,
  String cdn = '',
  required String uid,
  required String size,
}) {
  final t = template.trim().isEmpty ? kDefaultAvatarTemplate : template.trim();
  final uidInt = int.tryParse(uid) ?? 0;
  final padded = uidInt.toString().padLeft(9, '0');
  final d1 = padded.substring(0, 3);
  final d2 = padded.substring(3, 5);
  final d3 = padded.substring(5, 7);
  final tail = padded.substring(7);
  final cdnUrl = cdn.trim().isEmpty ? baseUrl : cdn.trim();

  final map = <String, String>{
    '{baseurl}': baseUrl,
    '{cdn}': cdnUrl,
    '{uid}': uid,
    '{size}': size,
    '{d1}': d1,
    '{d2}': d2,
    '{d3}': d3,
    '{tail}': tail,
    '{dir}': '$d1/$d2/$d3',
  };
  var result = t;
  map.forEach((k, v) => result = result.replaceAll(k, v));
  return result;
}

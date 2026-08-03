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

/// 头像加载尺寸策略。
///
/// Discuz 头像 URL 有 small / middle / big 三种尺寸，实际图片差异不大。
/// 固定某一尺寸可让同一用户在所有场景共用同一 URL，显著提高头像缓存命中率，
/// 避免因不同场景请求不同尺寸而重复下载、造成加载慢的错觉。
enum AvatarSizeMode {
  /// 自适应：根据实际 UI 大小在 small / middle / big 间选择
  auto('auto', '自适应'),

  /// 固定加载小尺寸
  small('small', 'small'),

  /// 固定加载中尺寸（默认，缓存命中率与画质折中）
  middle('middle', 'middle'),

  /// 固定加载大尺寸
  big('big', 'big');

  const AvatarSizeMode(this.value, this.label);

  /// 持久化值；对固定策略而言即 Discuz 尺寸名
  final String value;

  /// 设置页展示名
  final String label;

  /// 按持久化值反查，未知值回退 [AvatarSizeMode.middle]
  static AvatarSizeMode fromValue(String? v) => AvatarSizeMode.values
      .firstWhere((m) => m.value == v, orElse: () => AvatarSizeMode.middle);
}

/// 根据尺寸策略与 UI 半径解析实际请求的 Discuz 头像尺寸名。
///
/// [AvatarSizeMode.auto] 时按 [radius] 自适应：radius ≥ 28 → big，
/// 18~27 → middle，否则 small；固定策略直接返回对应尺寸名。
String resolveAvatarSize(AvatarSizeMode mode, double radius) {
  if (mode != AvatarSizeMode.auto) return mode.value;
  if (radius >= 28) return 'big';
  if (radius >= 18) return 'middle';
  return 'small';
}

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

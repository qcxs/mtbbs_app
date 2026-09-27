/// MCP 出站脱敏 —— 所有返回给 AI 客户端的数据都必须过这里。
///
/// 设计原则：**架构层先挡住，本层只做兜底**。首版数据源复用现有 API
/// （携带登录态），因此本层负责剥离"即使登录也不该外流"的字段：
/// 凭据、formhash、IP、联系方式，以及编辑器表单快照。
class McpSanitizer {
  McpSanitizer._();

  /// 一律剥离的键（按完整键名做大小写不敏感匹配）。
  ///
  /// 用**完整键名**而非包含匹配：`ipLocation`（公开的"来自"）不会被
  /// `ip` 误伤，`author` 也不会被 `auth` 误伤（见 docs/07 #20 的教训）。
  static const Set<String> blockedKeys = {
    // 凭据 / 鉴权
    'cookie',
    'cookies',
    'cookiestring',
    'formhash',
    'password',
    'passwd',
    'token',
    'accesstoken',
    'refreshtoken',
    'secret',
    'authorization',
    'sessionid',
    'sid',
    // 联系方式与实名
    'email',
    'emailverified',
    'realname',
    'qq',
    'phone',
    'mobile',
    'telephone',
    // IP（`ipLocation` 是公开的地区文案，键名不同，不受影响）
    'ip',
    'registerip',
    'lastvisitip',
    'lastip',
    'lastactivityip',
    // 编辑器表单快照（含 formhash / uploadHash）
    'pagedata',
    'uploadhash',
    'emojimap',
    // 需要 formhash 才能生效的写操作入口，对只读场景无用
    'followurl',
    'recommendurl',
    'favoriteurl',
    'kickurl',
  };

  /// 链接里残留的 formhash 参数（`[url]` 之外的旁路，兜底再擦一遍）
  static final RegExp _formhashInUrl = RegExp(
    r'([?&]formhash=)[^&\s]*',
    caseSensitive: false,
  );

  static bool isBlockedKey(String key) =>
      blockedKeys.contains(key.toLowerCase());

  /// 递归脱敏：剥离黑名单键 + 擦除文本里残留的 formhash。
  static dynamic sanitize(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (isBlockedKey(key)) continue;
        out[key] = sanitize(entry.value);
      }
      return out;
    }
    if (value is List) return value.map(sanitize).toList();
    if (value is String) return scrubText(value);
    return value;
  }

  /// 擦除字符串中的 `formhash=` 参数值
  static String scrubText(String text) {
    if (!text.contains('formhash=')) return text;
    return text.replaceAllMapped(_formhashInUrl, (m) => '${m[1]}[已隐去]');
  }

  /// 截断过长文本，避免单次响应把上下文挤爆
  static String clampText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n…（已截断，原文共 ${text.length} 字）';
  }
}

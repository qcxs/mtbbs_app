import 'dart:convert';

/// 帖子缓存的纯策略函数（无 IO、无状态，便于单测）。
///
/// 与 `ThreadCacheService`（存储编排）分离：这里是"算不算新帖 / 缓存键身份 /
/// 内容版本"等判定规则，改动频率低、可独立验证。

/// 账号标识：登录用户 `uid:<uid>`，游客 `guest`
///
/// 幂等：传入已是 `uid:123` 的值不会二次加前缀。
String viewerTag(String uid) {
  final value = uid.trim();
  if (value.isEmpty || value == '0' || value == 'guest') return 'guest';
  if (value.startsWith('uid:')) return value;
  return 'uid:$value';
}

/// 判断帖子时间文本是否代表「新帖」。
///
/// 采用**排除法**（宁可多缓存，也不因模板前缀/措辞差异漏掉自动缓存）：
/// - 空串 → 非新帖
/// - 含相对时间词（`刚刚/刚才/昨天/前天`，或 `秒前/分钟前/小时前/天前`）→ 新帖；
///   词语可出现在任意位置，兼容「发表在 半小时前」这类带前缀的输出
/// - 含完整年月日（`2026-10-11`、`2026/10/11`、`2026年10月11日`）→ 非新帖
/// - 含时分（`12:34` / `12:34:56`）且无相对时间词 → 非新帖
/// - 其余一律视为新帖
bool isNewThreadTime(String postTime) {
  final text = postTime.trim();
  if (text.isEmpty) return false;
  if (RegExp(r'刚刚|刚才|昨天|前天|秒前|分钟前|小时前|天前').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'\d{4}\s*[-/年]\s*\d{1,2}\s*[-/月]\s*\d{1,2}').hasMatch(text)) {
    return false;
  }
  if (RegExp(r'\d{1,2}:\d{2}').hasMatch(text)) return false;
  return true;
}

/// 内容哈希：FNV-1a 64 位（16 位小写十六进制）
///
/// 只包含标题 + 楼主正文；`postTime` 等易变字段不参与，避免相对时间变化
/// 每次都产生新版本。不折叠内部空白，避免 `[code]` 缩进差异被误判。
String threadContentHash(String title, String bbcode) {
  final input = utf8.encode(
    '${_normalizeForHash(title)}\u0000${_normalizeForHash(bbcode)}',
  );
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final byte in input) {
    hash ^= byte;
    hash *= prime; // Dart VM int 为 64 位，溢出自动截断
  }
  final hi = (hash >> 32) & 0xFFFFFFFF;
  final lo = hash & 0xFFFFFFFF;
  return hi.toRadixString(16).padLeft(8, '0') +
      lo.toRadixString(16).padLeft(8, '0');
}

String _normalizeForHash(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

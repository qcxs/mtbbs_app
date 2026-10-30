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

/// 「新帖」时间窗口：完整时间距离现在不超过该时长即视为新帖。
///
/// 部分站点（如 52pojie）不显示相对时间，所有帖子都是 `2026-10-30 13:04`
/// 这样的完整时间，因此必须按时间差判断，不能一律当旧帖。
const Duration kNewThreadWindow = Duration(days: 7);

/// 相对时间词：出现在文本任意位置都说明帖子很新（含「昨天 12:34」这类混合格式）
final RegExp _relativeTimeRe = RegExp(
  r'刚刚|刚才|今天|昨天|前天|秒前|分钟前|小时前|天前',
);

/// `2026-10-30 13:04(:56)` / `2026/10/30` / `2026年10月30日`
final RegExp _fullDateTimeRe = RegExp(
  r'(\d{4})\s*[-/年]\s*(\d{1,2})\s*[-/月]\s*(\d{1,2})\s*日?'
  r'\s*(?:(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
);

/// 无年份的 `10-30 13:04` / `10月30日`（按当前年份补全）
final RegExp _monthDayTimeRe = RegExp(
  r'(?<!\d)(\d{1,2})\s*[-/月]\s*(\d{1,2})\s*日?'
  r'\s*(?:(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
);

/// 判断帖子时间文本是否代表「新帖」。
///
/// 采用**排除法**（宁可多缓存，也不因模板前缀/措辞差异漏掉自动缓存）：
/// - 空串 → 非新帖
/// - 含相对时间词（`刚刚/刚才/今天/昨天/前天`，或 `秒前/分钟前/小时前/天前`）→ 新帖；
///   词语可出现在任意位置，兼容「发表在 半小时前」这类带前缀的输出
/// - 含完整时间（`2026-10-30 13:04`、`2026/10/30`、`2026年10月30日`、`10-30 13:04`）
///   → 与 [now] 比较，距现在不超过 [kNewThreadWindow] 才算新帖
/// - 其余一律视为新帖
bool isNewThreadTime(String postTime, {DateTime? now}) {
  final text = postTime.trim();
  if (text.isEmpty) return false;
  if (_relativeTimeRe.hasMatch(text)) return true;

  final current = now ?? DateTime.now();
  final parsed = parsePostTime(text, now: current);
  if (parsed != null) {
    final age = current.difference(parsed);
    // 未来时间（站点时钟/时区偏差）同样按新帖，避免误判成旧帖
    return age.isNegative || age <= kNewThreadWindow;
  }

  if (RegExp(r'\d{4}\s*[-/年]\s*\d{1,2}\s*[-/月]\s*\d{1,2}').hasMatch(text)) {
    return false;
  }
  if (RegExp(r'\d{1,2}:\d{2}').hasMatch(text)) return false;
  return true;
}

/// 解析帖子时间文本为本地时间；无法识别或日期非法时返回 null。
///
/// 支持：`2026-10-30 13:04`、`2026/10/30 13:04:56`、`2026年10月30日 13:04`、
/// `10-30 13:04`、`10月30日`；只有日期时按 00:00 计。
DateTime? parsePostTime(String text, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final full = _fullDateTimeRe.firstMatch(text);
  if (full != null) {
    return _buildDate(
      int.parse(full.group(1)!),
      int.parse(full.group(2)!),
      int.parse(full.group(3)!),
      full.group(4),
      full.group(5),
      full.group(6),
    );
  }
  final short = _monthDayTimeRe.firstMatch(text);
  if (short != null) {
    return _buildDate(
      current.year,
      int.parse(short.group(1)!),
      int.parse(short.group(2)!),
      short.group(3),
      short.group(4),
      short.group(5),
    );
  }
  return null;
}

DateTime? _buildDate(
  int year,
  int month,
  int day,
  String? hour,
  String? minute,
  String? second,
) {
  final h = hour == null ? 0 : int.parse(hour);
  final m = minute == null ? 0 : int.parse(minute);
  final s = second == null ? 0 : int.parse(second);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (h > 23 || m > 59 || s > 59) return null;
  final date = DateTime(year, month, day, h, m, s);
  // DateTime 会把 2 月 30 日滚到 3 月，归一化后不一致即视为非法
  if (date.month != month || date.day != day) return null;
  return date;
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

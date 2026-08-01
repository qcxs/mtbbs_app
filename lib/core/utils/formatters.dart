/// 通用格式化与解析工具。
library;

String _pad2(int n) => n.toString().padLeft(2, '0');

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前 / MM-dd HH:mm
String formatRelativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${_pad2(dt.month)}-${_pad2(dt.day)} ${_pad2(dt.hour)}:${_pad2(dt.minute)}';
}

/// 简版相对时间：N 分钟前 / N 小时前 / N 天前 / M/d
String formatRelativeTimeShort(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return '${dt.month}/${dt.day}';
}

/// 智能绝对时间：今天 HH:mm / 昨天 HH:mm / M/d HH:mm
String formatSmartTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(dt.year, dt.month, dt.day);
  final hm = '${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  if (date == today) return hm;
  if (date == today.subtract(const Duration(days: 1))) return '昨天 $hm';
  return '${dt.month}/${dt.day} $hm';
}

/// 完整绝对时间：M月d日 HH:mm
String formatFullTime(DateTime dt) {
  return '${dt.month}月${dt.day}日 ${_pad2(dt.hour)}:${_pad2(dt.minute)}';
}

/// 标准日期时间：yyyy-MM-dd HH:mm:ss
String formatDateTimeFull(DateTime dt) {
  return '${dt.year}-${_pad2(dt.month)}-${_pad2(dt.day)} '
      '${_pad2(dt.hour)}:${_pad2(dt.minute)}:${_pad2(dt.second)}';
}

/// 文件大小格式化：B / KB / MB
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 安全解析时间，失败回退当前时间
DateTime parseDateTimeOrNow(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}

import 'package:flutter/foundation.dart';

/// 应用日志级别
///
/// 编译期通过 `kReleaseMode` 控制：release 模式完全跳过，零开销。
/// 调试模式可用 `LogLevel.level` 运行时动态开关分类。
enum LogLevel { info, debug, warning, error }

/// 轻量应用日志
///
/// 用法：
/// ```dart
/// AppLogger.i('PARSE', 'guide: success, 50 threads');
/// AppLogger.list('PARSE', items, 3, labelFn: (e) => e.title);
/// ```
///
/// release 模式自动静默（依赖 [debugPrint] + [kReleaseMode] 双保险）。
/// [enabled] 由 ApiService.setLogging() 控制，对应设置页"API 日志输出"开关。
class AppLogger {
  /// 日志总开关。关闭后所有日志不输出。
  /// 由 ApiService.setLogging(enabled:) 控制。
  static bool enabled = true;

  /// 运行时日志级别（enabled 为 true 时有效）
  /// 默认 [LogLevel.info]：展示 DIO/PARSE/PAGE 常规日志
  /// 设为 [LogLevel.debug] 可输出更详细的调试信息
  static LogLevel level = LogLevel.info;

  /// 日志标签长度对齐（右对齐填充，保证控制台对齐）
  static const int _tagWidth = 12;

  /// 是否允许输出当前级别
  static bool _allow(LogLevel lvl) =>
      !kReleaseMode && enabled && lvl.index >= level.index;

  static void _log(LogLevel lvl, String tag, String msg) {
    if (!_allow(lvl)) return;
    final tagPadded = tag.padLeft(_tagWidth);
    debugPrint('[$tagPadded] $msg');
  }

  // ==================== 便捷方法 ====================

  static void i(String tag, String msg) => _log(LogLevel.info, tag, msg);
  static void d(String tag, String msg) => _log(LogLevel.debug, tag, msg);
  static void w(String tag, String msg) => _log(LogLevel.warning, tag, msg);
  static void e(String tag, String msg) => _log(LogLevel.error, tag, msg);

  // ==================== 工具方法 ====================

  /// 截断输出长列表，避免刷屏。
  ///
  /// [items]      完整列表
  /// [maxShow]    最多显示的条数（超出的计为 "N more"）
  /// [labelFn]    从元素提取显示文本
  /// [summary]    列表摘要（如 "50 threads"）
  ///
  /// 输出格式：
  /// ```
  ///   50 threads:
  ///     + title1
  ///     + title2
  ///     + title3
  ///     ... (47 more)
  /// ```
  static void list<T>(
    String tag,
    List<T> items,
    int maxShow, {
    required String Function(T) labelFn,
    String summary = '',
  }) {
    if (!_allow(LogLevel.info)) return;
    final prefix = summary.isNotEmpty ? '$summary:\n' : '';
    final lines = items.take(maxShow).map((e) => '    + ${labelFn(e)}');
    final rest = items.length > maxShow
        ? '    ... (${items.length - maxShow} more)'
        : '';
    final msg = [prefix, ...lines, if (rest.isNotEmpty) rest].join('\n');
    debugPrint('[$tag] $msg');
  }

  /// 格式化字节大小（如 "177KB"）
  static String bytes(int b) {
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)}KB';
    return '${b}B';
  }
}

import 'dart:convert';
import 'package:dio/dio.dart';
import '../core/logger.dart';

/// 从 Dio Response 中安全解码响应体
String safeDecode(Response<String> resp) => resp.data ?? '';

/// 解析响应并自动输出解析日志
///
/// 自动提取关键摘要 + 列表数据前 3 项。debug 模式输出，release 零开销。
/// 所有 export 层统一使用此函数替代手写的 parseResponse 调用。
///
/// [parseFn] 接收 (body, statusCode)，返回解析结果 Map。
/// 如果 parse 函数有其他参数，用闭包包装：
/// ```dart
/// parseWithLog(resp, (b, s) => parse.parseResponse(b, s, extra: val));
/// ```
T parseWithLog<T>(
  Response<String> resp,
  T Function(String body, int statusCode) parseFn,
) {
  final body = safeDecode(resp);
  final result = parseFn(body, resp.statusCode ?? 0);
  // 仅在 result 是 Map<String, dynamic> 时自动输出日志
  if (result is Map<String, dynamic>) {
    _logParseResult(result as Map<String, dynamic>, resp.requestOptions.path);
  }
  return result;
}

/// 输出解析结果日志
void _logParseResult(Map<String, dynamic> result, String path) {
  if (result['success'] != true) {
    AppLogger.w('PARSE', '$path failed: ${result['message'] ?? '?'}');
    return;
  }

  // 摘要：完整 JSON，列表/Map 缩略为 "[N items]" / "{N entries}"
  final summary = <String, dynamic>{};
  for (final entry in result.entries) {
    final v = entry.value;
    if (v is List) {
      summary[entry.key] = '[${v.length} items]';
    } else if (v is Map) {
      summary[entry.key] = '{${v.length} entries}';
    } else {
      summary[entry.key] = v;
    }
  }
  AppLogger.i('PARSE', '$path ← ${jsonEncode(summary)}');

  // 详情：首个列表/Map 展示实际内容
  for (final k in result.keys) {
    final v = result[k];
    if (v is List && v.isNotEmpty) {
      final items = v.take(3).map((e) => '  ${jsonEncode(e)}').join('\n');
      final rest = v.length > 3 ? '\n  ... (${v.length - 3} more)' : '';
      AppLogger.d('PARSE', '$k:\n$items$rest');
      return;
    }
    if (v is Map && v.isNotEmpty) {
      final lines = v.entries
          .take(5)
          .map((e) {
            final val = e.value is String
                ? '"${e.value}"'
                : jsonEncode(e.value);
            return '  "${e.key}": $val';
          })
          .join('\n');
      AppLogger.d('PARSE', '$k:\n$lines');
      return;
    }
  }
}

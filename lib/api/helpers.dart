import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/app/event_bus.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 从 Dio Response 中安全解码响应体
String safeDecode(Response<String> resp) => resp.data ?? '';

/// parse.dart 统一前置：HTTP 状态码校验 + 解析 DOM + Discuz 错误页/登录页检测。
///
/// 失败时 [error] 非空，应直接作为 `parseResponse` 的返回值；
/// 通过时 [doc] 非空，可继续解析。
///
/// 用法：
/// ```dart
/// final pre = prepareDoc(body, statusCode);
/// if (pre.error != null) return pre.error!;
/// final doc = pre.doc!;
/// ```
({dom.Document? doc, Map<String, dynamic>? error}) prepareDoc(
  String body,
  int statusCode,
) {
  if (statusCode != 200) {
    return (
      doc: null,
      error: {'success': false, 'message': 'HTTP $statusCode'},
    );
  }
  final doc = html_parser.parse(body);
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return (
      doc: null,
      error: {
        'success': false,
        'message': pageError.message ?? '页面错误',
        'loginRequired': pageError.loginRequired,
      },
    );
  }
  return (doc: doc, error: null);
}

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
    final map = result as Map<String, dynamic>;
    // 服务器明确返回“需要登录”的页面（登录过期/未登录被拦截）→ 广播登录过期事件
    // 幂等性由订阅端保证（AuthProvider.markSessionExpired + UI 节流）
    if (map['loginRequired'] == true) {
      EventBus.fire(LoginExpiredEvent());
    }
    _logParseResult(map, resp.requestOptions.path);
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
    if (entry.key == '_health') continue; // 健康自检单独输出，见下
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

  // 健康自检：结构解析成功但关键字段为空 → 明确告警
  // （区别于"页面本身没有数据"：这里表示"页面结构可能变了"，见 docs/07 静默失败）
  final health = result['_health'];
  if (health is Map) {
    final missing = health['missing'];
    if (missing is List && missing.isNotEmpty) {
      AppLogger.w(
        'PARSE',
        '$path 解析健康告警（${health['parser'] ?? '?'}）：${missing.join('；')}',
      );
    }
  }

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

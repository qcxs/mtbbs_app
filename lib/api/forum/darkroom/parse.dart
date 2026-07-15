import 'dart:convert';
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/logger.dart';

/// 小黑屋 JSON 响应解析
///
/// 响应格式：
/// ```json
/// {"message":"1|27232","data":{153922:{...}}}
/// {"message":"0|1","data":[]}
/// ```
/// message: "hasMore|nextCid" — hasMore 1 有下一页，0 无
/// data 的 key 是裸数字（如 153922），不符合 JSON 规范，
/// 解析前先通过 _fixNumericKeys 给数字 key 补引号。
/// dateline 有两种格式：
/// 1. HTML span: "<span title=\"2026-7-9 21:37\">3&nbsp;天前</span>"
/// 2. 纯文本: "2026-6-30 20:24"

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final Map<String, dynamic> json;
  try {
    // Discuz 返回的 JSON 中 data 对象的键是裸数字 {153922:{...}}，
    // 解析前先给数字 key 补上引号
    json = jsonDecode(_fixNumericKeys(body)) as Map<String, dynamic>;
  } catch (e) {
    AppLogger.e('PARSE', 'darkroom JSON decode failed: $e');
    return {'success': false, 'message': 'JSON 解析失败'};
  }

  // 解析 message 字段
  final msg = (json['message'] as String?)?.split('|') ?? ['0', '1'];
  final hasMore = msg.isNotEmpty && msg[0] == '1';
  final nextCid = msg.length > 1 ? msg[1] : '';

  // 解析 data
  final rawData = json['data'];
  final List<Map<String, dynamic>> items = [];

  if (rawData is Map) {
    for (final entry in rawData.entries) {
      if (entry.value is Map) {
        final item = Map<String, dynamic>.from(entry.value as Map);
        // 处理 dateline：HTML span → textContent
        final rawDateline = item['dateline'] as String? ?? '';
        item['dateline'] = _extractDatelineText(rawDateline);
        items.add(item);
      }
    }
  }

  AppLogger.i('PARSE', 'darkroom: ${items.length} items, hasMore=$hasMore');
  if (items.isNotEmpty) {
    AppLogger.list(
      'PARSE',
      items,
      3,
      labelFn: (item) => jsonEncode(item),
      summary: '${items.length} items',
    );
  }

  return {
    'success': true,
    'items': items,
    'count': items.length,
    'hasMore': hasMore,
    'nextCid': nextCid,
  };
}

/// 提取 dateline 的纯文本内容
///
/// 处理两种格式：
/// - "<span title=\"2026-7-9 21:37\">3&nbsp;天前</span>" → "3 天前"
/// - "2026-6-30 20:24" → "2026-6-30 20:24"
String _extractDatelineText(String raw) {
  if (!raw.contains('<') && !raw.contains('&')) return raw;
  try {
    final doc = htmlParser.parseFragment(raw);
    var text = doc.text?.trim() ?? raw;
    // htmlParser 对 &nbsp; 可能保留为 \u00A0，统一转成常规空格
    text = text.replaceAll('\u00A0', ' ');
    return text;
  } catch (_) {
    return raw;
  }
}

/// Discuz 小黑屋 API 返回的 JSON 中 data 对象的数字键没有引号，
/// 如 {153922: {"cid":"27636",...}}，这不符合 JSON 规范。
/// 此函数在 jsonDecode 前给所有裸数字键补上引号。
///
/// 正则 [{,](\d+): 匹配 {数字: 或 ,数字: 模式，
/// 替换为 {/,"数字":，纯字符串操作无 JSON 解析干扰。
String _fixNumericKeys(String raw) {
  return raw.replaceAllMapped(RegExp(r'[{,](\d+):'), (match) {
    final prefix = match[0]![0]; // '{' 或 ','
    return '$prefix"${match[1]}":';
  });
}

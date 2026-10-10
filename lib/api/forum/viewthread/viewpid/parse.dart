import 'package:mtbbs/core/parser/post_parser.dart';
import 'package:mtbbs/core/parser/xml_helper.dart';

/// 单帖详情（viewpid）响应解析
///
/// 从 inajax XML/CDATA 中提取单条帖子/评论的完整数据。
/// 内部委托 [parsePostFromTable] 完成 PC 模板解析（表情还原由解析层
/// 自行从 EmojiService 读取当前站点数据）。
///
/// 返回字段名与 getThreadDetail 一致：username / postTime。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final inajax = parseInajaxXml(body);
  if (inajax == null) {
    return {'success': false, 'message': '非 inajax 响应', 'raw_type': 'unknown'};
  }

  final postTable = inajax.htmlDoc.querySelector('table[id^="pid"]');
  if (postTable == null) {
    return {'success': false, 'message': '未找到帖子容器'};
  }
  return {
    'success': true,
    'post': parsePostFromTable(postTable),
    'raw_type': 'xml_cdata',
  };
}

/// 解析「按 pid 定位回复」的 301 跳转目标，提取 tid / page。
///
/// [location] 形如 `forum.php?mod=viewthread&tid=174303&page=1#pid11933888`
/// （可能是相对路径，用 [Uri.parse] 取 query 即可，无需判断 host）。
Map<String, dynamic> parseFindpostLocation(String location, int statusCode) {
  final href = location.trim();
  if (href.isEmpty) {
    return {'success': false, 'message': '无重定向地址（HTTP $statusCode）'};
  }
  final query = Uri.parse(href).queryParameters;
  final tid = query['tid'] ?? '';
  if (tid.isEmpty) {
    return {'success': false, 'message': '重定向地址未含 tid（HTTP $statusCode）'};
  }
  final page = int.tryParse(query['page'] ?? '') ?? 1;
  return {'success': true, 'tid': tid, 'page': page};
}

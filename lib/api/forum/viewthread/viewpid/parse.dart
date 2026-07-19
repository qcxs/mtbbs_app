import 'package:html/dom.dart' as dom;

import '../../../../core/post_parser.dart';
import '../../../../core/xml_helper.dart';

/// 单帖详情（viewpid）响应解析
///
/// 从 inajax XML/CDATA 中提取单条帖子/评论的完整数据。
/// 内部委托 [parsePostFromTable] 完成 PC 模板解析。
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

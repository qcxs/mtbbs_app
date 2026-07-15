import 'package:html/parser.dart' as html_parser;
import '../../../core/xml_helper.dart';

/// 论坛导航响应解析
///
/// 响应为 inajax XML/CDATA，内部 HTML 结构为：
/// ```
/// <ul id="fs_group"><li fid="1">分区名</li>...</ul>
/// <ul id="fs_forum_common"><li fid="41">版块名</li>...</ul>
/// <ul id="fs_forum_分区id"><li fid="37">版块名</li>...</ul>
/// ```
///
/// 返回 `{success, forums: {fid: name}}`
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final inajax = parseInajaxXml(body);
  if (inajax == null) {
    return {'success': false, 'message': '非 inajax 响应'};
  }

  final doc = html_parser.parse(inajax.cdataHtml);
  final forums = <String, String>{};

  // 只取 fs_forum_* 内的版块 li，排除 fs_group（一级分区）
  for (final ul in doc.querySelectorAll('ul[id^="fs_forum_"]')) {
    for (final li in ul.querySelectorAll('li[fid]')) {
      final fid = li.attributes['fid'] ?? '';
      final name = li.text.trim();
      if (fid.isNotEmpty && name.isNotEmpty) {
        forums[fid] = name;
      }
    }
  }

  return {
    'success': forums.isNotEmpty,
    'forums': forums,
    'count': forums.length,
  };
}

import 'package:html/parser.dart' as html_parser;
import '../../../core/xml_helper.dart';

/// 论坛导航响应解析
///
/// 响应格式可能为两种之一：
/// 1. 标准 inajax XML/CDATA: `<root><![CDATA[ HTML ]]></root>`
/// 2. Discuz succeedhandle_ JS 回调: `succeedhandle_nav('ajaxtarget', 'HTML');`
///
/// 内部 HTML 结构：
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

  // 尝试从响应体中提取 HTML 内容
  String? htmlContent;

  // 1. 优先尝试 CDATA XML 格式
  final inajax = parseInajaxXml(body);
  if (inajax != null) {
    htmlContent = inajax.cdataHtml;
  }

  // 2. 尝试 succeedhandle_ 回调格式
  //    succeedhandle_nav('ajaxtarget', 'HTML...');
  if (htmlContent == null) {
    final jsMatch =
        RegExp(r"""succeedhandle_\w+\s*\(\s*'[^']*'\s*,\s*'([\s\S]*?)'\s*\);?""")
            .firstMatch(body);
    if (jsMatch != null) {
      htmlContent = jsMatch
          .group(1)!
          // Discuz 会对引号转义，还原
          .replaceAll("\\'", "'")
          .replaceAll('\\"', '"');
    }
  }

  if (htmlContent == null || htmlContent.trim().isEmpty) {
    return {'success': false, 'message': '无法从响应中提取 HTML'};
  }

  final doc = html_parser.parse(htmlContent);
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

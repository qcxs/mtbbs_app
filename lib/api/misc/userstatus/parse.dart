import 'dart:convert';
import 'package:html/parser.dart' as html_parser;

/// 用户状态响应解析
///
/// 从 misc.php?mod=userstatus 的 JSON 响应中提取：
/// ```json
/// {"uid":"152009","userstatus":"<div id=\"um\">...HTML...</div>","qmenu":"..."}
/// ```
/// userstatus HTML 中包含用户名、头像、积分、用户组等信息。
/// 未登录时 uid 为 "0"。
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  try {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final uid = json['uid']?.toString() ?? '0';

    if (uid == '0') {
      return {'success': false, 'uid': '0', 'message': '未登录'};
    }

    final result = <String, dynamic>{'success': true, 'uid': uid};

    // 解析 userstatus HTML
    final userstatusHtml = json['userstatus']?.toString() ?? '';
    if (userstatusHtml.isNotEmpty) {
      final doc = html_parser.parse(userstatusHtml);

      // 用户名：.vwmy a
      final usernameEl = doc.querySelector('.vwmy a');
      if (usernameEl != null) {
        result['username'] = usernameEl.text.trim();
      }

      // 头像：.avt img
      final avatarEl = doc.querySelector('.avt img');
      if (avatarEl != null) {
        result['avatarUrl'] = avatarEl.attributes['src'];
      }

      // 空间链接：.avt a 的 href
      final avatarLink = doc.querySelector('.avt a')?.attributes['href'] ?? '';
      if (avatarLink.isNotEmpty) {
        result['spaceUrl'] = avatarLink;
      }

      // 积分和用户组在第二个 <p> 中
      // <p><a>积分: 11385</a>|<a>用户组: 博士生</a></p>
      final paragraphs = doc.querySelectorAll('p');
      if (paragraphs.length >= 2) {
        final infoText = paragraphs[1].text;
        final creditMatch = RegExp(r'积分:\s*([\d,]+)').firstMatch(infoText);
        if (creditMatch != null) {
          result['credits'] = creditMatch.group(1)?.replaceAll(',', '');
        }
        final groupMatch = RegExp(r'用户组:\s*([^<\s]+)').firstMatch(infoText);
        if (groupMatch != null) {
          result['userGroup'] = groupMatch.group(1)?.trim();
        }
      }
    }

    return result;
  } catch (e) {
    return {'success': false, 'message': '解析失败: $e'};
  }
}

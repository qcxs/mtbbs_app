import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/page_helper.dart';

/// 从发帖/回复页面的 HTML 中提取会话字段
///
/// 返回：
/// - formhash: CSRF 令牌
/// - posttime: 时间戳
/// - noticeauthor: 通知作者（引用回复时才有）
/// - reppid: 被回复的帖子 PID（引用回复时才有）
Map<String, dynamic> parseFormData(String body) {
  final doc = htmlParser.parse(body);

  // 统一检测 Discuz 错误页（登录、权限不足等）
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'formhash': '',
      'posttime': '',
      'noticeauthor': '',
      'reppid': '',
      'noticetrimstr': '',
      'noticeauthormsg': '',
      'loginRequired': pageError.loginRequired,
    };
  }

  final formhash = _extractInputValue(doc, 'formhash');
  final posttime = _extractInputValue(doc, 'posttime');
  final noticeauthor = _extractInputValue(doc, 'noticeauthor');
  final reppid = _extractInputValue(doc, 'reppid');
  final noticetrimstr = _extractInputValue(doc, 'noticetrimstr');
  final noticeauthormsg = _extractInputValue(doc, 'noticeauthormsg');

  return {
    'success': formhash != null,
    'formhash': formhash ?? '',
    'posttime': posttime ?? '',
    'noticeauthor': noticeauthor ?? '',
    'reppid': reppid ?? '',
    'noticetrimstr': noticetrimstr ?? '',
    'noticeauthormsg': noticeauthormsg ?? '',
    'loginRequired': false,
  };
}

String? _extractInputValue(dom.Document doc, String name) {
  final byName = doc.querySelector('input[name="$name"]');
  if (byName != null) return byName.attributes['value'] ?? '';
  final byId = doc.querySelector('input#$name, input[id="$name"]');
  if (byId != null) return byId.attributes['value'] ?? '';
  return null;
}

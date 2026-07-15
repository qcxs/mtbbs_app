import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'page_helper.dart';

/// 从编辑页/发帖页/回复页提取的会话数据
class PageFormData {
  final String formhash;
  final String posttime;
  final String fid;
  final String tid;
  final String pid;
  final String noticeauthor;
  final String reppid;
  final String noticetrimstr;
  final String noticeauthormsg;

  /// 编辑模式下的标题（仅 editPost 时有效）
  final String title;

  /// 编辑模式下的内容（仅 editPost/editReply 时有效）
  final String content;

  /// 编辑模式下已绑定的图片
  final List<Map<String, String>> images;

  /// 图片上传所需的 hash（从页面 JavaScript 中提取）
  final String uploadHash;

  /// 请求对应的 URL
  final String fetchedUrl;

  /// 是否提取成功
  final bool success;
  final bool loginRequired;
  final String? error;

  const PageFormData({
    this.formhash = '',
    this.posttime = '',
    this.fid = '',
    this.tid = '',
    this.pid = '',
    this.noticeauthor = '',
    this.reppid = '',
    this.noticetrimstr = '',
    this.noticeauthormsg = '',
    this.title = '',
    this.content = '',
    this.images = const [],
    this.uploadHash = '',
    this.fetchedUrl = '',
    this.success = false,
    this.loginRequired = false,
    this.error,
  });
}

/// 统一页面提取器
///
/// 根据编辑器类型构造对应的 Discuz 页面 URL，提取 formhash/posttime 等表单字段。
/// 编辑模式额外提取标题、内容、已绑定图片。
class PageFetcher {
  final String Function(String url) fetch;

  PageFetcher({required this.fetch});

  /// 构造页面 URL
  static String buildUrl({
    required String type,
    String fid = '',
    String tid = '',
    String pid = '',
    String? repquote,
  }) {
    switch (type) {
      case 'post':
        return '/forum.php?mod=post&action=newthread&fid=$fid&mobile=2';
      case 'comment':
        return '/forum.php?mod=post&action=reply&fid=2&tid=$tid&mobile=2';
      case 'reply':
        final q = repquote != null ? '&repquote=$repquote' : '';
        return '/forum.php?mod=post&action=reply&fid=2&tid=$tid$q&mobile=2';
      case 'editPost':
      case 'editReply':
        return '/forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1&mobile=2';
      default:
        return '';
    }
  }

  /// 提取表单字段
  static PageFormData parsePage(String html, {String url = ''}) {
    final doc = htmlParser.parse(html);

    // 统一检测 Discuz 错误页（登录、主题不存在、权限不足等）
    final pageError = checkPageError(doc, html);
    if (pageError.isError) {
      return PageFormData(
        success: false,
        loginRequired: pageError.loginRequired,
        error: pageError.message,
      );
    }

    final formhash = _val(doc, 'formhash');
    final posttime = _val(doc, 'posttime');
    final fid = _val(doc, 'fid');
    final tid = _val(doc, 'tid');
    final pid = _val(doc, 'pid');
    final noticeauthor = _val(doc, 'noticeauthor');
    final reppid = _val(doc, 'reppid');
    final noticetrimstr = _val(doc, 'noticetrimstr');
    final noticeauthormsg = _val(doc, 'noticeauthormsg');

    // 编辑模式：提取标题
    final titleInput = doc.querySelector(
      'input#needsubject, input[id="needsubject"]',
    );
    final title = titleInput?.attributes['value']?.trim() ?? '';

    // 编辑模式：提取内容
    String content = '';
    final textarea = doc.querySelector(
      'textarea#needmessage, textarea[id="needmessage"]',
    );
    if (textarea != null) {
      content = textarea.text.trim();
    } else {
      final textarea2 = doc.querySelector(
        'textarea#e_textarea, textarea[id="e_textarea"]',
      );
      if (textarea2 != null) content = textarea2.text.trim();
    }

    // 编辑模式：提取已绑定的图片
    final images = <Map<String, String>>[];
    final imgList = doc.querySelector('ul#imglist');
    if (imgList != null) {
      for (final li in imgList.querySelectorAll('li')) {
        final span = li.querySelector('span[aid]');
        final img = li.querySelector('img');
        final aid = span?.attributes['aid'] ?? '';
        final src = img?.attributes['src'] ?? '';
        if (aid.isNotEmpty && src.isNotEmpty) {
          images.add({'aid': aid, 'src': src, 'type': 'existing'});
        }
      }
    }

    // 从页面 JavaScript 中提取图片上传所需的 hash
    // 格式: uploadformdata:{uid:"...", hash:"32位hex"}
    final hashMatch = RegExp(
      r'''uploadformdata[^}]*?hash:"([a-f0-9]+)"''',
    ).firstMatch(html);
    final uploadHash = hashMatch?.group(1) ?? '';

    return PageFormData(
      formhash: formhash,
      posttime: posttime,
      fid: fid,
      tid: tid,
      pid: pid,
      noticeauthor: noticeauthor,
      reppid: reppid,
      noticetrimstr: noticetrimstr,
      noticeauthormsg: noticeauthormsg,
      title: title,
      content: content,
      images: images,
      uploadHash: uploadHash,
      fetchedUrl: url,
      success: formhash.isNotEmpty,
    );
  }

  /// 从 HTML 中提取 input value（by id or name）
  static String _val(dom.Document doc, String name) {
    final byName = doc.querySelector('input[name="$name"]');
    if (byName != null) return byName.attributes['value'] ?? '';
    final byId = doc.querySelector('input#$name, input[id="$name"]');
    if (byId != null) return byId.attributes['value'] ?? '';
    return '';
  }
}

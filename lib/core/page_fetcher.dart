import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/logger.dart';
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

  /// 编辑模式下已绑定的附件（仅 PC 版，从 a[id^=attachname] 提取）
  final List<Map<String, String>> boundAttachments;

  /// 图片上传所需的 hash（从页面 JavaScript 中提取）
  final String uploadHash;

  /// 论坛允许的图片扩展名列表（如 ['jpg','jpeg','gif','png']）
  final List<String> imageExtensions;

  /// 论坛允许的附件扩展名列表（如图片+文档等）
  final List<String> attachmentExtensions;

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
    this.boundAttachments = const [],
    this.uploadHash = '',
    this.imageExtensions = const [],
    this.attachmentExtensions = const [],
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
        return '/forum.php?mod=post&action=newthread&fid=$fid';
      case 'comment':
        return '/forum.php?mod=post&action=reply&fid=2&tid=$tid';
      case 'reply':
        final q = repquote != null ? '&repquote=$repquote' : '';
        return '/forum.php?mod=post&action=reply&fid=2&tid=$tid$q';
      case 'editPost':
      case 'editReply':
        return '/forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid&page=1';
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
      'input#subject, input[name="subject"]',
    );
    final title = titleInput?.attributes['value']?.trim() ?? '';

    // 编辑模式：提取内容
    String content = '';
    final textarea = doc.querySelector(
      'textarea#e_textarea, textarea[id="e_textarea"]',
    );
    if (textarea != null) content = textarea.text.trim();

    // 编辑模式：提取已绑定的图片和附件
    // PC 版格式：
    //   图片：<a id="imageattach{aid}"><img id="image_{aid}" src="forum.php?mod=image&aid={aid}...">
    //   附件：<a id="attachname{aid}" title="filename 文件大小: ...">filename</a>
    final images = <Map<String, String>>[];
    final boundAttachments = <Map<String, String>>[];

    for (final a in doc.querySelectorAll('a[id^="imageattach"]')) {
      final aId = a.attributes['id'] ?? '';
      final aid = aId.replaceFirst('imageattach', '');
      if (aid.isEmpty || !RegExp(r'^\d+$').hasMatch(aid)) continue;
      final img = a.querySelector('img');
      final src = img?.attributes['src'] ?? '';
      if (src.isNotEmpty) {
        images.add({'aid': aid, 'src': src, 'type': 'existing'});
      }
    }

    for (final a in doc.querySelectorAll('a[id^="attachname"]')) {
      final aId = a.attributes['id'] ?? '';
      final aid = aId.replaceFirst('attachname', '');
      if (aid.isEmpty || !RegExp(r'^\d+$').hasMatch(aid)) continue;
      final title = a.attributes['title'] ?? '';
      final sizeMatch = RegExp(r'文件大小:\s*([^ ]+)').firstMatch(title);
      boundAttachments.add({
        'aid': aid,
        'filename': a.text.trim(),
        'title': title,
        'size': sizeMatch?.group(1) ?? '',
      });
    }

    // 从页面表单中提取图片/附件上传所需的 hash
    final hashInput = doc.querySelector(
      'form#imgattachform input[name="hash"], '
      'form#attachform input[name="hash"]',
    );
    final uploadHash = hashInput?.attributes['value'] ?? '';

    // 从页面 JavaScript 中提取允许的文件扩展名
    List<String> parseExtList(String raw) => raw
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    final extMatch = RegExp(
      r"""var\s+extensions\s*=\s*'([^']+)'""",
    ).firstMatch(html);
    final imgExtMatch = RegExp(
      r"""var\s+imgexts\s*=\s*'([^']+)'""",
    ).firstMatch(html);
    final attachmentExtensions = extMatch != null
        ? parseExtList(extMatch.group(1)!)
        : <String>[];
    final imageExtensions = imgExtMatch != null
        ? parseExtList(imgExtMatch.group(1)!)
        : <String>[];

    AppLogger.i(
      'PAGE',
      jsonEncode({
        'type': 'editor_page',
        'url': url,
        'formhash': formhash.isNotEmpty,
        'fid': fid,
        'tid': tid,
        'pid': pid,
        'titleLen': title.length,
        'contentLen': content.length,
        'images': images.length,
        'boundAttachments': boundAttachments.length,
        'uploadHash': uploadHash.isNotEmpty,
        'imageExts': imageExtensions.join(','),
        'attachExts': attachmentExtensions.join(','),
      }),
    );

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
      boundAttachments: boundAttachments,
      uploadHash: uploadHash,
      imageExtensions: imageExtensions,
      attachmentExtensions: attachmentExtensions,
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

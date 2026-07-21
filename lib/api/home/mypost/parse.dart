import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 我的帖子 HTML 解析
///
/// 解析 home.php?mod=space&do=notice&view=mypost&type=post 页面，
/// 提取帖子提醒列表和分页信息。
///
/// 每条提醒的 DOM 结构：
/// ```html
/// <dl class="cl" notice="6744379" id="notice_6744379">
///   <dd class="m avt mbn">
///     <a href="https://bbs.binmt.cc/space-uid-16205.html">
///       <img src="...avatar...">
///     </a>
///   </dd>
///   <dt>
///     <span class="xg1 xw0"><span title="2026-7-19 14:53">半小时前</span></span>
///   </dt>
///   <dd class="ntc_body">
///     <a href="...space-uid-xxx.html">精神小伙</a> 回复了您的帖子
///     <a href="...ptid=xxx&pid=xxx">帖子标题</a> &nbsp;
///     <a href="...pid=xxx&ptid=xxx" class="lit">查看</a>
///   </dd>
/// </dl>
/// ```

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = html_parser.parse(body);

  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  final items = <Map<String, dynamic>>[];
  final dls = doc.querySelectorAll('dl[id^="notice_"]');

  for (final dl in dls) {
    final item = _parseItem(dl);
    if (item != null) items.add(item);
  }

  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  AppLogger.i(
    'PARSE',
    'mypost: ${items.length} items, page $currentPage/$totalPages',
  );

  return {
    'success': true,
    'items': items,
    'count': items.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
  };
}

Map<String, dynamic>? _parseItem(dom.Element dl) {
  try {
    // 头像链接 → uid
    final avatarLink = dl.querySelector('dd.avt a');
    final avatarHref = avatarLink?.attributes['href'] ?? '';
    final uidMatch = RegExp(r'uid[=-](\d+)').firstMatch(avatarHref);
    final uid = uidMatch?.group(1) ?? '';

    // ntc_body 中的解析
    final bodyEl = dl.querySelector('dd.ntc_body');
    if (bodyEl == null) return null;

    // 保留完整 HTML 供内联渲染
    final bodyHtml = bodyEl.nodes.map((n) {
      if (n is dom.Element) return n.outerHtml;
      if (n is dom.Text) return n.text;
      return n.toString();
    }).join();

    // 用户名：ntc_body 中的第一个 a 标签
    final firstLink = bodyEl.querySelector('a');
    final username = sanitizeText(firstLink?.text ?? '');

    // 帖子标题 + 查看链接
    String threadTitle = '';
    String viewUrl = '';
    for (final a in bodyEl.querySelectorAll('a[target="_blank"]')) {
      final href = a.attributes['href'] ?? '';
      if (a.classes.contains('lit')) {
        viewUrl = href;
      } else if (threadTitle.isEmpty) {
        threadTitle = sanitizeText(a.text);
      }
    }

    // 兜底 viewUrl
    if (viewUrl.isEmpty) {
      for (final a in bodyEl.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('goto=findpost') && href.contains('pid=')) {
          viewUrl = href;
        }
      }
    }

    // 时间：<dt><span class="xg1 xw0"><span title="2026-7-20 02:46">14 小时前</span></span></dt>
    String time = '';
    String timeTitle = '';
    final dtEl = dl.querySelector('dt');
    if (dtEl != null) {
      final timeInner = dtEl.querySelector('span.xg1.xw0 span');
      if (timeInner != null) {
        time = timeInner.text.trim().replaceAll('\u00A0', ' ');
        timeTitle = timeInner.attributes['title'] ?? '';
      }
    }

    return {
      'uid': uid,
      'username': username,
      'threadTitle': threadTitle,
      'viewUrl': viewUrl,
      'bodyHtml': bodyHtml,
      'time': time,
      'timeTitle': timeTitle,
      // segments：结构化段落供 UI 直接渲染，无需 HTML 解析
      'segments': _extractSegments(bodyEl),
    };
  } catch (e) {
    AppLogger.w('PARSE', 'mypost item parse error: $e');
    return null;
  }
}

/// 从 ntc_body 中提取结构化段落
List<Map<String, dynamic>> _extractSegments(dom.Element bodyEl) {
  final segments = <Map<String, dynamic>>[];
  for (final node in bodyEl.nodes) {
    if (node is dom.Text) {
      final text = node.text
          .replaceAll('\u00A0', ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (text.trim().isNotEmpty) {
        segments.add({'type': 'text', 'text': text.trim()});
      }
    } else if (node is dom.Element && node.localName == 'a') {
      final href = node.attributes['href'] ?? '';
      final text = sanitizeText(node.text);
      if (text.isEmpty) continue;
      if (href.contains('space-uid-') || href.contains('space.php?uid=')) {
        final uidMatch = RegExp(r'uid[=-](\d+)').firstMatch(href);
        segments.add({
          'type': 'user',
          'text': text,
          'uid': uidMatch?.group(1) ?? '',
        });
      } else {
        segments.add({'type': 'thread', 'text': text, 'url': href});
      }
    }
  }
  return segments;
}

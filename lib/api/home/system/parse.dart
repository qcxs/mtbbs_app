import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 系统提醒 HTML 解析
///
/// 解析 home.php?mod=space&do=notice&view=system 页面。
///
/// 每条提醒的 DOM 结构：
/// ```html
/// <dl class="cl" notice="6739069" id="notice_6739069">
///   <dd class="m avt mbn">
///     <img src="...systempm.png" alt="systempm">
///   </dd>
///   <dt>
///     <span class="xg1 xw0"><span title="2026-7-16 04:50">3 天前</span></span>
///   </dt>
///   <dd class="ntc_body">
///     您在主题 <a href="...ptid=169295" target="_blank">帖子标题</a> 的帖子被
///     <a href="...space-uid-xxx.html">用户名</a> 评分 金币 +1
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
    'system: ${items.length} items, page $currentPage/$totalPages',
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
    final id = dl.attributes['id'] ?? '';
    final noticeId = id.startsWith('notice_') ? id.substring(7) : '';

    // 时间
    final dtEl = dl.querySelector('dt .xg1.xw0 span[title]');
    final time = dtEl?.attributes['title'] ?? '';

    // ntc_body 解析
    final bodyEl = dl.querySelector('dd.ntc_body');
    if (bodyEl == null) return null;

    // 保留完整 bodyHtml（含 quote 留言）供内联渲染
    final bodyHtml = bodyEl.nodes.map((n) {
      if (n is dom.Element) return n.outerHtml;
      if (n is dom.Text) return n.text;
      return n.toString();
    }).join();

    // 纯文本消息（去掉 quote 内容，供旧字段使用）
    final bodyTextClone = bodyEl.clone(true);
    bodyTextClone
        .querySelectorAll('.quote, blockquote')
        .forEach((e) => e.remove());
    final fullText = sanitizeText(bodyTextClone.text);

    // 帖子标题 + 链接：第一个 a[target="_blank"]
    String threadTitle = '';
    String threadUrl = '';
    // 用户名 + uid：ntc_body 中指向 space 的 a 标签
    String username = '';
    String userUid = '';
    String userUrl = '';

    for (final a in bodyEl.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      final text = sanitizeText(a.text);

      if (href.contains('space-uid-') || href.contains('space.php?uid=')) {
        // 用户链接
        if (username.isEmpty) {
          username = text;
          userUrl = href;
          final m = RegExp(r'uid[=-](\d+)').firstMatch(href);
          if (m != null) userUid = m.group(1)!;
        }
      } else if (href.contains('goto=findpost') && threadTitle.isEmpty) {
        // 帖子链接
        threadTitle = text;
        threadUrl = href;
      } else if (href.contains('forum.php?mod=redirect') &&
          threadTitle.isEmpty) {
        threadTitle = text;
        threadUrl = href;
      }
    }

    // 兜底 threadUrl
    if (threadUrl.isEmpty) {
      for (final a in bodyEl.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('ptid=')) {
          threadUrl = href;
          if (threadTitle.isEmpty) threadTitle = sanitizeText(a.text);
          break;
        }
      }
    }

    return {
      'noticeId': noticeId,
      'time': time,
      'message': fullText,
      'bodyHtml': bodyHtml,
      'threadTitle': threadTitle,
      'threadUrl': threadUrl,
      'username': username,
      'userUid': userUid,
      'userUrl': userUrl,
      // segments：结构化段落供 UI 直接渲染，无需 HTML 解析
      'segments': _extractSegments(bodyEl),
    };
  } catch (e) {
    AppLogger.w('PARSE', 'system item parse error: $e');
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
    } else if (node is dom.Element) {
      // 处理 quote 块
      if (node.localName == 'blockquote' || node.classes.contains('quote')) {
        final quoteText = node.text.trim();
        if (quoteText.isNotEmpty) {
          segments.add({'type': 'quote', 'text': quoteText});
        }
        continue;
      }
      // 处理链接
      if (node.localName == 'a') {
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
  }
  return segments;
}

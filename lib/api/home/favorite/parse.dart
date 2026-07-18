import 'package:html/parser.dart' as htmlParser;
import '../../../core/logger.dart';

/// 收藏列表 HTML 解析
///
/// 页面结构：
/// ```html
/// <li id="fav_666610" class="bbda ptm pbm">
///   <span><img src="...thread.gif" alt="thread"></span>
///   <a href="...thread-122729-1-1.html">标题</a>
///   <span class="xg1">2026-7-6 19:21</span>
///   <div class="quote">
///     <blockquote id="quote_preview">备注</blockquote>
///   </div>
/// </li>
/// ```

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  try {
    final doc = htmlParser.parse(body);
    final items = <Map<String, dynamic>>[];
    final lis = doc.querySelectorAll('li[id^="fav_"]');

    for (final li in lis) {
      final input = li.querySelector('input[name="favorite[]"]');
      final favid = input?.attributes['value'] ?? '';

      final a = li.querySelector('a[href*="thread-"]');
      final href = a?.attributes['href'] ?? '';
      final tidMatch = RegExp(r'thread-(\d+)').firstMatch(href);
      final tid = tidMatch?.group(1) ?? '';
      final title = a?.text.trim() ?? '';

      final timeEl = li.querySelector('span.xg1');
      final time = timeEl?.text.trim() ?? '';

      final quote = li.querySelector('blockquote#quote_preview');
      final note = quote?.text.trim() ?? '';

      final img = li.querySelector('img');
      final type = img?.attributes['alt'] ?? '';

      if (favid.isNotEmpty || tid.isNotEmpty) {
        items.add({
          'favid': favid,
          'tid': tid,
          'title': title,
          'time': time,
          'note': note,
          'type': type,
        });
      }
    }

    // 分页信息：检查是否还有下一页
    bool hasMore = false;
    final pg = doc.querySelector('.pg');
    if (pg != null) {
      final links = pg.querySelectorAll('a');
      int maxPage = 1;
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        final pageMatch = RegExp(r'page=(\d+)').firstMatch(href);
        if (pageMatch != null) {
          final p = int.tryParse(pageMatch.group(1)!) ?? 1;
          if (p > maxPage) maxPage = p;
        }
      }
      final strong = pg.querySelector('strong');
      final currentPage = int.tryParse(strong?.text.trim() ?? '') ?? 1;
      hasMore = maxPage > currentPage;
    }

    AppLogger.i('PARSE', 'favorites: ${items.length} items, hasMore=$hasMore');
    if (items.isNotEmpty) {
      AppLogger.list(
        'PARSE',
        items,
        3,
        labelFn: (item) => '${item['title']}(${item['tid']})',
        summary: '${items.length} items',
      );
    }

    return {
      'success': true,
      'items': items,
      'count': items.length,
      'hasMore': hasMore,
    };
  } catch (e) {
    AppLogger.e('PARSE', 'favorites parse error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}

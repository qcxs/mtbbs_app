import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/utils/logger.dart';

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

      final a = li.querySelector(
        'a[href*="thread-"], a[href*="viewthread"], a[href*="tid="]',
      );
      final href = a?.attributes['href'] ?? '';
      // 兼容伪静态（thread-4-1-1.html）与动态（viewthread&tid=4）两种链接
      final tidMatch = RegExp(r'thread-(\d+)|tid=(\d+)').firstMatch(href);
      final tid = tidMatch?.group(1) ?? tidMatch?.group(2) ?? '';
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

/// 收藏结果解析
///
/// Discuz 收藏成功后返回 301/302 跳转（Location 含 viewthread），
/// 或 200 提示页。已收藏会提示"抱歉，您已收藏，请勿重复收藏"——
/// 属于幂等成功，不应视为失败。
Map<String, dynamic> parseAddResult(String body, int statusCode) {
  if (statusCode == 301 || statusCode == 302) {
    return {'success': true, 'message': '收藏成功'};
  }
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }
  if (body.contains('已收藏')) {
    return {'success': true, 'message': '已收藏过该帖子'};
  }
  final errorMatch = RegExp(r'(抱歉|错误|失败|无权|权限|非法)').firstMatch(body);
  if (errorMatch != null) {
    final start = body.indexOf(errorMatch.group(0)!);
    final snippet = body.substring(start, start + 60);
    final cleanMsg = snippet.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return {'success': false, 'message': cleanMsg};
  }
  final ok = body.contains('收藏成功') || body.contains('已收藏');
  return {'success': ok, 'message': ok ? '收藏成功' : '未知响应'};
}

/// 删除收藏结果解析
///
/// Discuz 删除成功返回 301/302 跳转回收藏列表，或提示"取消收藏成功"；
/// 失败时正文含错误文案。
Map<String, dynamic> parseDeleteResult(String body, int statusCode) {
  if (statusCode == 301 || statusCode == 302) {
    return {'success': true, 'message': '取消收藏成功'};
  }
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }
  final errorMatch = RegExp(r'(抱歉|错误|失败|无权|权限|非法)').firstMatch(body);
  if (errorMatch != null) {
    final start = body.indexOf(errorMatch.group(0)!);
    final snippet = body.substring(start, start + 60);
    final cleanMsg = snippet.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return {'success': false, 'message': cleanMsg};
  }
  final ok = body.contains('取消收藏成功') || body.contains('收藏已取消');
  return {'success': ok, 'message': ok ? '取消收藏成功' : '未知响应'};
}

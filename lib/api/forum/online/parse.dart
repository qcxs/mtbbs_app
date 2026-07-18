import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;
import '../../../core/logger.dart';

/// Discuz 在线用户 HTML 解析
///
/// 页面结构：
/// ```html
/// <dt class="ptm pbm bbda">
///   <img src="...online_admin.gif"> 管理员
///   <img src="...online_supermod.gif"> 超级版主
///   <img src="...online_moderator.gif"> 版主
///   <img src="...online_member.gif"> 会员
/// </dt>
/// <dd class="ptm pbm">
///   <ul class="cl">
///     <li title="时间: 18:01">
///       <img src="...online_member.gif" alt="icon">
///       <a href="...space-uid-71118.html">~xiaohui~</a>
///     </li>
///   </ul>
/// </dd>
/// ```

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  try {
    final doc = htmlParser.parse(body);

    // 1. 提取类型图例 — 遍历 dt 的子节点，<img> 后紧跟文本节点即类型名
    final typeMap = <String, String>{};
    final dt = doc.querySelector('dt.ptm.pbm.bbda');
    if (dt != null) {
      String? pendingFile;
      for (final node in dt.nodes) {
        if (node is dom.Element && node.localName == 'img') {
          pendingFile = node.attributes['src']?.split('/').last;
        } else if (node.nodeType == 3 && pendingFile != null) {
          final text = (node.text ?? '').trim();
          if (text.isNotEmpty) {
            typeMap[pendingFile] = text;
            pendingFile = null;
          }
        }
      }
    }

    // 2. 提取在线用户列表
    final items = <Map<String, dynamic>>[];
    final ul = doc.querySelector('dd ul.cl');
    if (ul != null) {
      final lis = ul.querySelectorAll('li');
      for (final li in lis) {
        final title = li.attributes['title'] ?? '';
        final time = title.startsWith('时间: ') ? title.substring(4) : title;

        final img = li.querySelector('img');
        final imgSrc = img?.attributes['src'] ?? '';
        final imgFile = imgSrc.split('/').last;
        final type = typeMap[imgFile] ?? '';

        final a = li.querySelector('a');
        final username = a?.text.trim() ?? '';
        final href = a?.attributes['href'] ?? '';
        final uidMatch = RegExp(r'space-uid-(\d+)').firstMatch(href);
        final uid = uidMatch?.group(1) ?? '';

        if (username.isNotEmpty || uid.isNotEmpty) {
          items.add({
            'username': username,
            'uid': uid,
            'type': type,
            'typeIcon': imgSrc,
            'time': time,
          });
        }
      }
    }

    // 3. 提取统计信息
    // h3 结构: <strong><a>在线会员</a></strong><span class="xs1">- N 人在线...</span>
    String? stats;
    final h3 = doc.querySelector('h3');
    if (h3 != null) {
      // 直接取 <span> 的文本，不含 "在线会员"；用 span.textContent 替代 h3.text 避免多余文字
      final span = h3.querySelector('span.xs1');
      if (span != null) {
        stats = span.text
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll('  ', ' ')
            .trim();
      } else {
        // 兜底：直接取 h3 文本并移除链接文字
        final link = h3.querySelector('a');
        stats = h3.text;
        if (link != null) stats = stats.replaceFirst(link.text, '');
        stats = stats
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll('  ', ' ')
            .trim();
      }
      if (stats.startsWith('-')) stats = stats.substring(1).trim();
    }

    AppLogger.i('PARSE', 'online: ${items.length} users, stats=$stats');
    if (items.isNotEmpty) {
      AppLogger.d('PARSE', 'typeMap: $typeMap');
      AppLogger.list(
        'PARSE',
        items,
        3,
        labelFn: (item) =>
            '${item['username']}(${item['uid']})[${item['type']}]',
        summary: '${items.length} users',
      );
    }

    return {
      'success': true,
      'items': items,
      'count': items.length,
      'stats': stats ?? '',
    };
  } catch (e) {
    AppLogger.e('PARSE', 'online parse error: $e');
    return {'success': false, 'message': '解析失败: $e'};
  }
}

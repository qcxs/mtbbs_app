import 'package:html/dom.dart' as dom;
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'parser_utils.dart';
import 'thread_list_parser.dart';

/// 空间帖子列表解析器（我的帖子/好友的帖子）
///
/// 识别特征：`<table>` 内包含 `<tr class="th">`（表头行带 `td.icn`）
/// 适用场景：52破解 / MT论坛 的 `home.php?mod=space&do=thread`（我的帖子）
///
/// DOM 结构：
/// ```html
/// <div class="tl">
///   <form><table>
///     <tr class="th">                                    <!-- 表头 -->
///       <td class="icn">&nbsp;</td>
///       <th>主题</th>
///       <td class="frm">版块/群组</td>
///       <td class="num">回复/查看</td>
///       <td class="by">最后发帖</td>
///     </tr>
///     <tr>                                                <!-- 数据行 -->
///       <td class="icn">icon</td>
///       <th>                                               <!-- ★ 标题 -->
///         <a href="thread-{tid}.html">{title}</a>
///         <img src="image_s.gif" alt="图片附件">
///         <span class="tps">分页链接</span>
///       </th>
///       <td><a href="forum-{fid}.html">{forum}</a></td>
///       <td class="num"><a>{replies}</a><em>{views}</em></td>
///       <td class="by"><cite><a>{author}</a></cite><em><a>{time}</a></em></td>
///     </tr>
///   </table></form>
/// </div>
/// ```
class SpaceThreadParser implements ThreadListParser {
  @override
  bool canParse(dom.Document doc) {
    // 特征：<table> 内 <tr class="th"> 且包含 <td class="icn">
    final headerRow = doc.querySelector('table tr.th');
    if (headerRow == null) return false;
    return headerRow.querySelector('td.icn') != null;
  }

  @override
  List<ThreadItem> parse(dom.Document doc) {
    // 数据行直接位于 <table> 下，行首是 <td class="icn">（跳过表头行）
    final rows = doc.querySelectorAll('table tr');
    final items = <ThreadItem>[];
    for (final row in rows) {
      // 跳过表头行
      if (row.className.contains('th')) continue;
      final icn = row.querySelector('td.icn');
      if (icn == null) continue;
      items.add(_parseRow(row));
    }
    return items;
  }

  ThreadItem _parseRow(dom.Element tr) {
    int? threadId;
    String? title, threadUrl;

    // 标题：<th> 内取第一个非分页的链接（排除 .tps 内的分页数字）
    final titleCell = tr.querySelector('th');
    if (titleCell != null) {
      final allLinks = titleCell.querySelectorAll('a');
      dom.Element? titleLink;
      for (final link in allLinks) {
        // 跳过分页链接（.tps 内的数字页码）
        final parent = link.parent;
        if (parent is dom.Element && parent.className == 'tps') continue;
        titleLink = link;
        break;
      }
      if (titleLink != null) {
        title = sanitizeText(titleLink.text);
        final href = titleLink.attributes['href'] ?? '';
        // 从 findpost/ptid= 链接中提取 tid
        final ptidMatch = RegExp(r'ptid=(\d+)').firstMatch(href);
        if (ptidMatch != null) {
          threadId = int.tryParse(ptidMatch.group(1)!);
          threadUrl = normalizeUrl('thread-$threadId-1-1.html');
        } else {
          threadUrl = href;
          threadId = extractThreadIdFromUrl(threadUrl);
        }
        if (threadUrl.isNotEmpty) threadUrl = normalizeUrl(threadUrl);
      }
    }

    // 版块：查找含 forum 链接的 <td>
    String? boardName;
    String? boardUrl;
    int? boardId;
    final forumLink = tr.querySelector(
      'td a[href*="forum-"], td a[href*="forumdisplay"]',
    );
    if (forumLink != null) {
      boardName = sanitizeText(forumLink.text);
      boardUrl = forumLink.attributes['href'] ?? '';
      if (boardUrl.isNotEmpty) boardId = extractBoardIdFromUrl(boardUrl);
    }

    // 统计：<td class="num">
    int? replies, views;
    final numTd = tr.querySelector('td.num');
    if (numTd != null) {
      final replyLink = numTd.querySelector('a');
      if (replyLink != null) {
        replies = int.tryParse(replyLink.text.trim());
      }
      final viewEm = numTd.querySelector('em');
      if (viewEm != null) {
        views = int.tryParse(viewEm.text.trim());
      }
    }

    // 最后发表：<td class="by">（仅提取最后回复时间，不提取作者——这不是发帖人）
    String? time;
    final lastTd = tr.querySelector('td.by');
    if (lastTd != null) {
      final timeEl = lastTd.querySelector('em a, em');
      if (timeEl != null) {
        time = sanitizeText(timeEl.text);
      }
    }

    return ThreadItem(
      uid: null,
      nickname: null,
      time: time,
      title: title,
      threadUrl: threadUrl,
      threadId: threadId,
      boardName: boardName,
      boardUrl: boardUrl,
      boardId: boardId,
      comments: replies,
      views: views,
    );
  }
}

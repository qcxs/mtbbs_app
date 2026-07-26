import 'package:html/dom.dart' as dom;
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'thread_list_parser.dart';

/// 标准 Discuz 表格帖子列表解析器
///
/// 识别特征：`<div id="threadlist">` 内 `<table>` + `<th class="common">` 标题列
/// 适用场景：52破解 全 UA、MT论坛 导读（PC UA）
///
/// DOM 结构：
/// ```html
/// <div id="threadlist" class="tl bm bmw">
///   <table>
///     <tbody id="normalthread_{tid}">
///       <tr>
///         <td class="icn">icon</td>
///         <th class="common">                    <!-- ★ 标题 -->
///           <a class="xst" href="thread-{tid}.html">{title}</a>
///           <span class="xi1">[标签]</span>
///           <a class="xi1">New</a>
///           <img src="image_s.gif">              <!-- 附件标记 -->
///         </th>
///         <td class="by">forum</td>
///         <td class="by">author + time</td>
///         <td class="num">replies + views</td>
///         <td class="by">last post author + time</td>
///       </tr>
///     </tbody>
///   </table>
/// </div>
/// ```
class DiscuzTableParser implements ThreadListParser {
  @override
  bool canParse(dom.Document doc) {
    // 特征：#threadlist 内存在 tbody[id^=normalthread_] 且包含 th
    final tbody = doc.querySelector('#threadlist tbody[id^="normalthread_"]');
    if (tbody == null) return false;
    return tbody.querySelector('th') != null;
  }

  @override
  List<ThreadItem> parse(dom.Document doc) {
    final tbodyList = doc.querySelectorAll(
      '#threadlist tbody[id^="normalthread_"]',
    );
    return tbodyList.map(_parseRow).toList();
  }

  ThreadItem _parseRow(dom.Element tbody) {
    final tr = tbody.querySelector('tr');
    if (tr == null) {
      return ThreadItem(title: null);
    }

    // 按 class 查找各列，不依赖固定索引（板块页 vs 导读页列数不同）
    int? threadId;
    String? title, threadUrl;

    // 标题列：th 内的 a.xst 或 a[href*=thread-]
    final titleCell = tr.querySelector('th');
    if (titleCell != null) {
      final link = titleCell.querySelector('a.xst, a[href*="thread-"]');
      if (link != null) {
        title = sanitizeText(link.text);
        threadUrl = link.attributes['href'] ?? '';
        threadId = _extractThreadId(threadUrl);
        if (threadUrl.isNotEmpty && !threadUrl.startsWith('http')) {
          threadUrl = '${SiteStore.instance.baseUrl}/$threadUrl';
        }
      }
    }

    // 版块：td.by 内有 forum 链接的
    String? boardName;
    String? boardUrl;
    int? boardId;
    final allBy = tr.querySelectorAll('td.by');
    // 分离版块列：内容不含 <cite> 且链接包含 forum-
    dom.Element? forumTd;
    dom.Element? authorTd;
    for (final by in allBy) {
      final hasCite = by.querySelector('cite') != null;
      final hasForumLink =
          by.querySelector('a[href*="forum-"], a[href*="forumdisplay"]') !=
          null;
      if (!hasCite && hasForumLink) {
        forumTd = by;
      } else if (authorTd == null) {
        authorTd = by;
      }
    }
    if (forumTd != null) {
      final link = forumTd.querySelector('a');
      if (link != null) {
        boardName = sanitizeText(link.text);
        boardUrl = link.attributes['href'] ?? '';
        if (boardUrl.isNotEmpty) boardId = _extractBoardId(boardUrl);
      }
    }

    // 作者 + 时间：已在上一步分离出来的 authorTd
    String? author;
    String? time;
    int? uid;
    if (authorTd != null) {
      final cite = authorTd.querySelector('cite a');
      if (cite != null) {
        author = sanitizeText(cite.text);
        uid = _extractUid(cite.attributes['href'] ?? '');
      }
      final emTime = authorTd.querySelector('em span, em');
      if (emTime != null) {
        time = sanitizeText(emTime.text);
      }
    }

    // 统计：td.num
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

    return ThreadItem(
      uid: uid,
      nickname: author,
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

  int? _extractUid(String url) {
    try {
      final uri = Uri.parse(url);
      final uidStr = uri.queryParameters['uid'];
      if (uidStr != null) return int.tryParse(uidStr);
      final m = RegExp(r'space-uid-(\d+)').firstMatch(url);
      if (m != null) return int.tryParse(m.group(1)!);
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _extractThreadId(String url) {
    final result = parseThreadUrl(url);
    return result['tid'] != 0 ? result['tid'] : null;
  }

  int? _extractBoardId(String url) {
    final m = RegExp(r'forum[_-](\d+)').firstMatch(url);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }
}

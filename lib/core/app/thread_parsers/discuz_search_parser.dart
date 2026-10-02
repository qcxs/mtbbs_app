import 'package:html/dom.dart' as dom;
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/thread_parsers/parser_utils.dart';
import 'package:mtbbs/core/app/thread_parsers/thread_list_parser.dart';

/// 标准 Discuz **搜索**结果列表解析器（桌面版 / PC UA）
///
/// 识别特征：`#threadlist` 内为 `<li class="pbw" id="{tid}">`
/// —— **不是**版块页的 `tbody[id^=normalthread_]` 表格结构，
/// 故 [DiscuzTableParser] 不命中，需要本解析器。
///
/// 适用场景：搜索页（`search.php?mod=forum`）桌面版。
///
/// DOM 结构：
/// ```html
/// <div class="slst mtw" id="threadlist">
///   <ul>
///     <li class="pbw" id="{tid}">
///       <h3 class="xs3"><a href="forum.php?mod=viewthread&tid={tid}...">{title}</a></h3>
///       <p class="xg1">{replies} 个回复 - {views} 次查看</p>
///       <p>{summary}</p>
///       <p>
///         <span>{time}</span> -
///         <span><a href="space-uid-{uid}.html">{author}</a></span> -
///         <span><a href="forum-{fid}-1.html">{forumname}</a></span>
///       </p>
///     </li>
///   </ul>
/// </div>
/// ```
class DiscuzSearchParser implements ThreadListParser {
  @override
  bool canParse(dom.Document doc) {
    return doc.querySelector('#threadlist li.pbw') != null;
  }

  @override
  List<ThreadItem> parse(dom.Document doc) {
    return doc.querySelectorAll('#threadlist li.pbw').map(_parseItem).toList();
  }

  ThreadItem _parseItem(dom.Element li) {
    // ===== 标题 / 链接 / tid =====
    String? title;
    String? threadUrl;
    final link = li.querySelector('h3 a');
    if (link != null) {
      title = sanitizeText(link.text);
      final href = link.attributes['href'] ?? '';
      if (href.isNotEmpty) threadUrl = normalizeUrl(href);
    }
    // 克米/标准模板的 li id 就是 tid；取不到再从 URL 兜底
    final tid = int.tryParse(li.id) ?? extractThreadIdFromUrl(threadUrl ?? '');

    // ===== 三段 <p>：统计(xg1) / 摘要 / 元信息(带链接) =====
    dom.Element? statP;
    dom.Element? summaryP;
    dom.Element? metaP;
    for (final p in li.querySelectorAll('p')) {
      if (p.classes.contains('xg1')) {
        statP = p;
      } else if (p.querySelector(
            'a[href*="space-uid"], a[href*="uid="], '
            'a[href*="forum-"], a[href*="forumdisplay"]',
          ) !=
          null) {
        metaP = p;
      } else {
        summaryP ??= p;
      }
    }

    // 回复 / 查看："265 个回复 - 1010 次查看"
    int? replies;
    int? views;
    final statText = statP?.text ?? '';
    if (statText.isNotEmpty) {
      final rm = RegExp(r'(\d+)\s*个?回复').firstMatch(statText);
      if (rm != null) replies = int.tryParse(rm.group(1)!);
      final vm = RegExp(r'(\d+)\s*次?查看').firstMatch(statText);
      if (vm != null) views = int.tryParse(vm.group(1)!);
    }

    // 摘要
    final summary = summaryP == null ? null : sanitizeText(summaryP.text);

    // ===== 时间 / 作者 / 版块 =====
    String? time;
    String? nickname;
    String? boardName;
    String? boardUrl;
    int? uid;
    int? boardId;
    if (metaP != null) {
      time = sanitizeText(metaP.querySelector('span')?.text);

      final authorLink = metaP.querySelector(
        'a[href*="space-uid"], a[href*="uid="]',
      );
      if (authorLink != null) {
        nickname = sanitizeText(authorLink.text);
        uid = extractUidFromUrl(authorLink.attributes['href'] ?? '');
      }

      final boardLink = metaP.querySelector(
        'a[href*="forum-"], a[href*="forumdisplay"]',
      );
      if (boardLink != null) {
        boardName = sanitizeText(boardLink.text);
        final href = boardLink.attributes['href'] ?? '';
        if (href.isNotEmpty) {
          boardUrl = normalizeUrl(href);
          boardId = extractBoardIdFromUrl(boardUrl);
        }
      }
    }

    return ThreadItem(
      uid: uid,
      nickname: nickname,
      time: time,
      title: title,
      summary: summary,
      threadUrl: threadUrl,
      threadId: tid,
      boardName: boardName,
      boardUrl: boardUrl,
      boardId: boardId,
      comments: replies,
      views: views,
    );
  }
}

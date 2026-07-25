import 'package:html/dom.dart' as dom;
import '../../models/thread_item.dart';
import '../site_store.dart';
import '../page_helper.dart';
import 'thread_list_parser.dart';

/// 克米模板表格混合式帖子列表解析器
///
/// 识别特征：`<tbody id="normalthread_">` 内 `<td>` 包含 `<div.comiis_postlist>`
/// 适用场景：MT论坛 板块页（PC UA）
///
/// DOM 结构：
/// ```html
/// <tbody id="normalthread_{tid}">
///   <tr>
///     <td>
///       <div class="comiis_postlist cl">          <!-- 卡片嵌入 td -->
///         <div class="comiis_listtx"><a><img src="avatar"></a></div>
///         <h2 class="cl">
///           <span class="comiis_common">
///             <a href="thread-{tid}.html">{title}</a>
///             <img src="image_s.gif">              <!-- 附件 -->
///           </span>
///         </h2>
///         <p>
///           <span class="y">
///             <em class="km_view">{views}</em>
///             <em class="km_reply"><a>{replies}</a></em>
///           </span>
///           <em class="km_user"><a>{author}</a></em>
///           <em>{time} 发表在</em>
///           <em><a>{forum}</a></em>
///           <em>最后回复于 <a>{last_time}</a></em>
///         </p>
///       </div>
///     </td>
///   </tr>
/// </tbody>
/// ```
class ComiisTableParser implements ThreadListParser {
  @override
  bool canParse(dom.Document doc) {
    // 特征：tbody[id^=normalthread_] 内 td 包含 div.comiis_postlist
    final tbody = doc.querySelector('tbody[id^="normalthread_"]');
    if (tbody == null) return false;
    return tbody.querySelector('td div.comiis_postlist') != null;
  }

  @override
  List<ThreadItem> parse(dom.Document doc) {
    final tbodyList = doc.querySelectorAll('tbody[id^="normalthread_"]');
    return tbodyList.map(_parseRow).toList();
  }

  ThreadItem _parseRow(dom.Element tbody) {
    final postlist = tbody.querySelector('td div.comiis_postlist');
    if (postlist == null) {
      return ThreadItem(title: null);
    }

    // 头像 → UID
    int? uid;
    final avatarLink = postlist.querySelector('.comiis_listtx a');
    if (avatarLink != null) {
      uid = _extractUid(avatarLink.attributes['href'] ?? '');
    }

    // 标题
    String? title, threadUrl;
    int? threadId;
    final titleSpan = postlist.querySelector(
      '.comiis_common a[href*="thread-"]',
    );
    if (titleSpan != null) {
      title = sanitizeText(titleSpan.text);
      threadUrl = titleSpan.attributes['href'] ?? '';
      threadId = _extractThreadId(threadUrl);
      if (threadUrl.isNotEmpty && !threadUrl.startsWith('http')) {
        threadUrl = '${SiteStore.instance.baseUrl}/$threadUrl';
      }
    }

    // 从 <p> 段落提取各字段
    final p = postlist.querySelector('p');

    // 统计
    int? replies, views;
    if (p != null) {
      final replyEl = p.querySelector('.km_reply a');
      if (replyEl != null) {
        replies = int.tryParse(replyEl.text.trim());
      }
      final viewEl = p.querySelector('.km_view');
      if (viewEl != null) {
        views = int.tryParse(viewEl.text.trim());
      }
    }

    // 作者
    String? author;
    if (p != null) {
      final authorEl = p.querySelector('.km_user a');
      if (authorEl != null) {
        author = sanitizeText(authorEl.text);
        if (uid == null) {
          uid = _extractUid(authorEl.attributes['href'] ?? '');
        }
      }
    }

    // 时间：跳过已知非时间 <em>，从 <em> 内的 <span> 提取时间文本
    String? time;
    if (p != null) {
      for (final em in p.querySelectorAll('em')) {
        final cls = em.className;
        if (cls.contains('km_user') ||
            cls.contains('km_view') ||
            cls.contains('km_reply'))
          continue;
        final span = em.querySelector('span');
        if (span != null) {
          final text = sanitizeText(span.text);
          if (text.isNotEmpty && !text.contains('最后回复')) {
            time = text;
            break;
          }
        }
      }
    }

    // 版块
    String? boardName;
    String? boardUrl;
    int? boardId;
    if (p != null) {
      final forumLink = p.querySelector(
        'em a[href*="forum-"], em a[href*="forumdisplay"]',
      );
      if (forumLink != null) {
        boardName = sanitizeText(forumLink.text);
        boardUrl = forumLink.attributes['href'] ?? '';
        if (boardUrl.isNotEmpty) boardId = _extractBoardId(boardUrl);
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

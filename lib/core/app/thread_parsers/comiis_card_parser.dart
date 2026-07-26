import 'package:html/dom.dart' as dom;
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'thread_list_parser.dart';

/// 克米模板卡片式帖子列表解析器
///
/// 识别特征：`<li class="forumlist_li comiis_znalist ...">`
/// 适用场景：MT论坛 导读/板块/我的帖子（移动 UA）
///
/// DOM 结构：
/// ```html
/// <li class="forumlist_li comiis_znalist bg_f b_t b_b comiis_list_readimgs">
///   <div class="forumlist_li_top cl">          <!-- 用户信息 -->
///     <a class="wblist_tximg"><img src="avatar"></a>
///     <h2><a class="top_user">username</a><span class="top_lev">Lv.X</span></h2>
///     <div class="forumlist_li_time"><span>time</span></div>
///   </div>
///   <div class="mmlist_li_box cl">              <!-- 标题+摘要+图片 -->
///     <h2><a href="...">title</a></h2>
///     <div class="list_body cl"><a class="f_b">summary</a></div>
///     <div class="comiis_pyqlist_imgs"><ul><li><img src="..."></li></ul></div>
///   </div>
///   <div class="comiis_xznalist_bk cl">         <!-- 版块 -->
///     <a class="bg_g f_0">forum</a>
///   </div>
///   <div class="comiis_xznalist_bottom cl">     <!-- 统计 -->
///     <ul><li>likes</li><li>replies</li><li>views</li></ul>
///   </div>
/// </li>
/// ```
class ComiisCardParser implements ThreadListParser {
  @override
  bool canParse(dom.Document doc) {
    return doc.querySelector('li.forumlist_li.comiis_znalist') != null;
  }

  @override
  List<ThreadItem> parse(dom.Document doc) {
    final items = doc.querySelectorAll('li.forumlist_li.comiis_znalist');
    return items.map(_parseItem).toList();
  }

  ThreadItem _parseItem(dom.Element li) {
    // UID
    int? uid;
    final avatarLink = li.querySelector(
      'a.wblist_tximg, a[href*="space&uid="]',
    );
    final avatarHref = avatarLink?.attributes['href'];
    if (avatarHref != null) uid = _extractUid(avatarHref);

    // 昵称
    final nameEl = li.querySelector('.top_user, a[href*="space-username-"]');
    final nickname = sanitizeText(nameEl?.text);

    // 等级
    final levelEl = li.querySelector('.top_lev');
    final level = sanitizeText(levelEl?.text);

    // 时间
    final timeEl = li.querySelector(
      '.forumlist_li_time span, .forumlist_li_time',
    );
    final time = sanitizeText(timeEl?.text);

    // 关注链接
    final followEl = li.querySelector('a[href*="follow&op=add"]');
    final followUrl = followEl?.attributes['href'];

    // 标题
    String? title, summary, threadUrl;
    int? threadId;
    final titleEl = li.querySelector('.mmlist_li_box h2');
    if (titleEl != null) {
      final titleLink = titleEl.querySelector('a');
      if (titleLink != null) {
        title = sanitizeText(_cleanText(titleLink, excludeTags: {'span', 'i'}));
        threadUrl = titleLink.attributes['href'];
        threadId = _extractThreadId(threadUrl ?? '');
      }
      if (threadUrl != null && !threadUrl.startsWith('http')) {
        threadUrl = '${SiteStore.instance.baseUrl}/$threadUrl';
      }
      final summaryEl = li.querySelector('.list_body');
      if (summaryEl != null) summary = sanitizeText(summaryEl.text);
    } else {
      // 回退：无 h2，摘要内直接是链接
      final bodyLink = li.querySelector('.mmlist_li_box .list_body a');
      if (bodyLink != null) {
        title = sanitizeText(bodyLink.text);
        threadUrl = bodyLink.attributes['href'];
        threadId = _extractThreadId(threadUrl ?? '');
        if (threadUrl != null && !threadUrl.startsWith('http')) {
          threadUrl = '${SiteStore.instance.baseUrl}/$threadUrl';
        }
      }
    }

    // 版块
    final boardEl = li.querySelector(
      '.comiis_xznalist_bk a, .comiis_znalist_bk a, a[href*="forum-"], a[href*="forumdisplay"]',
    );
    final boardName = boardEl != null
        ? sanitizeText(
            _cleanText(
              boardEl,
              excludeTags: {'i'},
            ).replaceAll(RegExp(r'^[\s\u00a0]*来自?\s*'), ''),
          )
        : null;
    final boardUrl = boardEl?.attributes['href'];

    int? boardId;
    if (boardUrl != null) boardId = _extractBoardId(boardUrl);

    // 统计
    int? likes, comments, views;
    final bottomUl = li.querySelector('.comiis_xznalist_bottom');
    if (bottomUl != null) {
      final statLis = bottomUl.querySelectorAll('li');
      if (statLis.length >= 1) likes = _extractInt(statLis[0].text);
      if (statLis.length >= 2) comments = _extractInt(statLis[1].text);
      if (statLis.length >= 3) views = _extractInt(statLis[2].text);
    }

    // 图片
    List<String>? images;
    final imgContainer = li.querySelector(
      '.comiis_pyqlist_imgs, .comiis_pyqlist_img, .mmlist_li_box img',
    );
    if (imgContainer != null) {
      final imgs = imgContainer.querySelectorAll('img');
      if (imgs.isNotEmpty) {
        images = imgs
            .map(
              (img) =>
                  img.attributes['src'] ?? img.attributes['data-src'] ?? '',
            )
            .where((s) => s.isNotEmpty)
            .map(normalizeUrl)
            .toList();
      }
    }

    if (threadId == null && threadUrl != null) {
      threadId = _extractThreadId(threadUrl);
    }

    return ThreadItem(
      uid: uid,
      nickname: nickname,
      level: level,
      time: time,
      followUrl: followUrl,
      title: title,
      summary: summary,
      threadUrl: threadUrl,
      threadId: threadId,
      boardName: boardName,
      boardUrl: boardUrl,
      boardId: boardId,
      likes: likes,
      comments: comments,
      views: views,
      images: images,
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

  int? _extractInt(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.isEmpty ? null : int.parse(cleaned);
  }

  int? _extractBoardId(String url) {
    final m = RegExp(r'forum[_-](\d+)').firstMatch(url);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  String _cleanText(dom.Element el, {Set<String> excludeTags = const {}}) {
    final buf = StringBuffer();
    for (final node in el.nodes) {
      if (node is dom.Element && excludeTags.contains(node.localName)) continue;
      buf.write(node.text);
    }
    return buf.toString().trim();
  }
}

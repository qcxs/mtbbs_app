import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import '../models/thread_item.dart';
import 'package:mtbbs/core/site_store.dart';
import 'package:mtbbs/core/url_util.dart';
import 'page_helper.dart';

/// 解析帖子列表 HTML，返回 ThreadItem 列表。
/// 适用于导读、版块列表、搜索结果等。
List<ThreadItem> parseThreadList(String html) {
  final doc = htmlParser.parse(html);
  final items = doc.querySelectorAll('li.forumlist_li');
  return items.map(_parseItem).toList();
}

ThreadItem _parseItem(dom.Element li) {
  // UID
  int? uid;
  final avatarLink = li.querySelector('a.wblist_tximg, a[href*="space&uid="]');
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

  // 标题（排除 span/i 及其 title 属性的文本）
  String? title, summary, threadUrl;
  int? threadId;
  final titleEl = li.querySelector('.mmlist_li_box h2');
  if (titleEl != null) {
    // 标准模板：<div.mmlist_li_box><h2><a>标题</a></h2><div.list_body>摘要</div>
    // 注意：span/i 可能嵌套在 <a> 内部（精/热度等），需对 <a> 做清洗而非 h2
    final titleLink = titleEl.querySelector('a');
    if (titleLink != null) {
      title = sanitizeText(_cleanText(titleLink, excludeTags: {'span', 'i'}));
      threadUrl = titleLink.attributes['href'];
      threadId = _extractThreadId(threadUrl ?? '');
    }
    if (threadUrl != null && !threadUrl.startsWith('http')) {
      threadUrl = '${SiteStore.instance.baseUrl}/$threadUrl';
    }
    // 摘要（独立于标题）
    final summaryEl = li.querySelector('.list_body');
    if (summaryEl != null) summary = sanitizeText(summaryEl.text);
  } else {
    // 我的帖子模板：无 h2，<div.mmlist_li_box><div.list_body><a>标题</a></div>
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

  // 版块（排除 i 字体图标文本）
  // 优先标准版块链接，其次 time div 内的 forumdisplay 链接（部分模板）
  final boardEl = li.querySelector(
    '.comiis_znalist_bk a, a[href*="forum-"], a[href*="forumdisplay"]',
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

  // 版块 ID
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

  // 图片（确保返回绝对 URL）
  List<String>? images;
  final imgContainer = li.querySelector(
    '.comiis_pyqlist_imgs, .comiis_pyqlist_img, .mmlist_li_box img',
  );
  if (imgContainer != null) {
    final imgs = imgContainer.querySelectorAll('img');
    if (imgs.isNotEmpty) {
      images = imgs
          .map(
            (img) => img.attributes['src'] ?? img.attributes['data-src'] ?? '',
          )
          .where((s) => s.isNotEmpty)
          .map(normalizeUrl)
          .toList();
    }
  }

  if (threadId == null && threadUrl != null)
    threadId = _extractThreadId(threadUrl);

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

/// 从版块 URL（如 forum-40-1.html）中提取 fid。
int? _extractBoardId(String url) {
  final m = RegExp(r'forum[_-](\d+)').firstMatch(url);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// 获取元素文本，排除指定标签的子元素（如 span 的 title、i 的字体图标等）
///
/// 只取直接子节点中的文本，跳过匹配 [excludeTags] 的元素节点。
String _cleanText(dom.Element el, {Set<String> excludeTags = const {}}) {
  final buf = StringBuffer();
  for (final node in el.nodes) {
    if (node is dom.Element && excludeTags.contains(node.localName)) continue;
    buf.write(node.text);
  }
  return buf.toString().trim();
}

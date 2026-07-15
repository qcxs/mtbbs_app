import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/xml_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 排行榜条目
class RankItem {
  final int rank;
  final String title;
  final String tid;
  final String threadUrl;
  final String forumName;
  final String forumUrl;
  final String author;
  final String authorUid;
  final String authorUrl;
  final String time;
  final String count;

  const RankItem({
    required this.rank,
    required this.title,
    required this.tid,
    required this.threadUrl,
    required this.forumName,
    required this.forumUrl,
    required this.author,
    required this.authorUid,
    required this.authorUrl,
    required this.time,
    required this.count,
  });

  Map<String, dynamic> toMap() => {
    'rank': rank,
    'title': title,
    'tid': tid,
    'threadUrl': threadUrl,
    'forumName': forumName,
    'forumUrl': forumUrl,
    'author': author,
    'authorUid': authorUid,
    'authorUrl': authorUrl,
    'time': time,
    'count': count,
  };
}

/// 解析排行榜响应
///
/// 响应格式：XML CDATA 包裹的 HTML。
/// 支持两种模板：
///   1. 桌面 PC 模板（MT 论坛）：`<table><tr><td class="icn"><th><td class="frm"><td class="by"><td>`
///   2. 移动 App 模板（克米模板）：`<div class="comiis_postphb"><ul><li><div class="postphb_mun"><a class="postphb_tit"><p>`
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  // 解析 XML CDATA
  final xmlResult = parseInajaxXml(body);
  if (xmlResult == null || xmlResult.cdataHtml.isEmpty) {
    AppLogger.w('PARSE', 'ranklist: failed to parse XML CDATA');
    return {'success': false, 'message': '解析 XML 失败'};
  }

  final html = xmlResult.cdataHtml;
  final doc = htmlParser.parse(html);

  // 先过统一错误检测
  final pageError = checkPageError(doc, html);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  // 尝试两种解析策略
  var items = _parseTable(doc);
  if (items.isEmpty) {
    items = _parseLiList(doc);
  }

  AppLogger.i('PARSE', 'ranklist: ${items.length} items');
  if (items.isNotEmpty) {
    final show = items.length > 3 ? items.take(3).toList() : items;
    AppLogger.list(
      'PARSE',
      show,
      show.length,
      labelFn: (RankItem e) => jsonEncode(e.toMap()),
      summary: items.length > 3 ? 'top 3' : '',
    );
  }

  return {'success': true, 'items': items.map((e) => e.toMap()).toList()};
}

// ==================== 策略1：桌面 PC 模板（table 结构） ====================
//
// <table>
//   <tr class="th">...</tr>  ← 跳过头行
//   <tr>
//     <td class="icn"><img src="rank_1.gif" alt="1" />或纯数字</td>
//     <th><a href="thread-xxx-1-1.html">标题</a></th>
//     <td class="frm"><a href="forum-xx-1.html">版块</a></td>
//     <td class="by"><cite><a href="space-uid-xxx.html">作者</a></cite><em>时间</em></td>
//     <td><a href="thread-xxx-1-1.html" class="xi2">数值</a></td>
//   </tr>
// </table>

List<RankItem> _parseTable(dom.Document doc) {
  final rows = doc.querySelectorAll('table tr:not(.th)');
  if (rows.isEmpty) return [];

  final items = <RankItem>[];
  for (final row in rows) {
    final th = row.querySelector('th');
    final icnTd = row.querySelector('td.icn');
    final frmTd = row.querySelector('td.frm');
    final byTd = row.querySelector('td.by');
    final allTds = row.querySelectorAll('td');
    final countTd = allTds.length >= 5 ? allTds.last : null;

    if (th == null) continue;

    // 排名
    final rank = _parseRankFromImg(icnTd);

    // 标题 + URL
    final titleLink = th.querySelector('a');
    final title = _text(titleLink);
    final threadUrl = titleLink?.attributes['href'] ?? '';
    final tid = _extractTid(threadUrl);

    // 版块
    final forumLink = frmTd?.querySelector('a');
    final forumName = _text(forumLink);
    final forumUrl = forumLink?.attributes['href'] ?? '';

    // 作者
    final citeLink = byTd?.querySelector('cite a');
    final author = _text(citeLink);
    final authorUrl = citeLink?.attributes['href'] ?? '';
    final authorUid = _extractUid(authorUrl);
    final timeEl = byTd?.querySelector('em');
    final time = _text(timeEl);

    // 统计值
    final countLink = countTd?.querySelector('a');
    final count = _text(countLink ?? countTd);

    items.add(
      RankItem(
        rank: rank,
        title: title,
        tid: tid,
        threadUrl: threadUrl,
        forumName: forumName,
        forumUrl: forumUrl,
        author: author,
        authorUid: authorUid,
        authorUrl: authorUrl,
        time: time,
        count: count,
      ),
    );
  }
  return items;
}

// ==================== 策略2：移动 App 模板（li 列表结构） ====================
//
// <div class="comiis_postphb">
//   <ul>
//     <li class="b_t">
//       <div class="postphb_mun"><img src="comiis_rank1.png" alt="1" />或纯数字</div>
//       <a href="forum.php?mod=viewthread&tid=14" class="postphb_tit">标题</a>
//       <p>
//         <span class="y f_d">8回复</span>
//         <a href="home.php?mod=space&uid=2" class="f_ok"><img src="avatar">作者</a>
//         <span class="f_d">2026-7-10 16:38</span>
//       </p>
//     </li>
//   </ul>
// </div>

List<RankItem> _parseLiList(dom.Document doc) {
  final lis = doc.querySelectorAll('.comiis_postphb li, .comiis_postphb ul li');
  if (lis.isEmpty) return [];

  final items = <RankItem>[];
  for (final li in lis) {
    // 排名
    final munDiv = li.querySelector('.postphb_mun');
    final rank = _parseRankFromImg(munDiv);

    // 标题 + URL
    final titleLink = li.querySelector('a.postphb_tit');
    final title = _text(titleLink);
    final threadUrl = titleLink?.attributes['href'] ?? '';
    final tid = _extractTid(threadUrl);

    // 作者信息（p 标签内）
    final pEl = li.querySelector('p');
    final authorLink = pEl?.querySelector('a.f_ok');
    final author = _text(authorLink);
    final authorUrl = authorLink?.attributes['href'] ?? '';
    final authorUid = _extractUid(authorUrl);

    // 时间：p 标签内最后一个 span.f_d
    final time = (() {
      final spans = pEl?.querySelectorAll('span.f_d');
      if (spans != null && spans.length >= 2) return _text(spans.last);
      return '';
    })();

    // 统计值：从 span.y f_d 中提取数字（如 "8回复"）
    final countSpan = pEl?.querySelector('span.y');
    final count = _extractCount(_text(countSpan));

    items.add(
      RankItem(
        rank: rank,
        title: title,
        tid: tid,
        threadUrl: threadUrl,
        forumName: '',
        forumUrl: '',
        author: author,
        authorUid: authorUid,
        authorUrl: authorUrl,
        time: time,
        count: count,
      ),
    );
  }
  return items;
}

// ==================== 通用工具 ====================

/// 从元素中解析排名：优先取 img.alt，否则取纯文本
int _parseRankFromImg(dom.Element? el) {
  if (el == null) return 0;
  final img = el.querySelector('img');
  if (img != null) {
    final alt = img.attributes['alt'] ?? '';
    return int.tryParse(alt) ?? 0;
  }
  return int.tryParse(el.text.trim()) ?? 0;
}

/// 从 thread URL 提取 tid
String _extractTid(String url) {
  final m = RegExp(r'thread-(\d+)').firstMatch(url);
  if (m != null) return m.group(1)!;
  final uri = Uri.tryParse(url);
  return uri?.queryParameters['tid'] ?? '';
}

/// 从 space URL 提取 uid
String _extractUid(String url) {
  final m = RegExp(r'space-uid-(\d+)').firstMatch(url);
  if (m != null) return m.group(1)!;
  final uri = Uri.tryParse(url);
  return uri?.queryParameters['uid'] ?? '';
}

/// 从 "8回复" 中提取数字
String _extractCount(String text) {
  final m = RegExp(r'(\d+)').firstMatch(text);
  return m?.group(1) ?? text;
}

String _text(dom.Element? el) => el?.text.trim() ?? '';

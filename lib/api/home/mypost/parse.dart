import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/parser/notice_segments.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 我的帖子 HTML 解析
///
/// 解析 home.php?mod=space&do=notice&view=mypost&type=post 页面，
/// 提取帖子提醒列表和分页信息。
///
/// 正文的结构化段落由 [extractNoticeSegments] 统一产出（与系统提醒/管理工作
/// 同一份实现），本文件只额外提取「预览 / 回复」需要的 tid/pid 相关字段。
///
/// 每条提醒的 DOM 结构：
/// ```html
/// <dl class="cl" notice="6744379" id="notice_6744379">
///   <dd class="m avt mbn">
///     <a href="https://bbs.binmt.cc/space-uid-16205.html">
///       <img src="...avatar...">
///     </a>
///   </dd>
///   <dt>
///     <span class="xg1 xw0"><span title="2026-7-19 14:53">半小时前</span></span>
///   </dt>
///   <dd class="ntc_body">
///     <a href="...space-uid-xxx.html">精神小伙</a> 回复了您的帖子
///     <a href="...ptid=xxx&pid=xxx">帖子标题</a> &nbsp;
///     <a href="...pid=xxx&ptid=xxx" class="lit">查看</a>
///   </dd>
/// </dl>
/// ```

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final items = <Map<String, dynamic>>[];
  final dls = doc.querySelectorAll('dl[id^="notice_"]');

  for (final dl in dls) {
    final item = _parseItem(dl);
    if (item != null) items.add(item);
  }

  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'items': items,
    'count': items.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
    // 页面自带导航：站点实际有哪些视图 / 子类型（用于裁剪 Tab，与 notice/parse 同源）
    'nav': parseNoticeNav(doc),
  };
}

Map<String, dynamic>? _parseItem(dom.Element dl) {
  try {
    // 头像链接 → uid
    final uid = noticeAvatarUid(dl);

    // ntc_body 中的解析
    final bodyEl = dl.querySelector('dd.ntc_body');
    if (bodyEl == null) return null;

    // 保留完整 HTML 供内联渲染
    final bodyHtml = bodyEl.nodes.map((n) {
      if (n is dom.Element) return n.outerHtml;
      if (n is dom.Text) return n.text;
      return n.toString();
    }).join();

    final segments = extractNoticeSegments(bodyEl);

    // 用户名：ntc_body 中的第一个链接
    final username = sanitizeText(bodyEl.querySelector('a')?.text ?? '');

    // 帖子标题 + 查看链接
    String threadTitle = '';
    String viewUrl = '';
    for (final a in bodyEl.querySelectorAll('a[target="_blank"]')) {
      final href = a.attributes['href'] ?? '';
      if (a.classes.contains('lit')) {
        viewUrl = href;
      } else if (threadTitle.isEmpty) {
        threadTitle = sanitizeText(a.text);
      }
    }

    // 兜底 viewUrl
    if (viewUrl.isEmpty) {
      for (final a in bodyEl.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        if (href.contains('goto=findpost') && href.contains('pid=')) {
          viewUrl = href;
        }
      }
    }

    final time = noticeTime(dl);

    return {
      'uid': uid,
      'username': username,
      'threadTitle': threadTitle,
      'viewUrl': viewUrl,
      'bodyHtml': bodyHtml,
      'time': time.text,
      'timeTitle': time.title,
      'fromNum': noticeHasFromNum(dl),
      // segments：结构化段落供 UI 直接渲染，无需 HTML 解析
      'segments': segments,
    };
  } catch (e) {
    AppLogger.w('PARSE', 'mypost item parse error: $e');
    return null;
  }
}

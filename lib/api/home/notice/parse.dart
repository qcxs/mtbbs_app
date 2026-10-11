import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/parser/notice_segments.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 提醒 HTML 解析（`do=notice` 各视图通用）
///
/// 解析 `home.php?mod=space&do=notice&view={system|manage|interactive|mypost}` 页面
/// ——各视图共用同一张模板与 DOM 结构，差别只在正文内容：
/// - `system`：评分 / 操作等系统通知
/// - `manage`：管理工作待办（正文是 `admin.php` 处理链接），或举报处理反馈
///   （正文含 `space-uid-` 用户链接，并以 `<br>` 分行）
/// - `interactive`：坛友互动（留言 / 打招呼 / 好友…）
///
/// 条目正文千变万化（几十套消息模板），统一交给
/// [extractNoticeSegments] 递归解析，避免任一类模板丢内容。
///
/// 每条提醒的 DOM 结构：
/// ```html
/// <dl class="cl" notice="6739069" id="notice_6739069">
///   <dd class="m avt mbn">
///     <img src="...systempm.png" alt="systempm">
///   </dd>
///   <dt>
///     <span class="xg1 xw0"><span title="2026-7-16 04:50">3 天前</span></span>
///   </dt>
///   <dd class="ntc_body">
///     您在主题 <a href="...ptid=169295" target="_blank">帖子标题</a> 的帖子被
///     <a href="...space-uid-xxx.html">用户名</a> 评分 金币 +1
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
    // 页面自带导航：站点实际有哪些视图 / 子类型（用于裁剪 Tab，见 parseNoticeNav）
    'nav': parseNoticeNav(doc),
  };
}

Map<String, dynamic>? _parseItem(dom.Element dl) {
  try {
    final id = dl.attributes['id'] ?? '';
    final noticeId = id.startsWith('notice_') ? id.substring(7) : '';
    final time = noticeTime(dl);

    // 对方头像 uid（interactive/mypost 是对方头像；system/manage 为系统图标 → 空）
    final avatarUid = noticeAvatarUid(dl);

    final bodyEl = dl.querySelector('dd.ntc_body');
    if (bodyEl == null) return null;

    // 保留完整 bodyHtml（含 quote 留言）供内联渲染
    final bodyHtml = bodyEl.nodes.map((n) {
      if (n is dom.Element) return n.outerHtml;
      if (n is dom.Text) return n.text;
      return n.toString();
    }).join();

    final segments = extractNoticeSegments(bodyEl);

    // 纯文本兜底（去掉 quote 内容），供旧字段使用
    final bodyTextClone = bodyEl.clone(true);
    bodyTextClone
        .querySelectorAll('.quote, blockquote')
        .forEach((e) => e.remove());
    final fullText = sanitizeText(bodyTextClone.text);

    // 用户名 / uid / 帖子链接：从结构化段落里回取，避免与渲染口径不一致
    String username = '';
    String userUid = '';
    String threadTitle = '';
    String threadUrl = '';
    for (final seg in segments) {
      final type = seg['type'] as String?;
      if (type == 'user') {
        if (username.isEmpty) {
          username = seg['text'] as String? ?? '';
          userUid = seg['uid'] as String? ?? '';
        }
      } else if (type == 'thread' && threadUrl.isEmpty) {
        threadUrl = seg['url'] as String? ?? '';
        threadTitle = seg['text'] as String? ?? '';
      }
    }

    return {
      'noticeId': noticeId,
      'time': time.text,
      'timeTitle': time.title,
      'message': fullText,
      'bodyHtml': bodyHtml,
      'segments': segments,
      'avatarUid': avatarUid,
      'fromNum': noticeHasFromNum(dl),
      // 兼容字段（同一条正文，旧调用方仍在读）
      'threadTitle': threadTitle,
      'threadUrl': threadUrl,
      'username': username,
      'userUid': userUid,
    };
  } catch (e) {
    AppLogger.w('PARSE', 'notice item parse error: $e');
    return null;
  }
}

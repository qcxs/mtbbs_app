import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 用户留言板（`home.php?mod=space&uid={uid}&do=wall`）HTML 解析
///
/// 只解析 **PC 模板**。DOM 结构（实测 bbs.binmt.cc）：
/// ```html
/// <div id="comment_ul" class="xld xlda">
///   <dl id="comment_{cid}_li" class="bbda cl">
///     <dd class="m avt"><a href="space-uid-{uid}.html"><img src="avatar"></a></dd>
///     <dt>
///       <span class="y xw0">
///         <a id="c_{cid}_edit"   href="...op=edit&cid={cid}&handlekey=editcommenthk_{cid}">编辑</a>
///         <a id="c_{cid}_delete" href="...op=delete&cid={cid}&handlekey=delcommenthk_{cid}">删除</a>
///         <a id="c_{cid}_reply"  href="...op=reply&cid={cid}&handlekey=replycommenthk_{cid}">回复</a>
///       </span>
///       <a href="space-uid-{uid}.html" id="author_{cid}">{昵称}</a>
///       <span class="xg1 xw0">{时间}</span>
///     </dt>
///     <dd id="comment_{cid}">
///       <!-- 回复他人时服务端注入引用块： -->
///       <div class="quote"><blockquote><b>{被引作者}</b>: {被引内容}</blockquote></div>{正文}
///     </dd>
///   </dl>
///   ...
/// </div>
/// ```
///
/// 权限差异（**按实际存在的操作链接判定，不写死**）：
/// - 自己的留言板：所有人的留言都有「删除/回复」，自己的额外有「编辑」
/// - 他人的留言板：操作链接全部隐藏（顶部留言框仍在）
///
/// 正文回退为 BBCode（服务端已把受限 BBCode 白名单 `[b][i][u][quote][img]`
/// 与裸 URL 渲染成 HTML），交渲染层走统一管线（见 docs/02 数据层 ↔ 渲染层边界）。
///
/// 分页复用 [extractPagination]（`.pg`，每页 20 条）。
Map<String, dynamic> parseWallPage(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final comments = <Map<String, dynamic>>[];
  for (final dl in doc.querySelectorAll('#comment_ul dl[id^="comment_"]')) {
    final c = _parseComment(dl);
    if (c != null) comments.add(c);
  }

  // formhash：一页共用一个，发布/回复/编辑/删除都用它
  final formhash =
      doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '';

  // 顶部留言框存在 = 当前登录用户可以在该墙留言
  final canPost = doc.querySelector('form[id^="quickcommentform_"]') != null;

  // 容器缺失 = 页面结构变更（区别于"墙为空"：空墙仍有 #comment_ul）
  final hasList = doc.querySelector('#comment_ul') != null;

  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'comments': comments,
    'count': comments.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'hasMore': currentPage < totalPages,
    'formhash': formhash,
    'canPost': canPost,
    '_health': {
      'parser': 'wall',
      'missing': [
        if (!hasList) 'comment_ul（页面结构可能变更）',
        if (formhash.isEmpty) 'formhash（需登录）',
      ],
    },
  };
}

/// 解析单条留言
Map<String, dynamic>? _parseComment(dom.Element dl) {
  try {
    final cid = (RegExp(
      r'comment_(\d+)_li',
    ).firstMatch(dl.attributes['id'] ?? '')?.group(1));
    if (cid == null) return null;

    final avatar = dl.querySelector('dd.m.avt img')?.attributes['src'] ?? '';

    // 作者：dt 内的 <a id="author_{cid}">
    final authorLink =
        dl.querySelector('a[id="author_$cid"]') ?? dl.querySelector('dt a');
    final authorName = sanitizeText(authorLink?.text ?? '');
    final authorHref = authorLink?.attributes['href'] ?? '';
    final authorUid =
        RegExp(r'space-uid-(\d+)').firstMatch(authorHref)?.group(1) ?? '';

    // 时间：dt 内作者名后的 span.xg1.xw0
    final time = sanitizeText(dl.querySelector('span.xg1.xw0')?.text ?? '');

    // 操作权限：按实际存在的链接判定
    final canEdit = dl.querySelector('a[id="c_${cid}_edit"]') != null;
    final canDelete = dl.querySelector('a[id="c_${cid}_delete"]') != null;
    final canReply = dl.querySelector('a[id="c_${cid}_reply"]') != null;

    // 正文（含可能的引用块）
    String message = '';
    String quotedUser = '';
    String quotedText = '';
    final contentDd = dl.querySelector('dd[id="comment_$cid"]');
    if (contentDd != null) {
      final clone = contentDd.clone(true);
      final quote = clone.querySelector('.quote');
      if (quote != null) {
        final bq = quote.querySelector('blockquote');
        if (bq != null) {
          quotedUser = sanitizeText(bq.querySelector('b')?.text ?? '');
          final bqClone = bq.clone(true);
          bqClone.querySelector('b')?.remove();
          quotedText = sanitizeText(
            bqClone.text,
          ).replaceFirst(RegExp(r'^[:：]\s*'), '');
        }
        quote.remove();
      }
      message = Html2BBCode().convertElementContent(clone);
    }

    return {
      'cid': cid,
      'authorUid': authorUid,
      'authorName': authorName,
      'avatar': avatar,
      'time': time,
      'message': message,
      'quotedUser': quotedUser,
      'quotedText': quotedText,
      'canEdit': canEdit,
      'canDelete': canDelete,
      'canReply': canReply,
    };
  } catch (e) {
    AppLogger.w('PARSE', 'wall comment parse error: $e');
    return null;
  }
}

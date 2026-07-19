import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 私人消息列表 HTML 解析
///
/// 解析 home.php?mod=space&do=pm&filter=privatepm 页面，
/// 提取消息列表和分页信息。
///
/// 每条消息的 DOM 结构：
/// ```html
/// <dl id="pmlist_48846" class="bbda cur1 cl newpm">
///   <dd class="m avt">
///     <div class="newpm_avt" title="有未读消息"></div>
///     <a href="...space-uid-152009.html"><img src="...avatar..."></a>
///   </dd>
///   <dd class="ptm pm_c">
///     <div class="o">
///       <input type="checkbox" name="deletepm_deluid[]" value="152009">
///     </div>
///     <a href="...space-uid-152009.html" class="xw1">qcxs</a> 对 <span class="xi2">您</span> 说 :<br>
///     消息内容<br>
///     <span class="xg1"><span title="2026-7-19 15:25">19 秒前</span></span>
///     <span class="pm_o y">
///       <span class="xg1 z">共 13 条</span>
///       <a href="...subop=view&touid=152009#last" id="pmlist_48846_a">回复</a>
///     </span>
///   </dd>
/// </dl>
/// ```

/// 解析 PM 列表页 HTML，返回结构化数据
Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = html_parser.parse(body);

  // 统一检测 Discuz 错误页
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  // 提取消息列表
  final items = <Map<String, dynamic>>[];
  final dls = doc.querySelectorAll('dl[id^="pmlist_"]');

  for (final dl in dls) {
    final item = _parsePmItem(dl);
    if (item != null) items.add(item);
  }

  // 提取分页信息
  final pagination = extractPagination(doc);
  final currentPage = pagination['currentPage'] ?? 1;
  final totalPages = pagination['totalPages'] ?? 1;

  AppLogger.i(
    'PARSE',
    'pm list: ${items.length} items, page $currentPage/$totalPages',
  );

  return {
    'success': true,
    'items': items,
    'count': items.length,
    'currentPage': currentPage,
    'totalPages': totalPages,
  };
}

/// 解析单条 PM 消息项
Map<String, dynamic>? _parsePmItem(dom.Element dl) {
  try {
    final idAttr = dl.attributes['id'] ?? '';
    final plid = idAttr.startsWith('pmlist_') ? idAttr.substring(7) : '';

    // 未读状态：仅通过 dl 的 newpm class 判断
    final hasNewpm = dl.classes.contains('newpm');

    // 头像
    final avatarImg = dl.querySelector('dd.avt img');
    final avatar = avatarImg?.attributes['src'] ?? '';

    // 头像链接 → uid
    final avatarLink = dl.querySelector('dd.avt a');
    final avatarHref = avatarLink?.attributes['href'] ?? '';
    final uidMatch = RegExp(r'uid[=-](\d+)').firstMatch(avatarHref);
    final uid = uidMatch?.group(1) ?? '';

    // 用户名（发送者或接收者）
    // 两种模式：
    //   <a class="xw1">用户名</a> 对 您 说   → 别人发的
    //   <span class="xi2 xw1">您</span> 对 <a>用户名</a> 说  → 自己发的
    final pmC = dl.querySelector('dd.pm_c');
    if (pmC == null) return null;

    final xw1Link = pmC.querySelector('a.xw1');
    final isIncoming = xw1Link != null;
    String username;
    if (isIncoming) {
      username = sanitizeText(xw1Link.text);
    } else {
      // 自己发的：取 "您 对 <a>xxx</a> 说" 中的 a
      final targetLink = pmC.querySelector('a');
      username = sanitizeText(targetLink?.text ?? '');
    }

    // 获取 pm_c 的纯文本，用于提取最后一条消息
    final pmClone = pmC.clone(true);
    // 移除嵌套元素（o, pm_o, script）
    pmClone
        .querySelectorAll('.o, .pm_o, .xg1, script')
        .forEach((e) => e.remove());
    // 提取 <br> 后的第一段文本作为最后一条消息
    final br = pmClone.querySelector('br');
    String lastMessage = '';
    if (br != null) {
      final parent = br.parent;
      if (parent != null) {
        final children = parent.nodes;
        final brIndex = children.indexOf(br);
        for (int i = brIndex + 1; i < children.length; i++) {
          final node = children[i];
          if (node is dom.Text) {
            final text = sanitizeText(node.text);
            if (text.isNotEmpty) {
              lastMessage = text;
              break;
            }
          } else {
            // 遇到元素节点停止
            break;
          }
        }
      }
    }

    // 消息总数 "共 N 条"
    final countSpan = pmC.querySelector('.xg1.z');
    final countText = sanitizeText(countSpan?.text ?? '');
    final countMatch = RegExp(r'共\s*(\d+)\s*条').firstMatch(countText);
    final messageCount = countMatch?.group(1) ?? '';

    // 时间
    final timeSpan = pmC.querySelector('span.xg1');
    String time;
    if (timeSpan != null) {
      // 优先取 span[title]（相对时间）
      final innerSpan = timeSpan.querySelector('span[title]');
      time = innerSpan?.attributes['title'] ?? sanitizeText(timeSpan.text);
    } else {
      time = '';
    }

    // 回复链接：查找 id 以 _a 结尾的 a 标签
    dom.Element? replyLink;
    for (final a in dl.querySelectorAll('a[id]')) {
      final id = a.attributes['id'] ?? '';
      if (id.endsWith('_a')) {
        replyLink = a;
        break;
      }
    }
    final replyUrl = replyLink?.attributes['href'] ?? '';

    return {
      'plid': plid,
      'uid': uid,
      'username': username,
      'avatar': avatar,
      'isNew': hasNewpm,
      'lastMessage': lastMessage,
      'messageCount': messageCount,
      'time': time,
      'replyUrl': replyUrl,
      'isIncoming': isIncoming,
    };
  } catch (e) {
    AppLogger.w('PARSE', 'pm item parse error: $e');
    return null;
  }
}

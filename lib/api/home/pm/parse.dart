import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/utils/logger.dart';

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
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

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

// ============================================================
// 会话详情（home.php?mod=space&do=pm&subop=view&touid=X）
// ============================================================

/// 解析私信会话详情页，提取对方信息、消息列表、分页与 formhash。
///
/// 页面结构（PC 模板，discuz.qcxs.top 与 bbs.binmt.cc 实测一致）：
/// ```html
/// <div class="tbmu pml pm_op_r cl">
///   <div class="xw1">共有 <span id="membernum" class="xi1">N</span> 条与
///     <a href="home.php?mod=space&uid=1">admin</a> 的交谈记录 …</div>
/// </div>
/// <div id="pm_ul" class="xld xlda mbm pml">
///   <a name="last"></a>
///   <dl id="pmlist_123" class="bbda cl">
///     <dd class="y mtm pm_o">…（删除菜单）…</dd>
///     <dd class="m avt" id="bottom"><a href="…uid=2"><img src="avatar"></a></dd>
///     <dd class="ptm">
///       <span class="xi2 xw1">您</span> &nbsp;              ← 自己发的
///       <!-- 对方发的则是： --> <a href="…uid=1" class="xw1">admin</a>
///       <br>{discuzcode 渲染后的 HTML 正文}<br>
///       <span class="xg1"><span title="2026-10-2 16:38">2 秒前</span></span>
///     </dd>
///   </dl>
///   <div id="pm_append"></div>
/// </div>
/// ```
/// - 正文用 [Html2BBCode] 还原为 BBCode（服务端经 UCenter `uccode` 已把
///   `[b]`/`[color]`/`[url]`/`[img]` 等渲染成 HTML，与帖子同源，见 docs/02）。
/// - 会话为空时 `#pm_ul` 与回复表单都不渲染，靠 [extractFormhash] 从
///   `op=showmsg` 页取 formhash。
Map<String, dynamic> parsePmView(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  // 对方信息（头部「共有 N 条与 <a>username</a> 的交谈记录」）
  String uid = '';
  String username = '';
  final header = doc.querySelector('.tbmu.pml') ?? doc.querySelector('.tbmu');
  if (header != null) {
    final link = _findUserLink(header);
    if (link != null) {
      uid = _uidFromHref(link.attributes['href'] ?? '');
      username = sanitizeText(link.text);
    }
  }
  final membernumText = sanitizeText(
    doc.querySelector('#membernum')?.text ?? '',
  );

  // 消息列表
  final items = <Map<String, dynamic>>[];
  for (final dl in doc.querySelectorAll('#pm_ul dl[id^="pmlist_"]')) {
    final item = _parseViewItem(dl);
    if (item != null) items.add(item);
  }

  // 对方头像：取第一条「非自己发的」消息的头像
  String avatar = '';
  for (final it in items) {
    if (it['isMine'] != true && (it['avatar'] as String).isNotEmpty) {
      avatar = it['avatar'] as String;
      break;
    }
  }

  // formhash（回复表单隐藏域，用于发送）
  final formhash =
      doc
          .querySelector('#pm_ul_post input[name="formhash"]')
          ?.attributes['value'] ??
      doc.querySelector('input[name="formhash"]')?.attributes['value'] ??
      '';

  // 分页：pmmulti 只输出「上一页/下一页」链接（无页码、无总数），
  // 因此直接取相邻页号：上一页 = 更旧，下一页 = 更新（page 从最旧 1 递增到最新）。
  final pg = doc.querySelector('.pg');
  int olderPage = 0;
  int newerPage = 0;
  if (pg != null) {
    for (final a in pg.querySelectorAll('a')) {
      final m = RegExp(
        r'[?&]page=(\d+)',
      ).firstMatch(a.attributes['href'] ?? '');
      if (m == null) continue;
      final p = int.tryParse(m.group(1)!) ?? 0;
      final text = sanitizeText(a.text);
      // 注意「上一页」不含连续子串「上页」（中间隔着「一」），需按整词匹配
      if (text.contains('上一页') || text.contains('上页')) {
        olderPage = p;
      } else if (text.contains('下一页') || text.contains('下页')) {
        newerPage = p;
      }
    }
  }

  return {
    'success': true,
    'uid': uid,
    'username': username,
    'avatar': avatar,
    'items': items,
    'count': items.length,
    'totalCount': int.tryParse(membernumText) ?? items.length,
    // 请求「最新页」时 olderPage 即上一页页码；0 表示没有更旧的消息
    'olderPage': olderPage,
    'newerPage': newerPage,
    'hasOlder': olderPage > 0,
    'formhash': formhash,
    '_health': {
      'parser': 'pm_view',
      'missing': [
        if (uid.isEmpty) 'uid',
        if (username.isEmpty) 'username',
        if (formhash.isEmpty) 'formhash',
      ],
    },
  };
}

/// 解析会话里的单条消息
Map<String, dynamic>? _parseViewItem(dom.Element dl) {
  try {
    final idAttr = dl.attributes['id'] ?? '';
    final pmid = idAttr.startsWith('pmlist_') ? idAttr.substring(7) : '';
    final ptm = dl.querySelector('dd.ptm');
    if (ptm == null) return null;

    // 发送者 uid / 头像：来自 dd.m.avt 的头像链接
    final avatarLink = dl.querySelector('dd.m.avt a');
    final senderUid = _uidFromHref(avatarLink?.attributes['href'] ?? '');
    final avatar = dl.querySelector('dd.m.avt img')?.attributes['src'] ?? '';

    // 是否自己发的：模板条件 authorid == 当前 uid 时渲染 <span class="xi2 xw1">您</span>
    final isMine = ptm.querySelector('span.xi2.xw1') != null;
    final senderName = isMine
        ? ''
        : sanitizeText(ptm.querySelector('a.xw1')?.text ?? '');

    // 时间：优先 span.xg1 内 span[title] 的绝对时间
    final timeSpan = ptm.querySelector('span.xg1');
    final time =
        timeSpan?.querySelector('span[title]')?.attributes['title'] ??
        sanitizeText(timeSpan?.text ?? '');

    return {
      'pmid': pmid,
      'isMine': isMine,
      'senderUid': senderUid,
      'senderName': senderName,
      'avatar': avatar,
      'bbcode': _extractMessageBbcode(ptm),
      'time': time,
    };
  } catch (e) {
    AppLogger.w('PARSE', 'pm view item parse error: $e');
    return null;
  }
}

/// 从 `dd.ptm` 中还原消息正文的 BBCode。
///
/// `dd.ptm` 的结构固定为「作者前缀 + `<br>` + 正文 + `<br>` + 时间」，
/// 因此去掉末尾时间、去掉首个 `<br>` 及其之前的作者前缀、再去掉一个
/// 收尾 `<br>`，剩下的就是正文。用 DOM 节点操作而非字符串切割，
/// 避免正文自带的 `<br>`/转义干扰。
String _extractMessageBbcode(dom.Element ptm) {
  final clone = ptm.clone(true);
  // 去掉时间节点
  clone.querySelectorAll('span.xg1').forEach((e) => e.remove());

  // 去掉作者前缀（一直到第一个 <br> 为止，含该 <br>）
  final prefix = <dom.Node>[];
  for (final n in clone.nodes) {
    prefix.add(n);
    if (n is dom.Element && n.localName == 'br') break;
  }
  for (final n in prefix) {
    n.remove();
  }

  // 去掉收尾的空白文本与一个布局 <br>
  final tail = clone.nodes.toList();
  for (int i = tail.length - 1; i >= 0; i--) {
    final n = tail[i];
    if (n is dom.Text && n.text.trim().isEmpty) {
      n.remove();
      continue;
    }
    if (n is dom.Element && n.localName == 'br') n.remove();
    break;
  }

  return Html2BBCode().convertElementContent(clone);
}

/// 从任意页面提取 formhash（Discuz 一个页面共用一个）
String extractFormhash(String body) {
  final doc = html_parser.parse(body);
  return doc.querySelector('input[name="formhash"]')?.attributes['value'] ?? '';
}

/// 在容器内找到指向用户空间（`uid=N` / `space-uid-N`）的链接
dom.Element? _findUserLink(dom.Element container) {
  for (final a in container.querySelectorAll('a')) {
    if (_uidFromHref(a.attributes['href'] ?? '').isNotEmpty) return a;
  }
  return null;
}

/// 从 href 提取用户 uid。
///
/// 只认用户空间链接的两种写法（`mod=space&uid=N` / `space-uid-N.html`），
/// 不能只匹配 `uid=N`——删除菜单等链接（`…&deletepm_deluid[]=1&uid=1`）也含 `uid=`。
String _uidFromHref(String href) {
  final m1 = RegExp(r'mod=space&uid=(\d+)').firstMatch(href);
  if (m1 != null) return m1.group(1)!;
  final m2 = RegExp(r'space-uid-(\d+)').firstMatch(href);
  return m2?.group(1) ?? '';
}

import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/url_util.dart';

/// 从 table#pidXX.plhin（PC 模板）提取单帖完整数据
///
/// 两个消费者共用此函数：
/// - getThreadDetail（detail/parse.dart）：解析帖子详情页的每个帖子
/// - getPostByPid（viewpid/parse.dart）：解析 inajax 单帖响应
///
/// 表情还原由 [Html2BBCode] 自行从 [EmojiService] 读取当前站点数据
/// （按站点隔离，无需调用方传递）；站点数据为空时静默跳过表情。
///
/// 返回字段名统一使用 detail 约定（username / postTime 等）。
Map<String, dynamic> parsePostFromTable(
  dom.Element table, {
  bool isOp = false,
  int floor = 0,
}) {
  final converter = Html2BBCode();

  // ---- PID ----
  final pid = extractPidFromTable(table);

  // ---- 作者信息区 TD.pls ----
  final pls = table.querySelector('td.pls');

  String uid = '', username = '', usergroup = '', followUrl = '';

  if (pls != null) {
    // 昵称 + UID
    final nameLink = pls.querySelector('.pi .authi a');
    if (nameLink != null) {
      username = sanitizeText(nameLink.text);
      final href = nameLink.attributes['href'] ?? '';
      final m = RegExp(r'space.*?uid[=-](\d+)').firstMatch(href);
      if (m != null) uid = m.group(1)!;
    }

    // 用户组
    final lev = pls.querySelector('p em a');
    if (lev != null) usergroup = sanitizeText(lev.text);

    // 关注链接
    final followEl = pls.querySelector('a[id^="followmod_"]');
    followUrl = resolveUrl(followEl?.attributes['href'] ?? '');
  }

  // ---- 帖子内容区 TD.plc ----
  final plc = table.querySelector('td.plc');

  String floorLabel = '',
      postTime = '',
      ipLocation = '',
      source = '',
      bbcode = '';
  Map<String, dynamic>? rating;

  // 置顶回复：管理员将该楼层置顶时，楼层号前会渲染 settop 图标
  // （克米 PC / 移动模板：`td.plc ... a[id^=postnum] img[src*=settop]`，title=置顶回复）
  final isStickReply =
      table.querySelector(
        'img[src*="settop"], img[title*="置顶回复"], img[alt*="置顶回复"]',
      ) !=
      null;

  if (plc != null) {
    // 楼层标签
    final postnum = plc.querySelector('a[id^="postnum"]');
    if (postnum != null) {
      floorLabel = sanitizeText(
        postnum.text,
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      // DOM 标签优先：数字（克米 `16#` / 标准 Discuz `#16`）或中文楼层名（沙发/椅子…）
      final domFloor = parseFloorFromLabel(floorLabel);
      if (domFloor != null) floor = domFloor;
    }

    // 帖子头部信息
    final authi = plc.querySelector('.pti .authi');
    if (authi != null) {
      // 发布时间
      final tmEl = authi.querySelector('em[id^="authorposton"]');
      if (tmEl != null) {
        postTime = sanitizeText(tmEl.text)
            .replaceAll(RegExp(r'发表于\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // 来源（"来自手机"等）
      final srcEl = authi.querySelector('.xg1');
      if (srcEl != null) {
        source = sanitizeText(srcEl.text).trim();
      }

      // IP 属地（克米模板特有，标准 Discuz 无此元素）
      final ipEl = authi.querySelector('code.comiis_iplocality');
      if (ipEl != null) {
        ipLocation = sanitizeText(ipEl.text)
            .replaceAll(RegExp(r'来自\s*'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }

    // 帖子正文 → BBCode
    final msgEl = plc.querySelector('td.t_f[id^="postmessage_"]');
    if (msgEl != null) {
      bbcode = converter.convertElementContent(msgEl);
    }

    // 分类信息（threadtype，如 52pojie「招聘」版）：完整内容放在
    // div.pcb > div.typeoption 里，位于 td.t_f 之外；浏览器中它显示在正文
    // 上方，这里单独转换后前置。不处理会整块丢失（只剩 t_f 里的补充说明）。
    final typeOptionEl = plc.querySelector('.typeoption');
    if (typeOptionEl != null) {
      final typeBbcode = converter.convertElement(typeOptionEl);
      if (typeBbcode.isNotEmpty) {
        bbcode = bbcode.isEmpty ? typeBbcode : '$typeBbcode\n$bbcode';
      }
    }

    // 帖内标题：div.pcb 内的 h2，但必须排除正文区 td.t_f。
    // 不能用 `div.pcb h2` 直接取：Markdown 帖（52pojie parsedown 插件）的正文
    // 标题本身就是 td.t_f 里的第一个 h2，会被误当"帖内标题"再前置一次，
    // 与正文里的标题重复。
    final pcbTitle = _findPostTitle(plc);
    if (pcbTitle != null) {
      final titleCode = sanitizeText(pcbTitle.text).trim();
      if (titleCode.isNotEmpty) {
        bbcode = '[b]$titleCode[/b]\n$bbcode';
      }
    }

    // 回帖奖励：h3.psth → [appdata]
    // DOM 结构：div.pct > div.cm > h3.psth，不在 td.t_f 内容区内
    final rewardEl = plc.querySelector('h3.psth');
    if (rewardEl != null) {
      // <h3 class="psth">回帖奖励 <span class="xw1 xs2 xi1">+30</span> 金币</h3>
      final amountSpan = rewardEl.querySelector('span.xw1.xs2.xi1');
      if (amountSpan != null) {
        final amount = sanitizeText(amountSpan.text).trim();
        if (amount.isNotEmpty) {
          final text = sanitizeText(rewardEl.text).trim();
          final unit = text
              .replaceAll(RegExp(r'回帖奖励\s*'), '')
              .replaceAll(amount, '')
              .trim();
          bbcode =
              '[appdata]${jsonEncode({"type": "reward", "amount": amount, "unit": unit})}[/appdata]\n$bbcode';
        }
      }
    }

    // 求助帖奖励（悬赏金）：.rusld → [appdata]
    // DOM 结构：div.pcbs > div.rwd > div.rusld.z > cite{amount}unit
    final helpReward = plc.querySelector('.rusld cite');
    if (helpReward != null) {
      final amount = sanitizeText(helpReward.text).trim();
      if (amount.isNotEmpty) {
        // 取 cite 后的单位文本（如 "金币"）
        final parentText = sanitizeText(helpReward.parent?.text ?? '').trim();
        final unit = parentText.replaceAll(amount, '').trim();
        bbcode =
            '[appdata]${jsonEncode({"type": "bounty", "amount": amount, "unit": unit})}[/appdata]\n$bbcode';
      }
    }

    // 锁定帖（仅作者可见等）：使用 appdata 专属标签
    // 保底策略：html2bbcode 已处理则跳过，否则补充识别
    final lockedEl = plc.querySelector('.locked');
    if (lockedEl != null) {
      final hasLockedAppdata = RegExp(
        r'\[appdata\]\{"type":"locked".*?\}\[/appdata\]',
      ).hasMatch(bbcode);
      if (!hasLockedAppdata) {
        final lockedMsg = sanitizeText(lockedEl.text).trim();
        if (lockedMsg.isNotEmpty) {
          bbcode =
              '[appdata]${jsonEncode({"type": "locked", "message": lockedMsg})}[/appdata]\n$bbcode';
        }
      }
    }

    // 投票帖：form#poll → [appdata]
    // DOM 结构：div.pcbs > form#poll
    final pollForm = plc.querySelector('form#poll');
    if (pollForm != null) {
      final pinf = pollForm.querySelector('.pinf');
      final pollType = pinf?.querySelector('strong')?.text.trim() ?? '';
      final voterText = pinf?.text.replaceAll(pollType, '').trim() ?? '';
      final voterMatch = RegExp(r'(\d+)').firstMatch(voterText);
      final voterCount = voterMatch?.group(1) ?? '';
      // 选项
      final options = pollForm
          .querySelectorAll('.pvt label')
          .map(
            (l) => sanitizeText(
              l.text,
            ).trim().replaceAll(RegExp(r'^\d+\.\s*'), ''),
          )
          .where((o) => o.isNotEmpty)
          .toList();
      // 状态
      final statusEl = pollForm.querySelector('tr:last-child td[colspan="2"]');
      final status = statusEl != null ? sanitizeText(statusEl.text).trim() : '';
      if (pollType.isNotEmpty) {
        bbcode +=
            '\n[appdata]${jsonEncode({"type": "poll", "pollType": pollType, "voterCount": voterCount, "options": options, if (status.isNotEmpty) "status": status})}[/appdata]';
      }
    }

    // 附件区 div.pattl — 未插入正文的附件，追加到正文末尾
    final pattl = plc.querySelector('div.pattl');
    if (pattl != null) {
      final ops = pattl.querySelectorAll('ignore_js_op');
      for (final op in ops) {
        final attachBbcode = converter.convertElement(op);
        if (attachBbcode.isNotEmpty) {
          bbcode += '\n$attachBbcode';
        }
      }
    }

    // 评分 URL 不在此解析：Discuz 评分 API 两站一致，
    // 由调用方用 tid+pid 直接拼接（forum.php?mod=misc&action=rate&tid=&pid=）。

    // 评分记录 dl.rate / dl[id^="ratelog_"]
    final rateDl = plc.querySelector('dl.rate, dl[id^="ratelog_"]');
    if (rateDl != null) {
      final headerLink = rateDl.querySelector('th a[href*="viewratings"]');
      final headerText = headerLink?.text.trim() ?? '';
      final detailUrl = resolveUrl(headerLink?.attributes['href'] ?? '');

      // 汇总行：克米模板的 p.ratc 是纯文本汇总；52pojie 同一位置是
      // 「查看全部评分」操作链接，不能当汇总文案显示，改用表头
      // （「参与人数 15」）作为汇总。
      String totalScore = '';
      final p = rateDl.querySelector('p.ratc');
      if (p != null && p.querySelector('a[href*="viewratings"]') == null) {
        totalScore = sanitizeText(p.text).trim();
      }
      if (totalScore.isEmpty) totalScore = headerText;

      // 列出每条评分
      final entries = <Map<String, dynamic>>[];

      // 解析表头确定列结构：th[0]=用户, th[1..n-2]=评分列, th[n-1]=理由
      final headerThs = rateDl.querySelectorAll('table.ratl tr th');
      final reasonColIndex = headerThs.length > 1 ? headerThs.length - 1 : null;
      final scoreColIndices = <int>[
        for (int i = 1; i < headerThs.length - 1; i++) i,
      ];
      // 评分列名（去除字体图标后的纯文本）
      final columns = scoreColIndices
          .map((i) => sanitizeText(headerThs[i].text))
          .where((s) => s.isNotEmpty)
          .toList();

      final rows = rateDl.querySelectorAll('tbody.ratl_l tr');
      for (final row in rows) {
        final allTds = row.querySelectorAll('td');
        if (allTds.isEmpty) continue;
        // 用户名列：克米模板是 `a.xg1`；52pojie 没有该类名，且首个 <a>
        // 是头像链接（文本为空），见 _findRateUserNameLink。
        final nameLink = _findRateUserNameLink(allTds[0]);
        // 评分列：按表头位置逐个取 td
        final scores = scoreColIndices
            .map((i) => i < allTds.length ? allTds[i].text.trim() : '')
            .toList();
        // 理由列：最后一列
        final reason = reasonColIndex != null && reasonColIndex < allTds.length
            ? allTds[reasonColIndex].text.trim()
            : '';
        if (nameLink != null) {
          final href = nameLink.attributes['href'] ?? '';
          // 克米：`space-uid-123`；52pojie：`home.php?mod=space&uid=123`
          final uidMatch = RegExp(r'space.*?uid[=-](\d+)').firstMatch(href);
          entries.add({
            'username': nameLink.text.trim(),
            'uid': uidMatch?.group(1) ?? '',
            'scores': scores,
            'reason': reason,
          });
        }
      }

      rating = {
        'header': headerText,
        'detailUrl': detailUrl,
        'totalScore': totalScore,
        'columns': columns,
        'entries': entries,
      };
    }
  }

  return {
    'pid': pid,
    'floor': floor,
    'floorLabel': floorLabel,
    'isOp': isOp,
    'uid': uid,
    'username': username,
    'usergroup': usergroup,
    'postTime': postTime,
    'ipLocation': ipLocation,
    'source': source,
    'bbcode': bbcode,
    'followUrl': followUrl,
    'rating': rating,
    'isStickReply': isStickReply,
  };
}

/// 评分记录行里的用户名链接。
///
/// - 克米模板：`<a class="xg1">昵称</a>`（首选，保持原行为）；
/// - 52pojie：`<a href="home.php?mod=space&uid=…"><img …></a><a …>昵称</a>`
///   —— 没有 `xg1`，且首个链接是头像（文本为空），因此退化为
///   「第一个带可见文本的链接」。
dom.Element? _findRateUserNameLink(dom.Element cell) {
  final xg1 = cell.querySelector('a.xg1');
  if (xg1 != null && sanitizeText(xg1.text).trim().isNotEmpty) return xg1;
  for (final a in cell.querySelectorAll('a')) {
    if (sanitizeText(a.text).trim().isNotEmpty) return a;
  }
  return null;
}

/// 找「帖内标题」：`div.pcb` 内、但不在正文区 `td.t_f` 里的 h2。
///
/// 模板把帖内标题渲染在正文区之外；而 52pojie 的 Markdown 插件会把作者写的
/// `## 标题` 输出成正文区内的第一个 `<h2>`。若直接用后代选择器 `div.pcb h2`
/// 取，会把正文标题当成帖内标题再前置一次，造成标题重复。
dom.Element? _findPostTitle(dom.Element plc) {
  for (final h2 in plc.querySelectorAll('div.pcb h2')) {
    if (!_isInsideContentCell(h2)) return h2;
  }
  return null;
}

/// [el] 是否位于楼层正文单元格（`td.t_f` / `.t_fsz`）内
bool _isInsideContentCell(dom.Element el) {
  for (dom.Node? node = el.parent; node != null; node = node.parent) {
    if (node is! dom.Element) continue;
    final cls = node.className;
    if (cls == 't_f' || cls == 't_fsz') return true;
  }
  return false;
}

/// 中文楼层名 → 楼层号
///
/// 克米模板前 10 楼用中文命名（`a[id^="postnum"].km1` 即楼主 = 1 楼），
/// 与数字标签连续编号：下水道 = 10 楼，其后的帖子即 `11#`。
const Map<String, int> _namedFloors = {
  '楼主': 1,
  '沙发': 2,
  '椅子': 3,
  '板凳': 4,
  '地毯': 5,
  '凉席': 6,
  '报纸': 7,
  '地板': 8,
  '地下室': 9,
  '下水道': 10,
};

/// 从 `a[id^="postnum"]` 的文本解析楼层号
///
/// 两种形态：
/// - 数字：克米模板 `16#`（数字在前），标准 Discuz `#16`
/// - 中文名：前 10 楼为 楼主/沙发/…/下水道，按 [_namedFloors] 映射
///
/// 解析不出返回 null，由调用方沿用按顺序推算的兜底楼层。
int? parseFloorFromLabel(String label) {
  if (label.isEmpty) return null;
  final match =
      RegExp(r'(\d+)\s*#').firstMatch(label) ??
      RegExp(r'#\s*(\d+)').firstMatch(label);
  if (match != null) {
    final parsed = int.tryParse(match.group(1)!);
    if (parsed != null) return parsed;
  }
  for (final entry in _namedFloors.entries) {
    if (label.contains(entry.key)) return entry.value;
  }
  return null;
}

/// 从 table#pidXX 提取 PID
String extractPidFromTable(dom.Element table) {
  final id = table.id;
  if (id.startsWith('pid')) return id.substring(3);
  return '';
}

/// 将相对 URL 解析为绝对 URL（空串原样返回，其余交给 [normalizeUrl]）
String resolveUrl(String href) {
  if (href.isEmpty) return '';
  return normalizeUrl(href);
}

import 'package:html/dom.dart' as dom;
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/html2bbcode.dart';
import 'package:mtbbs/core/page_helper.dart';

/// 从 table#pidXX.plhin（PC 模板）提取单帖完整数据
///
/// 两个消费者共用此函数：
/// - getThreadDetail（detail/parse.dart）：解析帖子详情页的每个帖子
/// - getPostByPid（viewpid/parse.dart）：解析 inajax 单帖响应
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
      bbcode = '',
      rateUrl = '';
  Map<String, dynamic>? rating;

  if (plc != null) {
    // 楼层标签
    final postnum = plc.querySelector('a[id^="postnum"]');
    if (postnum != null) {
      floorLabel = sanitizeText(
        postnum.text,
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      // 提取楼层数字
      final floorMatch = RegExp(r'#(\d+)').firstMatch(floorLabel);
      if (floorMatch != null) {
        floor = int.tryParse(floorMatch.group(1)!) ?? floor;
      }
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

    // 评分 URL
    final rateLink = plc.querySelector('.po .pob.cl a[onclick*="action=rate"]');
    if (rateLink != null) {
      final onclick = rateLink.attributes['onclick'] ?? '';
      final m = RegExp(r"'(/[^']+)'").firstMatch(onclick);
      if (m != null) {
        rateUrl = resolveUrl(m.group(1)!);
      }
    }

    // 评分记录 dl.rate / dl[id^="ratelog_"]
    final rateDl = plc.querySelector('dl.rate, dl[id^="ratelog_"]');
    if (rateDl != null) {
      final headerLink = rateDl.querySelector('th a[href*="viewratings"]');
      final headerText = headerLink?.text.trim() ?? '';
      final detailUrl = resolveUrl(headerLink?.attributes['href'] ?? '');

      // 汇总行
      String totalScore = '';
      final p = rateDl.querySelector('p.ratc');
      if (p != null) {
        totalScore = p.text.trim();
      }

      // 列出每条评分
      final entries = <Map<String, dynamic>>[];

      // 解析表头确定列结构：th[0]=用户, th[1..n-2]=评分列, th[n-1]=理由
      final headerThs = rateDl.querySelectorAll('table.ratl tr th');
      final reasonColIndex =
          headerThs.length > 1 ? headerThs.length - 1 : null;
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
        // 用户名列：第一个 td 中的 a.xg1
        final nameLink = allTds[0].querySelector('a.xg1');
        // 评分列：按表头位置逐个取 td
        final scores = scoreColIndices
            .map((i) => i < allTds.length ? allTds[i].text.trim() : '')
            .toList();
        // 理由列：最后一列
        final reason =
            reasonColIndex != null && reasonColIndex < allTds.length
                ? allTds[reasonColIndex].text.trim()
                : '';
        if (nameLink != null) {
          final href = nameLink.attributes['href'] ?? '';
          final uidMatch = RegExp(r'space-uid-(\d+)').firstMatch(href);
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
    'rateUrl': rateUrl,
    'followUrl': followUrl,
    'rating': rating,
  };
}

/// 从 table#pidXX 提取 PID
String extractPidFromTable(dom.Element table) {
  final id = table.id;
  if (id.startsWith('pid')) return id.substring(3);
  return '';
}

/// 将相对 URL 解析为绝对 URL
String resolveUrl(String href) {
  if (href.isEmpty) return '';
  final uri = Uri.tryParse(href);
  if (uri == null) return href;
  if (uri.hasScheme) return href;
  final base = Uri.parse(SiteConfig.baseUrl);
  return base.resolve(href).toString();
}

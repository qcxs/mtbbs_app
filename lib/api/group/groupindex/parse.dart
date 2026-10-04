/// 圈子（Discuz 群组 `group.php`）响应解析
///
/// 只解析**桌面模板**（`comiis_wide`，标题「群组」）；移动克米模板的圈子列表
/// 由 JS 动态加载，静态 HTML 无数据（见 http.dart 的 UA 说明）。
///
/// ## 首页 `/group.php?hot=yes` DOM
/// ```html
/// <div id="g_commend" class="bm"><!-- 推荐群组 -->
///   <div class="bm_c cl">
///     <dl class="xld">
///       <dd class="m"><a href="group-57-1.html"><img src="..." alt="技术学习"></a></dd>
///       <dt><a href="group-57-1.html">技术学习</a></dt>
///       <dd class="xg1">简介</dd>
///     </dl>
///   </div>
/// </div>
/// <div class="bm"><!-- 群组分类 -->
///   <div class="bm_c">
///     <dl class="mbm pbm bbda">
///       <dt class="pbn">
///         <span class="y xi2"><a href="group.php?gid=3">更多 ›</a></span>
///         <strong class="xs2"><a href="group.php?gid=3">技术</a></strong>
///         <span class="xg1">(27)</span>
///       </dt>
///       <dd><a href="group-57-1.html">技术学习</a> ...</dd>
///     </dl>
///   </div>
/// </div>
/// <div id="g_top" class="bm"><!-- 群组积分排行 -->
///   <div class="bm_c"><ol class="xl">
///     <li><span class="y xi2 xg1"> 382</span><a href="group-57-1.html">技术学习</a></li>
///   </ol></div>
/// </div>
/// ```
///
/// ## 分类页 `/group.php?gid=N` DOM
/// ```html
/// <h1>技术</h1>
/// <table class="fl_tb"><tbody>
///   <tr class="fl_row">
///     <td class="fl_icn"><a href="group-97-1.html"><img src="..." title="宣传小组"></a></td>
///     <td><strong><a href="group-97-1.html">宣传小组</a></strong>
///         <p class="xg1">简介</p></td>
///     <td class="fl_i">
///       <span class="i_z z"><strong>2</strong><em class="xg1">群组成员</em></span>
///       <span class="i_y z"><strong>2</strong><em class="xg1">主题</em></span>
///     </td>
///   </tr>
/// </tbody></table>
/// ```
library;

import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/url_util.dart';

/// 从 `group-{id}-{page}.html` 形式的链接中提取圈子 ID
String _groupIdFromHref(String href) {
  final m = RegExp(r'group-(\d+)').firstMatch(href);
  return m?.group(1) ?? '';
}

/// 从 `group.php?gid={id}` 形式的链接中提取分类 ID
String _categoryIdFromHref(String href) {
  final m = RegExp(r'[?&]gid=(\d+)').firstMatch(href);
  return m?.group(1) ?? '';
}

/// 从 "(27)" 这类文本中提取数字
int _digitsOnly(String text) {
  final m = RegExp(r'(\d+)').firstMatch(text);
  return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
}

/// 解析圈子首页（推荐圈子 + 圈子分类 + 积分排行）
Map<String, dynamic> parseIndex(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  // ① 推荐圈子
  final featured = <Map<String, dynamic>>[];
  final featuredDls = doc.querySelectorAll('#g_commend .bm_c dl.xld');
  for (final dl in featuredDls) {
    final a = dl.querySelector('dt a');
    final name = sanitizeText(a?.text);
    if (name.isEmpty) continue;
    final href = a?.attributes['href'] ?? '';
    featured.add({
      'gid': _groupIdFromHref(href),
      'name': name,
      'icon': normalizeUrl(
        dl.querySelector('dd.m img')?.attributes['src'] ?? '',
      ),
      'description': sanitizeText(dl.querySelector('dd.xg1')?.text),
      'url': normalizeUrl(href),
    });
  }

  // ② 圈子分类（含该分类下的圈子预览）
  final categories = <Map<String, dynamic>>[];
  final catDls = doc.querySelectorAll('dl.mbm.pbm.bbda');
  for (final dl in catDls) {
    final strongA = dl.querySelector('dt strong a');
    final name = sanitizeText(strongA?.text);
    final href = strongA?.attributes['href'] ?? '';
    if (name.isEmpty || href.isEmpty) continue;
    final groups = <Map<String, dynamic>>[];
    for (final a in dl.querySelectorAll('dd a')) {
      final gName = sanitizeText(a.text);
      final gHref = a.attributes['href'] ?? '';
      if (gName.isEmpty) continue;
      groups.add({
        'gid': _groupIdFromHref(gHref),
        'name': gName,
        'url': normalizeUrl(gHref),
      });
    }
    categories.add({
      'gid': _categoryIdFromHref(href),
      'name': name,
      'count': _digitsOnly(sanitizeText(dl.querySelector('dt span.xg1')?.text)),
      'url': normalizeUrl(href),
      'groups': groups,
    });
  }

  // ③ 积分排行
  final rank = <Map<String, dynamic>>[];
  for (final li in doc.querySelectorAll('#g_top ol.xl li')) {
    final a = li.querySelector('a');
    final name = sanitizeText(a?.text);
    if (name.isEmpty) continue;
    final href = a?.attributes['href'] ?? '';
    rank.add({
      'gid': _groupIdFromHref(href),
      'name': name,
      'score': _digitsOnly(sanitizeText(li.querySelector('span.y')?.text)),
      'url': normalizeUrl(href),
    });
  }

  final hasAny =
      featured.isNotEmpty || categories.isNotEmpty || rank.isNotEmpty;
  return {
    'success': true,
    'featured': featured,
    'categories': categories,
    'rank': rank,
    'categoryCount': categories.length,
    '_health': {
      'parser': 'group_index',
      'missing': hasAny ? const <String>[] : const ['未解析出任何圈子区块'],
    },
  };
}

/// 解析某个分类下的圈子列表（分页）
Map<String, dynamic> parseCategoryGroups(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final groups = <Map<String, dynamic>>[];
  final rows = doc.querySelectorAll('tr.fl_row');
  for (final tr in rows) {
    final a =
        tr.querySelector('td strong a') ?? tr.querySelector('td.fl_icn a');
    final name = sanitizeText(a?.text);
    if (name.isEmpty) continue;
    final href = a?.attributes['href'] ?? '';
    groups.add({
      'gid': _groupIdFromHref(href),
      'name': name,
      'icon': normalizeUrl(
        tr.querySelector('td.fl_icn img')?.attributes['src'] ?? '',
      ),
      'description': sanitizeText(tr.querySelector('td p.xg1')?.text),
      'members': _digitsOnly(
        sanitizeText(tr.querySelector('td.fl_i span.i_z')?.text),
      ),
      'threads': _digitsOnly(
        sanitizeText(tr.querySelector('td.fl_i span.i_y')?.text),
      ),
      'url': normalizeUrl(href),
    });
  }

  final pagination = extractPagination(doc);
  final cp = pagination['currentPage'] ?? 1;
  final tp = pagination['totalPages'] ?? 1;

  return {
    'success': true,
    'categoryName': sanitizeText(doc.querySelector('h1')?.text),
    'groups': groups,
    'count': groups.length,
    'currentPage': cp,
    'totalPages': tp,
    'hasMore': cp < tp,
    '_health': {
      'parser': 'group_category',
      // 容器存在却解析不出圈子 = 结构可能变了（区别于"该分类确实没有圈子"）。
      'missing': (groups.isEmpty && rows.isNotEmpty)
          ? const ['分类表格存在但未解析出圈子']
          : const <String>[],
    },
  };
}

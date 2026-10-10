import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 积分公式响应解析 — PC 版 DOM
///
/// 从 home.php?mod=spacecp&ac=credit 的 HTML 中提取：
/// - 当前积分（总积分值）
/// - 积分计算公式字符串
/// - 各项积分明细（金币、好评、信誉等）
///
/// PC 版 DOM 结构（标准 Discuz）：
/// ```html
/// <ul class="creditl mtm bbda cl">
///   <li class="xi1 cl"><em> 金币: </em>566  &nbsp; </li>
///   <li><em> 好评: </em>189 </li>
///   <li class="cl"><em>积分: </em>18851 <span class="xg1">( 总积分=...)</span></li>
/// </ul>
/// ```

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  // 查找 PC 版积分容器
  final creditUl = doc.querySelector('ul.creditl');
  if (creditUl == null) {
    return {'success': false, 'message': '未找到积分信息（可能需要登录）'};
  }

  final result = <String, dynamic>{'success': true};

  // --- 积分公式 ---
  // PC 版公式在最后一个 li 的 span.xg1 中
  final formulaSpan = creditUl.querySelector('li.cl span.xg1');
  if (formulaSpan != null) {
    var formulaText = formulaSpan.text.trim();
    // 去掉外层括号 "( ... )"
    if (formulaText.startsWith('(') && formulaText.endsWith(')')) {
      formulaText = formulaText.substring(1, formulaText.length - 1).trim();
    }
    // 去掉 "总积分=" 前缀
    if (formulaText.startsWith('总积分=')) {
      formulaText = formulaText.substring(4);
    }
    // 标准化符号
    formulaText = formulaText
        .replaceAll('×', '*')
        .replaceAll('X', '*')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('\u00A0', ' ') // &nbsp; → 空格
        .trim();
    result['formula'] = formulaText;
  }

  // --- 各项积分明细 ---
  // PC 版各项在 ul.creditl > li 中（不含最后一个带公式的 li）
  final items = <Map<String, dynamic>>[];
  for (final li in creditUl.querySelectorAll('li')) {
    // 跳过包含公式的 li（特征：内含 span.xg1）
    if (li.querySelector('span.xg1') != null) continue;

    final em = li.querySelector('em');
    if (em == null) continue;
    final label = em.text.trim().replaceAll(':', '').replaceAll('：', '').trim();
    if (label.isEmpty) continue;

    // 去除 em 标签获取纯文本值
    final liClone = li.clone(true);
    liClone.querySelector('em')?.remove();
    var value = liClone.text.trim();
    // 清理多余空白和 &nbsp;
    value = value.replaceAll('\u00A0', ' ').trim();

    items.add({'label': label, 'value': value});
  }
  if (items.isNotEmpty) {
    result['items'] = items;
  }

  // --- 总积分值 ---
  // 在公式 li 的 em 后的文本中
  final formulaLi = creditUl.querySelector('li.cl');
  if (formulaLi != null) {
    final formulaEm = formulaLi.querySelector('em');
    if (formulaEm != null) {
      // 克隆 li，移除 em 和 span，取纯文本
      final liClone = formulaLi.clone(true);
      liClone.querySelector('em')?.remove();
      liClone.querySelector('span')?.remove();
      var creditValue = liClone.text.trim().replaceAll('\u00A0', ' ').trim();
      if (creditValue.isNotEmpty) {
        result['credits'] = creditValue;
      }
    }
  }

  // 解析日志由 export 层 parseWithLog 统一输出，此处不再重复打印

  return result;
}

/// 积分记录响应解析 — 标准 Discuz PC 版 DOM
///
/// 数据表位于 `#ct .mn .bm form > table.dt`，每行 4 列，首行为 `<th>` 表头：
/// ```html
/// <table class="dt">
///   <tr><th width="80">操作</th><th width="80">积分变更</th><th>详情</th><th width="100">变更时间</th></tr>
///   <tr>
///     <td><a href="...&amp;optype=PRC">帖子被评分</a></td>
///     <td>好评 <span class="xi1">+1</span></td>  <!-- 增加 xi1 / 减少 xg1，数值带符号 -->
///     <td><a href="...&amp;goto=findpost&amp;pid=..."> <strong>标题</strong> 被评分获得的积分</a></td>
///     <td>2026-10-09 18:49</td>
///   </tr>
/// </table>
/// ```
/// - **详情**列在有链接时指向相关内容（帖子 `goto=findpost&pid=`、道具、主题等），
///   归一为绝对 URL 输出（`detailUrl`），由渲染层交给 URL 路由跳转。
///
/// 分页在 `.pg`（`<strong>当前页</strong>` + `<span title="共 N 页">`，见 [extractPagination]）。
/// 服务端 HTML 为最终结构，与 UA 无关（`comiis_wide` PC 模板）。
Map<String, dynamic> parseLogResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final table = doc.querySelector('table.dt');
  if (table == null) {
    return {'success': false, 'message': '未找到积分记录（可能需要登录）'};
  }

  final items = <Map<String, dynamic>>[];
  for (final tr in table.querySelectorAll('tr')) {
    final tds = tr.querySelectorAll('td');
    if (tds.length < 4) continue; // 跳过表头（th 行）

    // 积分变更：形如「金币 +2」，数值在 span 内（含符号）
    final changeCell = tds[1];
    final delta = sanitizeText(changeCell.querySelector('span')?.text);
    final changeClone = changeCell.clone(true);
    changeClone.querySelector('span')?.remove();
    final creditType = sanitizeText(changeClone.text);

    items.add({
      'action': sanitizeText(tds[0].text),
      'creditType': creditType,
      'delta': delta,
      'detail': sanitizeText(tds[2].text),
      'detailUrl': _absUrl(tds[2].querySelector('a')?.attributes['href']),
      'time': sanitizeText(tds[3].text),
    });
  }

  final pg = extractPagination(doc);
  final currentPage = pg['currentPage'] ?? 1;
  final totalPages = pg['totalPages'] ?? 1;

  AppLogger.i('PARSE', '积分记录 第 $currentPage/$totalPages 页，共 ${items.length} 条');

  return {
    'success': true,
    'items': items,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'hasMore': currentPage < totalPages,
  };
}

/// 归一为绝对 URL（数据层负责补全域名，见 docs/02「数据层 ↔ 渲染层职责边界」）。
/// 已绝对 / 协议相对原样或补协议；站内相对路径补 `baseUrl`。
String _absUrl(String? href) {
  final h = href?.trim() ?? '';
  if (h.isEmpty) return '';
  if (h.startsWith('http://') || h.startsWith('https://')) return h;
  if (h.startsWith('//')) return 'https:$h';
  final base = SiteStore.instance.baseUrl;
  return h.startsWith('/') ? '$base$h' : '$base/$h';
}

import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/app/page_helper.dart';
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

  AppLogger.i(
    'PARSE',
    jsonEncode({
      'type': 'credit',
      'credits': result['credits'],
      'formula': result['formula'],
    }),
  );

  return result;
}

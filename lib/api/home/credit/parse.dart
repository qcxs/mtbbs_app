import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 积分公式响应解析
///
/// 从 home.php?mod=spacecp&ac=credit 的 HTML 中提取：
/// - 当前积分
/// - 积分计算公式字符串
/// - 各项积分明细（金币、好评、信誉）

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

  // 查找公式容器
  final creditDiv = doc.querySelector('.comiis_creditl');
  if (creditDiv == null) {
    return {'success': false, 'message': '未找到积分信息（可能需要登录）'};
  }

  final result = <String, dynamic>{'success': true};

  // --- 当前积分 ---
  final creditSpan = creditDiv.querySelector('h2 span');
  if (creditSpan != null) {
    result['credits'] = creditSpan.text.trim();
  }

  // --- 积分公式 ---
  final formulaP = creditDiv.querySelector('h2 p.comiis_tm');
  if (formulaP != null) {
    var formulaText = formulaP.text.trim();
    // 去掉开头 "总积分="
    if (formulaText.startsWith('总积分=')) {
      formulaText = formulaText.substring(4);
    }
    // 标准化符号
    formulaText = formulaText
        .replaceAll('×', '*')
        .replaceAll('X', '*')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
    result['formula'] = formulaText;
  }

  // --- 各项积分明细 ---
  final items = <Map<String, dynamic>>[];
  for (final li in creditDiv.querySelectorAll('ul li')) {
    final span = li.querySelector('span');
    if (span == null) continue;
    final label = span.text
        .trim()
        .replaceAll(':', '')
        .replaceAll('：', '')
        .trim();
    // 去除 span 获取值
    final liClone = li.clone(true);
    liClone.querySelector('span')?.remove();
    final value = liClone.text.trim();
    items.add({'label': label, 'value': value});
  }
  if (items.isNotEmpty) {
    result['items'] = items;
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

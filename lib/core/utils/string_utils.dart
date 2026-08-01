/// 通用字符串 / 路径 / ID 小工具。
library;

import 'dart:math';

/// 生成唯一 ID（时间戳 + 随机数，无需依赖 uuid 包）
String genId() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final r = Random().nextInt(99999);
  return '${ts}_$r';
}

/// 取路径最后一段（兼容 `/` 和 `\`）：`a/b/c.jpg` → `c.jpg`
String basename(String path) => path.split(RegExp(r'[/\\]')).last;

/// 去除 HTML 标签：`<a>x</a>` → `x`
String stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

/// HTML 转义：`& < > " '` → 实体
String htmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// 解析带千分位逗号的整数："1,234" → 1234
int parseIntWithComma(Object? v, {int fallback = 0}) {
  final s = v?.toString().replaceAll(',', '').trim() ?? '';
  return int.tryParse(s) ?? fallback;
}

/// 解析带千分位逗号的小数："1,234.5" → 1234.5
double parseDoubleWithComma(Object? v, {double fallback = 0}) {
  final s = v?.toString().replaceAll(',', '').trim() ?? '';
  return double.tryParse(s) ?? fallback;
}

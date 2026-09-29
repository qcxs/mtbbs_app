part of 'bbcode2html.dart';

final RegExp _brBeforeOpen = RegExp(
  r'<br>\s*(?=<(?:div|blockquote|ul|ol|li|table|tr|td|pre|hr)(?:\s|>)|\x00CODE\d+\x00)',
  caseSensitive: false,
);
final RegExp _brAfterClose = RegExp(
  r'((?:</(?:div|blockquote|ul|ol|li|table|tr|td|pre)>|\x00CODE\d+\x00))\s*<br>',
  caseSensitive: false,
);
final RegExp _brBeforeClose = RegExp(
  r'<br>\s*(?=</(?:div|blockquote|ul|ol|li|table|tr|td|pre)>)',
  caseSensitive: false,
);
final RegExp _brAfterOpen = RegExp(
  r'(<(?:div|blockquote|ul|ol|li|table|tr|td|pre)(?:\s[^>]*)?>)\s*<br>',
  caseSensitive: false,
);

extension on BBCode2Html {
  /// 移除块级 HTML 容器前后多余的 `<br>`。
  ///
  /// BBCode 原文中常有排版用的换行和缩进，例如：
  /// ```bbcode
  /// [font=...]
  ///   [hide]
  ///     [appdata]{...}[/appdata]
  ///   [/hide]
  /// [/font]
  /// ```
  /// 或列表：
  /// ```bbcode
  /// [list]
  ///   [*]item
  /// [/list]
  /// ```
  /// 在 `\n` → `<br>` 阶段，这些排版换行也被转成了 `<br>`，
  /// 出现在块级容器周围。块级容器自身已产生段落换行，
  /// 其前后的 `<br>` 没有语义含义，只增加空白。
  ///
  /// 通用规则：移除与块级标签紧邻（中间仅空白）的 `<br>`，四个方向：
  /// 开标签前 / 闭标签后 / 闭标签前 / 开标签后。
  /// 未来新增块级标签，同步加入以下四个正则的标签组即可。
  /// [code] 占位符（\x00CODE\d+\x00）还原后是 <pre> 块级容器，也视为边界；
  /// 其还原后的内部 `<li><br></li>`（代码行尾换行）在清理之后生成，不受影响。
  String _removeAdjacentLineBreaks(String html) {
    // 开标签前的 <br>（如 text\n[list]、[/quote]\n[list]）
    html = html.replaceAll(_brBeforeOpen, '');
    // 闭标签后的 <br>（如 [/list]\n[list]）。
    // 注意：Dart 的 replaceAll 不展开 $1 组引用，须用 replaceAllMapped 取组。
    html = html.replaceAllMapped(_brAfterClose, (m) => m[1]!);
    // 闭标签前的 <br>（如 [/appdata]\n[/list]，本次修复的核心场景）
    html = html.replaceAll(_brBeforeClose, '');
    // 开标签后的 <br>（如 [list]\n 起始、[align=center]\n）
    html = html.replaceAllMapped(_brAfterOpen, (m) => m[1]!);
    return html;
  }

  /// 将 [table] BBCode 转换为 `<table>` HTML（嵌套安全）。
  ///
  /// 按最外层 [table] 块处理，保证 table 套 table、table 内任意标签互套
  /// 时结构完整（用 [outerBlocks] 栈式配对，非贪婪正则会被内层
  /// `[/td]`/`[/tr]` 截断）。表格外观（边框/内边距/列宽）由渲染层
  /// 按主题提供，这里只输出结构 + 从 [align] 提取的 text-align。
  String _convertTables(String html) {
    final result = StringBuffer();
    var lastEnd = 0;
    for (final block in outerBlocks(html, 'table')) {
      if (block.start > lastEnd) {
        result.write(html.substring(lastEnd, block.start));
      }
      result.write(_renderTableBlock(html.substring(block.start, block.end)));
      lastEnd = block.end;
    }
    result.write(html.substring(lastEnd));
    return result.toString();
  }

  /// 渲染单个最外层 [table]...[/table] 块
  String _renderTableBlock(String block) {
    final content = block.substring(7, block.length - 8); // 去 [table]/[/table]
    final rows = <String>[];
    for (final tr in outerBlocks(content, 'tr')) {
      final trBlock = content.substring(tr.start, tr.end);
      final trInner = trBlock.substring(4, trBlock.length - 5); // 去 [tr]/[/tr]
      final tds = <String>[];
      for (final td in outerBlocks(trInner, 'td')) {
        final tdBlock = trInner.substring(td.start, td.end);
        final tdInner = tdBlock.substring(
          4,
          tdBlock.length - 5,
        ); // 去 [td]/[/td]
        tds.add(_renderTd(tdInner));
      }
      rows.add('<tr>${tds.join()}</tr>');
    }
    return '<table>${rows.join()}</table>';
  }

  String _renderTd(String content) {
    // 递归转换 td 内嵌套的 [table]
    final inner = _convertTables(content);
    // 检测 td 内容是否被 <div align="XXX">...</div> 包裹，
    // 将 text-align 直接挂到 td 上（td 是表格单元格，块级元素在其中的
    // 对齐交给单元格自身的 text-align 处理更可靠）
    final trimmed = inner.trim();
    if (trimmed.startsWith('<div align="') && trimmed.endsWith('</div>')) {
      final attrMatch = RegExp(
        r'^<div\s+align="([^"]+)"\s*>',
      ).firstMatch(trimmed);
      if (attrMatch != null) {
        final align = attrMatch.group(1)!;
        final innermost = trimmed.substring(attrMatch.end, trimmed.length - 6);
        return '<td style="text-align:$align">$innermost</td>';
      }
    }
    return '<td>$inner</td>';
  }
}

/// 栈式匹配所有最外层 `[tag]...[/tag]` 块（含标签本身）。
///
/// 返回完整区间列表（start 为开标签位置、end 为闭标签之后）。
/// 与正则非贪婪匹配不同，这里按栈配对，天然支持嵌套
/// （如 table 套 table、tr 内嵌 table），不会被内层闭标签截断。
/// 未配对的残留标签会被忽略。
List<({int start, int end})> outerBlocks(String input, String tag) {
  final result = <({int start, int end})>[];
  // 注意：不能用 r'...' 原始字符串，否则 $tag 不插值
  final regex = RegExp('\\[/?$tag\\]', caseSensitive: false);
  var depth = 0;
  var start = -1;
  for (final m in regex.allMatches(input)) {
    if (m.group(0)!.toLowerCase() == '[$tag]') {
      if (depth == 0) start = m.start;
      depth++;
    } else {
      depth--;
      if (depth == 0 && start != -1) {
        result.add((start: start, end: m.end));
        start = -1;
      }
    }
  }
  return result;
}

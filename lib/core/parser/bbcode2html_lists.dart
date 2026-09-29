part of 'bbcode2html.dart';

/// 列表闭合标签（长度用于切出块内容）
const _kListClose = '[/list]';

/// 无序列表各层级的前缀符号（按嵌套深度轮换）。
///
/// 置为空列表即完全不加前缀（列表项退化为普通段落）；
/// 如需保留符号提示，改为 `['•', '◦', '▪']` 即可。
const _kUnorderedMarkers = <String>[];

/// 1 → A，2 → B … 27 → AA（表格列名式递增）
String _letters(int index) {
  var n = index;
  final codes = <int>[];
  while (n > 0) {
    n--;
    codes.add(0x41 + n % 26);
    n ~/= 26;
  }
  return String.fromCharCodes(codes.reversed);
}

extension on BBCode2Html {
  /// 将 `[list]` / `[list=1]` / `[list=a]` 等块转换为**带内联前缀的段落**。
  ///
  /// 刻意**不使用 `<ul>/<ol>/<li>`**：渲染器的列表标记是悬挂在文字左侧的，
  /// 每层嵌套都要额外吃掉一段水平空间（gutter），嵌套几层后正文会被挤到没有
  /// 宽度；而把编号直接拼进文字里，嵌套多少层都不占额外宽度、也不产生左侧留白。
  ///
  /// - 无序列表：默认不加前缀（见 [_kUnorderedMarkers]），项即普通段落
  /// - 有序列表：按 `[list=N]` 类型拼 `1.` / `a.` / `A.`
  ///
  /// 嵌套列表在项内容里递归处理，层级只影响无序前缀的符号（可选）。
  String _convertLists(String html, {int depth = 1}) {
    final blocks = _outerListBlocks(html);
    if (blocks.isEmpty) return html;
    final result = StringBuffer();
    var lastEnd = 0;
    for (final block in blocks) {
      if (block.start > lastEnd) {
        result.write(html.substring(lastEnd, block.start));
      }
      result.write(
        _renderListBlock(
          html.substring(block.start, block.end),
          block.type,
          depth,
        ),
      );
      lastEnd = block.end;
    }
    result.write(html.substring(lastEnd));
    return result.toString();
  }

  /// 渲染单个最外层 `[list...]...[/list]` 块为若干 `<div>`
  String _renderListBlock(String block, String type, int depth) {
    final openEnd = block.indexOf(']');
    if (openEnd < 0) return block;
    // 去 [list...] 与 [/list]
    final inner = block.substring(
      openEnd + 1,
      block.length - _kListClose.length,
    );
    final marker = _kUnorderedMarkers.isEmpty
        ? ''
        : '${_kUnorderedMarkers[(depth - 1) % _kUnorderedMarkers.length]} ';
    final buf = StringBuffer();
    var index = 0;
    for (final part in _splitListItems(inner)) {
      final body = _convertLists(part.content.trim(), depth: depth + 1);
      if (!part.isItem) {
        // [list] 与首个 [*] 之间的散落文本，按普通段落保留
        if (body.isNotEmpty) buf.write('<div>$body</div>');
        continue;
      }
      index++;
      final prefix = type.isEmpty ? marker : '${_orderedLabel(type, index)}. ';
      buf.write('<div>$prefix$body</div>');
    }
    return buf.toString();
  }

  /// 匹配最外层 `[list...]...[/list]` 块（栈式配对，支持列表套列表）
  List<({int start, int end, String type})> _outerListBlocks(String input) {
    // 注意：不能用 outerBlocks()，它只认裸标签，匹配不到 [list=1]
    final re = RegExp(
      r'\[list(?:=([^\]]*))?\]|\[/list\]',
      caseSensitive: false,
    );
    final blocks = <({int start, int end, String type})>[];
    var depth = 0;
    var start = -1;
    var type = '';
    for (final m in re.allMatches(input)) {
      if (m.group(0)!.startsWith('[/')) {
        depth--;
        if (depth <= 0) {
          if (start >= 0) {
            blocks.add((start: start, end: m.end, type: type));
          }
          depth = 0;
          start = -1;
        }
      } else {
        if (depth == 0) {
          start = m.start;
          type = (m.group(1) ?? '').trim();
        }
        depth++;
      }
    }
    return blocks;
  }

  /// 按最外层 `[*]` 切分列表项（跳过嵌套列表内部的 `[*]` 与 `[/*]`）
  ///
  /// `[/*]`（部分编辑器输出的项结束标记）只作分隔，不产生新项。
  List<({bool isItem, String content})> _splitListItems(String content) {
    final re = RegExp(
      r'\[list(?:=[^\]]*)?\]|\[/list\]|\[\*\]|\[/\*\]',
      caseSensitive: false,
    );
    final parts = <({bool isItem, String content})>[];
    var depth = 0;
    var itemStart = -1;
    var sawItem = false;
    for (final m in re.allMatches(content)) {
      final token = m.group(0)!.toLowerCase();
      if (token == '[*]') {
        if (depth == 0) {
          if (itemStart >= 0) {
            parts.add((
              isItem: true,
              content: content.substring(itemStart, m.start),
            ));
          } else if (!sawItem && m.start > 0) {
            // 仅首个 [*] 之前的文本算「散落文本」；
            // 若不加 sawItem 判断，[/*] 结束项后的下一个 [*] 会把
            // 已处理过的内容再当一次散落文本，产生重复段落。
            parts.add((isItem: false, content: content.substring(0, m.start)));
          }
          itemStart = m.end;
          sawItem = true;
        }
      } else if (token == '[/*]') {
        if (depth == 0 && itemStart >= 0) {
          parts.add((
            isItem: true,
            content: content.substring(itemStart, m.start),
          ));
          itemStart = -1;
        }
      } else if (token.startsWith('[list')) {
        depth++;
      } else {
        depth--;
      }
    }
    if (itemStart >= 0) {
      parts.add((isItem: true, content: content.substring(itemStart)));
    }
    return parts;
  }

  /// 有序列表前缀：`1.` / `a.` / `A.`；其它类型（如 `i`/`I`）回退为十进制
  String _orderedLabel(String type, int index) {
    switch (type) {
      case 'a':
        return _letters(index).toLowerCase();
      case 'A':
        return _letters(index);
      default:
        return '$index';
    }
  }

  /// 内容块标识 — 橙色标签 + 换行 + 内容
  /// 用于 quote / free / hide 等块级 BBCode
  String _labelBlock(String label, String content) {
    return '<span style="color:#FF9900">$label:</span><br>$content';
  }
}

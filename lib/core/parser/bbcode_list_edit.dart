/// `[list]` 文本转换 —— 「把段落变成列表」与「取消列表」的纯函数。
///
/// 为什么必须有：`[list]` 的项分隔符是 `[*]`，而渲染层按 `[*]` 切项
/// （`bbcode2html_lists.dart` 的 `_splitListItems`）。若给 `[list]` 直接裹上一段
/// **没有 `[*]`** 的普通文字，切不出任何项 → **整段内容渲染为空**。
/// 所以"变成列表"必须同时把每行转成项，"取消列表"也必须把项标记还原成普通文本。
library;

import 'package:mtbbs/core/parser/bbcode_blocks.dart';

/// 把纯文本转成列表项文本：每个非空行前加 `[*]`。
///
/// 产出形如 `\n[*]甲\n[*]乙\n`，供调用方拼成 `[list]…[/list]`。
/// 空行会被丢弃（空行会变成空项，渲染成多余的空行）。
String toListItems(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .map((l) => '[*]$l');
  if (lines.isEmpty) return '';
  return '\n${lines.join('\n')}\n';
}

/// 把列表项文本还原为普通文本：去掉 `[*]` / `[/*]` 标记，丢弃空行。
String fromListItems(String text) {
  return text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'\[\*\]|\[/\*\]'), '').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

/// 「在列表块内按回车」的处理结果。
///
/// - [exitList] 为 false：在光标处插入 `[*]` 起了新的一项
/// - [exitList] 为 true：当前项是空的，回车应**跳出列表**（该项标记被移除；
///   若列表已无项，`[list]` 外壳也一并去掉，块退化为普通段落）
typedef ListEnterResult = ({bool exitList, String text, int cursor});

/// 判断「在列表块内按回车」该怎么处理；返回 null 表示**不拦截**，
/// 交给文本框默认行为（普通换行）。
///
/// 只在光标位于**某一项的末尾**时接管：
/// - 该项还没内容 → 跳出列表（对应"列表写完按两次回车"的自然操作）
/// - 该项已有内容 → 自动补 `[*]` 起下一项（用户不必手打 `[*]`）
///
/// `[*]` 是**项分隔符**而非行前缀：一个项里可以有多行、多个标签，
/// 所以（1）只在"起新项"时补，（2）光标在项中间时**不接管**——
/// 那时用户要的是项内换行（比如图片下面再写一行），补 `[*]` 会凭空多出编号。
ListEnterResult? handleListEnter(String raw, int cursor) {
  final parts = splitBbcodeBlocks(raw);
  if (parts.length != 1 || parts.single.tag != 'list') return null;
  if (cursor < 0 || cursor > raw.length) return null;

  // 光标所在项的开标记（最后一个位于光标之前的 [*]）
  RegExpMatch? marker;
  for (final m in RegExp(r'\[\*\]').allMatches(raw)) {
    if (m.end <= cursor) {
      marker = m;
    } else {
      break;
    }
  }
  if (marker == null) return null; // 光标在 [list] 与首个 [*] 之间，交默认行为

  // 光标之后到下一个项边界（下一个 [*] 或 [/list]）之间必须没有内容，
  // 否则光标在项中间 → 普通换行
  final boundary = _nextItemBoundary(raw, cursor);
  if (raw.substring(cursor, boundary).trim().isNotEmpty) return null;

  if (raw.substring(marker.end, cursor).trim().isEmpty) {
    // 空项 → 跳出列表：连同该项标记与它前面的换行一起去掉
    var from = marker.start;
    while (from > 0 && raw[from - 1] == '\n') {
      from--;
    }
    var text = raw.replaceRange(from, cursor, '');
    // 列表已经没有项了，外壳留着只会渲染出空行
    if (!text.contains('[*]')) {
      text = text
          .replaceFirst(RegExp(r'^\[list(?:=[^\]]*)?\]'), '')
          .replaceFirst(RegExp(r'\[/list\]$'), '');
    }
    final close = text.indexOf('[/list]');
    return (
      exitList: true,
      text: text,
      cursor: close < 0 ? text.length : close + '[/list]'.length,
    );
  }

  // 项末尾 → 起新项，光标落到新 [*] 之后
  const insert = '\n[*]';
  return (
    exitList: false,
    text: raw.replaceRange(cursor, cursor, insert),
    cursor: cursor + insert.length,
  );
}

/// 光标之后的第一个项边界（下一个 `[*]` 或 `[/list]`）
int _nextItemBoundary(String raw, int cursor) {
  for (final m in RegExp(r'\[\*\]|\[/list\]').allMatches(raw)) {
    if (m.start >= cursor) return m.start;
  }
  return raw.length;
}

/// BBCode 锚点 —— 跨「编辑区 ↔ 预览区」的**结构身份**。
///
/// 这是编辑器定位功能的唯一地基。三条不可动摇的约定：
///
/// 1. **锚点不是坐标，是身份**。锚点 = 源码里的一个结构（一个段落、一张图、
///    一个引用块）。两边各自把它渲染出来；需要位置时**现场向渲染树要真实
///    坐标**（`RenderBox.localToGlobal`）。全过程不做估算、不按文字匹配、
///    不按比例换算 —— 因此不存在"帖子越长偏得越多"。
/// 2. **行内标签不影响锚点**。锚点是**原文切片**，`[b]` / `[color]` / `[url]`
///    都在切片内部，加粗、斜体、变色不会移动任何锚点边界。
/// 3. **无损**：`anchors.map((a) => a.raw).join() == 原文`，且首尾相接。
///    切分只切分、不改写，因此切完之后两边渲染的内容与整篇渲染完全同源。
///
/// 切分粒度 = 顶层块（复用 [splitBbcodeBlocks]）+ 文本块内的**空行分段**
/// + 整行加粗标题。理由：论坛正文里"段"就是作者心里的最小单位，
/// 一张图、一段引用、一行小标题各成一个锚点，标记槽不会糊成一片。
library;

import 'dart:math' as math;

import 'package:mtbbs/core/parser/bbcode_blocks.dart';
import 'package:mtbbs/core/parser/bbcode_source_lines.dart';

/// 一个锚点：一段可独立渲染、可独立定位的源码切片。
class BbAnchor {
  /// 文档序（0 基）。它就是锚点的身份：同一份源码切出来的锚点表，
  /// 编辑区与预览区拿到的是同一份，下标即对应关系。
  final int index;

  /// 结构类型。复用 [BbBlockKind]，保证"块"与"锚点"的类型判定只有一处来源。
  /// 文本块被进一步切成段落后，类型仍是 [BbBlockKind.text]。
  final BbBlockKind kind;

  /// 原文切片。`bbAnchors(s).map((a) => a.raw).join() == s` 恒成立。
  final String raw;

  /// [raw] 在原文中的起止偏移
  final int start;
  final int end;

  /// 该锚点**内容**首字符所在的源码行（0 基）。
  /// 是"段落的第一个字在第几行"，不是"切片起点在第几行"——
  /// 切片可能以空行开头，标记不该漂到上一个锚点的行尾。
  final int line;

  /// 悬停提示（该锚点开头的可见文字；纯图片/代码块等取类型名）
  final String label;

  const BbAnchor({
    required this.index,
    required this.kind,
    required this.raw,
    required this.start,
    required this.end,
    required this.line,
    required this.label,
  });

  /// 是否为普通文本段落
  bool get isParagraph => kind == BbBlockKind.text;

  @override
  String toString() => 'BbAnchor($index, $kind, ${raw.length} chars)';
}

/// 类型名（锚点自身没有可见文字时用作提示）
const _kindLabels = <BbBlockKind, String>{
  BbBlockKind.quote: '引用',
  BbBlockKind.free: '免费内容',
  BbBlockKind.hide: '隐藏内容',
  BbBlockKind.code: '代码块',
  BbBlockKind.list: '列表',
  BbBlockKind.table: '表格',
  BbBlockKind.align: '对齐块',
  BbBlockKind.image: '图片',
  BbBlockKind.attach: '附件',
  BbBlockKind.media: '音视频',
  BbBlockKind.data: '附件/数据',
  BbBlockKind.hr: '分隔线',
};

/// 整行就是一个加粗标题（`[b]…[/b]`）—— 论坛正文最常见的小节写法。
///
/// `[b]` 是行内标签、不产生块边界；不特判的话，"标题 + 正文 + 图片"这种
/// 没有空行的帖子几乎没有分段可用。
final _wholeLineBoldTitle = RegExp(
  r'^\s*\[b\][\s\S]*?\[/b\]\s*$',
  caseSensitive: false,
);

/// 标签提示最多取几个字
const _labelMaxChars = 16;

/// 把 BBCode 原文切成锚点表。
///
/// 保证（调用方可以依赖）：
/// * `anchors.map((a) => a.raw).join() == source`
/// * `anchors[i].start == anchors[i - 1].end`（首尾相接、无空隙）
/// * `anchors[i].index == i`
/// * `anchors[i].line` 单调不减（渲染顺序 = 文档顺序）
///
/// 空串输入返回空列表。
List<BbAnchor> bbAnchors(String source) {
  if (source.isEmpty) return const <BbAnchor>[];

  final lines = bbcodeSourceLines(source);
  // 先把 source 切成互不重叠、首尾相接的区间
  final ranges = <({int start, int end, BbBlockKind kind})>[];
  for (final block in splitBbcodeBlocks(source)) {
    if (!block.isText) {
      ranges.add((
        start: block.start,
        end: block.end,
        kind: bbBlockKindOf(block.tag),
      ));
      continue;
    }
    // 文本块内部再按"空行 / 整行加粗标题"分段。
    // 分段点只取**行首**，于是每段的 raw 天然把分隔空行收在自己尾部，
    // 切完拼起来还是原文。
    final starts = _paragraphStarts(source, lines, block.start, block.end);
    for (var i = 0; i < starts.length; i++) {
      ranges.add((
        start: starts[i],
        end: i + 1 < starts.length ? starts[i + 1] : block.end,
        kind: BbBlockKind.text,
      ));
    }
  }

  final merged = _mergeBlank(source, ranges);
  return [
    for (var i = 0; i < merged.length; i++)
      _anchor(source, lines, merged[i], i),
  ];
}

/// 偏移落在哪个锚点（锚点序号）；空表返回 -1。
///
/// 锚点表首尾相接、覆盖全文，所以"最后一个 `start <= offset` 的锚点"就是答案，
/// 二分即可。光标在段内任意位置移动都得到同一个锚点 —— 于是标记槽不会因为
/// 光标抖动而晃。
int bbAnchorIndexAt(List<BbAnchor> anchors, int offset) {
  if (anchors.isEmpty) return -1;
  if (offset < anchors.first.start) return -1;
  var lo = 0;
  var hi = anchors.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (anchors[mid].start <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// 纯空白区间并入相邻锚点。
///
/// 两个理由：
/// 1. 空白锚点在标记槽里没有任何意义（点不出、也认不出）
/// 2. 每多一个渲染单元就多一处空白处理差异（整篇渲染会移除紧邻块级标签的
///    `<br>`，见 docs/07 #17），把空白留在相邻锚点的切片里差异最小
List<({int start, int end, BbBlockKind kind})> _mergeBlank(
  String source,
  List<({int start, int end, BbBlockKind kind})> ranges,
) {
  final out = <({int start, int end, BbBlockKind kind})>[];
  int? leadStart; // 文档开头就是空白：把它让给后面第一个有内容的锚点
  for (final r in ranges) {
    if (_isBlank(source, r.start, r.end)) {
      if (out.isEmpty) {
        leadStart ??= r.start;
      } else {
        final prev = out.removeLast();
        out.add((start: prev.start, end: r.end, kind: prev.kind));
      }
      continue;
    }
    out.add((start: leadStart ?? r.start, end: r.end, kind: r.kind));
    leadStart = null;
  }
  // 整篇都是空白：退化成单个文本锚点，至少保证"无损"这条不变量成立
  if (out.isEmpty) {
    out.add((start: 0, end: source.length, kind: BbBlockKind.text));
  }
  return out;
}

bool _isBlank(String source, int start, int end) =>
    _firstContentOffset(source, start, end) == null;

BbAnchor _anchor(
  String source,
  List<BbSourceLine> lines,
  ({int start, int end, BbBlockKind kind}) range,
  int index,
) {
  final start = range.start;
  final end = range.end;
  final contentAt = _firstContentOffset(source, start, end);
  final line = _lineOf(lines, contentAt ?? start);
  return BbAnchor(
    index: index,
    kind: range.kind,
    raw: source.substring(start, end),
    start: start,
    end: end,
    line: line,
    label: _label(source, lines, start, end, line, range.kind),
  );
}

/// 文本块内的段落起点（升序，首个恒为 [start]）。
///
/// 段落边界只有两种：
/// * 空行之后的第一行（作者用空行分段）
/// * 整行加粗标题（论坛里的小节写法，通常不配空行）
List<int> _paragraphStarts(
  String source,
  List<BbSourceLine> lines,
  int start,
  int end,
) {
  final starts = <int>[start];
  for (var i = _lineOf(lines, start); i < lines.length; i++) {
    final lineStart = lines[i].start;
    if (lineStart >= end) break;
    if (lineStart <= start) continue; // [start] 所在行（或更前）不产生新段
    final text = lines[i].text;
    if (text.trim().isEmpty) continue;
    final blankBefore = lines[i - 1].text.trim().isEmpty;
    if (blankBefore || _wholeLineBoldTitle.hasMatch(text)) {
      if (starts.last != lineStart) starts.add(lineStart);
    }
  }
  return starts;
}

/// 该区间内第一个非空白字符的偏移；整段皆空白时返回 null
int? _firstContentOffset(String source, int start, int end) {
  for (var i = start; i < end; i++) {
    final c = source.codeUnitAt(i);
    if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return i;
  }
  return null;
}

/// 偏移所在的行号（[lines] 是同一份源码切出来的，二分即可）
int _lineOf(List<BbSourceLine> lines, int offset) {
  var lo = 0;
  var hi = lines.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (lines[mid].start <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo;
}

/// 悬停提示：先取该锚点自己开头的可见文字，取不到就退回类型名。
///
/// 刻意只在本锚点**自己的区间**里找 —— 不往下跨锚点找。
/// 跨锚点找会让"纯图片锚点"顶着下一段的文字，反而认不出。
String _label(
  String source,
  List<BbSourceLine> lines,
  int start,
  int end,
  int line,
  BbBlockKind kind,
) {
  final text = lines[line].text;
  final from = math.max(start, lines[line].start);
  final to = math.min(end, lines[line].start + text.length);
  if (from < to) {
    final visible = bbcodeLineVisibleText(source.substring(from, to));
    if (visible.isNotEmpty) {
      return visible.length <= _labelMaxChars
          ? visible
          : '${visible.substring(0, _labelMaxChars)}…';
    }
  }
  return _kindLabels[kind] ?? '';
}

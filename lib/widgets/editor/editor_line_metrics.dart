import 'package:flutter/rendering.dart';
import 'package:mtbbs/core/parser/bbcode_source_lines.dart';

/// 编辑区「源码行 → y」测量：直接向 `RenderEditable` 要光标矩形。
///
/// 为什么不自己用 `TextPainter` 复刻布局：编辑区是**软换行**的 TextField，
/// 一个源码行可能占多个视觉行；复刻字体、行高、内边距、可用宽度，迟早对不上。
/// `getLocalRectForCaret` 返回的是真实布局结果，天然对齐（含软换行与滚动）。
///
/// y 以 [measure] 传入的 [container] 顶边为原点 —— 调用方把行号槽放在同一个
/// 容器里，就能直接用这些 y 去 `Positioned`。
class EditorLineMetrics {
  final Map<int, double> _yByLine;

  const EditorLineMetrics._(this._yByLine);

  static const empty = EditorLineMetrics._({});

  /// 该源码行的 y（容器坐标系）；拿不到返回 null
  double? yOf(int line) => _yByLine[line];

  int get measuredLines => _yByLine.length;

  /// [container] 是行号槽所在的坐标系容器；[editableRoot] 是编辑框的渲染根
  /// （从它往下找 `RenderEditable`）。
  static EditorLineMetrics measure({
    required RenderBox? container,
    required RenderObject? editableRoot,
    required List<BbSourceLine> lines,
  }) {
    if (container == null || editableRoot == null || lines.isEmpty) return empty;
    final editable = _findEditable(editableRoot);
    if (editable == null || !editable.hasSize) return empty;

    final containerTop = container.localToGlobal(Offset.zero).dy;
    final yByLine = <int, double>{};
    for (var line = 0; line < lines.length; line++) {
      final rect = editable.getLocalRectForCaret(
        TextPosition(offset: lines[line].start),
      );
      yByLine[line] =
          editable.localToGlobal(rect.topLeft).dy - containerTop;
    }
    return EditorLineMetrics._(yByLine);
  }

  static RenderEditable? _findEditable(RenderObject node) {
    if (node is RenderEditable) return node;
    RenderEditable? found;
    node.visitChildren((child) {
      found ??= _findEditable(child);
    });
    return found;
  }
}

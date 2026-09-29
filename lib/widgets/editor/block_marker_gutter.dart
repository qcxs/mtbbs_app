import 'package:flutter/material.dart';

/// 标记槽宽度 —— 编辑区与预览区保持一致，两边看着才像同一套坐标。
///
/// 只有圆点和箭头，比行号窄得多，正文也能往左挪一点。
const double kMarkerGutterWidth = 20;

/// 一个标记：**锚点身份** + 它在宿主坐标系里的 y + 悬停提示。
///
/// [id] 是锚点序号（见 `bbcode_anchors.dart`），在两个区里指的是同一个锚点 ——
/// 这就是跨区定位的全部依据。y 只是"画在哪"，不参与对应关系。
typedef BlockMark = ({int id, double y, String label});

/// 锚点标记槽 —— 编辑区与预览区共用。
///
/// **为什么不是行号**：预览与源码之间只能做到元素/段落级对应（同一个源码行
/// 可能渲染成 0 行图片或 N 行换行文字），逐行数字必然对不齐；而且长文里
/// 一列数字既糊又占地方。改成标记后：能互相定位就够了。
///
/// - 每个 [marks] 项在它的 y 处显示一个圆点
/// - [activeId] 所在的标记换成箭头（当前在这）
/// - 点标记 → [onTapId]，跳到另一个区的对应锚点
/// - 悬停显示该锚点开头几个字，便于辨认
/// - y 太近的标记会被跳过（防止叠在一起）
///
/// ⚠️ 两件事别改坏：
/// 1. 必须放在宿主 `Stack` 的**非负位置**（`left: 0`），用内边距给正文让位。
///    越界子树能画出来但**点不到**（`RenderBox.hitTest` 先判 `size.contains`）。
/// 2. 整体包了 [ExcludeSemantics]（整个 App 已在 main.dart 全局关闭无障碍，
///    见 docs/07 #70，这里是局部兜底）。这些标记是纯装饰、却在测量/滚动时频繁
///    增删，让它们进语义树只会让 Windows 无障碍桥的 AXTree 反复失效。
///    手势不受影响。
class BlockMarkerGutter extends StatelessWidget {
  /// 可标记的锚点（y 为宿主坐标系，按 id 升序）
  final List<BlockMark> marks;

  /// 当前锚点（显示为箭头）
  final int? activeId;

  final ValueChanged<int> onTapId;

  final double width;

  /// 标记间最小垂直间隔，小于它就跳过（防重叠）
  final double minGap;

  const BlockMarkerGutter({
    super.key,
    required this.marks,
    required this.onTapId,
    this.activeId,
    this.width = kMarkerGutterWidth,
    this.minGap = 14,
  });

  static const double _rowHeight = 16;

  /// 取 [id] 所在的标记：不大于它的最后一个（id 即文档序，于是"当前锚点"
  /// 就一定落在某个标记上；即使该锚点自己没有标记也会退到上一个）
  static int? activeMarkId(List<BlockMark> marks, int? id) {
    if (id == null) return null;
    int? best;
    for (final m in marks) {
      if (m.id <= id) {
        best = m.id;
      } else {
        break;
      }
    }
    return best ?? (marks.isEmpty ? null : marks.first.id);
  }

  /// 实际显示哪些标记：当前锚点必留，其余按 y 升序尽量塞，太近的跳过
  @visibleForTesting
  static List<BlockMark> visibleMarks(
    List<BlockMark> marks,
    int? activeId, {
    double minGap = 14,
  }) {
    final active = activeMarkId(marks, activeId);
    BlockMark? activeMark;
    for (final m in marks) {
      if (m.id == active) activeMark = m;
    }
    final visible = <BlockMark>[];
    var lastY = double.negativeInfinity;
    for (final m in marks) {
      if (m.id == active) continue;
      if (m.y - lastY < minGap) continue;
      if (activeMark != null && (m.y - activeMark.y).abs() < minGap) continue;
      visible.add(m);
      lastY = m.y;
    }
    if (activeMark != null) visible.add(activeMark);
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = activeMarkId(marks, activeId);
    final shown = visibleMarks(marks, activeId, minGap: minGap);

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final m in shown)
              Positioned(
                top: m.y,
                left: 0,
                right: 0,
                height: _rowHeight,
                child: _mark(context, cs, m, active),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mark(BuildContext context, ColorScheme cs, BlockMark m, int? active) {
    final isActive = m.id == active;
    final content = Align(
      alignment: Alignment.center,
      child: isActive
          ? Icon(Icons.arrow_right, size: 18, color: cs.primary)
          // 直径刻意给足、颜色不给太淡：太小太浅在浅色背景上根本看不见
          : Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTapId(m.id),
      child: m.label.isEmpty
          ? content
          : Tooltip(
              message: m.label,
              waitDuration: const Duration(milliseconds: 500),
              // 提示只是给人看的：给每个标记建 AX 节点会让无障碍树剧烈抖动
              excludeFromSemantics: true,
              child: content,
            ),
    );
  }
}

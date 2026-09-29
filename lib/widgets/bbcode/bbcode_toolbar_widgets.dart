part of 'bbcode_toolbar.dart';

/// 工具栏回调控制器 — 所有操作通过 [onAction] 派发
class BBCodeToolbarController {
  final void Function(ToolbarAction) onAction;

  const BBCodeToolbarController({required this.onAction});
}

/// 颜色选择面板 — 小方格排列，自动换行
class ColorPickerPanel extends StatelessWidget {
  final void Function(Color color) onPicked;
  final double cellSize;
  final String title;

  const ColorPickerPanel({
    super.key,
    required this.onPicked,
    this.cellSize = 28,
    this.title = '选择颜色',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: bbcodeCommonColors.map((c) {
            return GestureDetector(
              onTap: () => onPicked(c),
              child: Container(
                width: cellSize,
                height: cellSize,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

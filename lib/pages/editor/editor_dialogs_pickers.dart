part of 'editor_dialogs.dart';

/// 显示字体大小选择对话框
void showFontSizePicker(
  BuildContext context,
  BBCodeController contentCtl,
  VoidCallback onFocusContent,
) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 360),
      title: Row(
        children: [
          const Expanded(child: Text('字体大小')),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(ctx).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [1, 2, 3, 4, 5, 6, 7].map((level) {
          final labels = {
            1: '极小',
            2: '较小',
            3: '普通',
            4: '较大',
            5: '很大',
            6: '特大',
            7: '极大',
          };
          final sampleSizes = {
            1: 11.0,
            2: 13.0,
            3: 15.0,
            4: 17.0,
            5: 20.0,
            6: 24.0,
            7: 30.0,
          };
          return ListTile(
            dense: true,
            title: Text(
              '${labels[level]} ($level)',
              style: TextStyle(fontSize: sampleSizes[level]),
            ),
            onTap: () {
              contentCtl.wrapParam('size', level.toString(), '[/size]');
              onFocusContent();
              Navigator.of(ctx).pop();
            },
          );
        }).toList(),
      ),
    ),
  );
}

/// 显示颜色选择对话框
void showColorPickerDialog(
  BuildContext context,
  BBCodeController contentCtl,
  VoidCallback onFocusContent, {
  required bool isBackcolor,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 360),
      title: Row(
        children: [
          Expanded(child: Text(isBackcolor ? '选择背景色' : '选择文字颜色')),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(ctx).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: ColorPickerPanel(
        title: '',
        onPicked: (color) {
          final hex = color.value.toRadixString(16).substring(2).toUpperCase();
          if (isBackcolor) {
            contentCtl.wrapParam('backcolor', '#$hex', '[/backcolor]');
          } else {
            contentCtl.wrapParam('color', '#$hex', '[/color]');
          }
          onFocusContent();
          Navigator.of(ctx).pop();
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

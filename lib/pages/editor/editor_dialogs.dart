import 'package:flutter/material.dart';

import 'package:mtbbs/widgets/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode_toolbar.dart';

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

/// 显示内联输入对话框（加粗/斜体/下划线/删除线）
void showInlineInputDialog(
  BuildContext context,
  String openTag,
  String closeTag,
  String dialogTitle,
  String hint,
  BBCodeController contentCtl,
  VoidCallback onFocusContent,
) {
  final textCtl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Row(
        children: [
          Expanded(child: Text(dialogTitle)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              textCtl.dispose();
              Navigator.of(ctx).pop();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: TextField(
        controller: textCtl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) {
            contentCtl.wrapInline(openTag, closeTag, value.trim());
            onFocusContent();
            textCtl.dispose();
            Navigator.of(ctx).pop();
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () {
            textCtl.dispose();
            Navigator.of(ctx).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = textCtl.text.trim();
            if (value.isNotEmpty) {
              contentCtl.wrapInline(openTag, closeTag, value);
              onFocusContent();
              textCtl.dispose();
              Navigator.of(ctx).pop();
            }
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 显示文本输入对话框（链接/图片URL等，支持双输入框）
void showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String hint,
  required String value,
  String? secondLabel,
  String? secondHint,
  String? secondValue,
  required void Function(String, String) onSubmit,
}) {
  final urlCtl = TextEditingController(text: value);
  final textCtl = TextEditingController(text: secondValue ?? '');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              urlCtl.dispose();
              textCtl.dispose();
              Navigator.of(ctx).pop();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: urlCtl,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            autofocus: true,
          ),
          if (secondLabel != null) ...[
            Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.swap_vert,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  tooltip: '交换',
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    final tmp = urlCtl.text;
                    urlCtl.text = textCtl.text;
                    textCtl.text = tmp;
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: textCtl,
              decoration: InputDecoration(
                labelText: secondLabel,
                hintText: secondHint ?? '',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            urlCtl.dispose();
            textCtl.dispose();
            Navigator.of(ctx).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final url = urlCtl.text.trim();
            final text = textCtl.text.trim();
            urlCtl.dispose();
            textCtl.dispose();
            Navigator.of(ctx).pop();
            onSubmit(url, text);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 显示页面信息对话框
void showPageInfoDialog(BuildContext context, Map<String, dynamic> fields) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('页面信息'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fields.entries
              .where((e) => e.value.toString().isNotEmpty)
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          e.key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          e.value.toString(),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 显示退出确认对话框
///
/// 返回：'save'=保存退出，'discard'=放弃退出，null=取消
Future<String?> showExitConfirmDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: const Row(
        children: [
          Expanded(
            child: Text(
              '内容已修改',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: const Text('是否保存当前修改？放弃的修改可在编辑历史中恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop('discard'),
          child: const Text('放弃'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop('save');
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_toolbar.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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
  showDialog(
    context: context,
    builder: (_) => _InlineInputDialog(
      openTag: openTag,
      closeTag: closeTag,
      dialogTitle: dialogTitle,
      hint: hint,
      contentCtl: contentCtl,
      onFocusContent: onFocusContent,
    ),
  );
}

/// 内联输入弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：pop 之后弹窗仍在退场动画中、
/// 子树仍会重建（插入内容会重建编辑器与预览），在 pop 前后提前 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _InlineInputDialog extends StatefulWidget {
  const _InlineInputDialog({
    required this.openTag,
    required this.closeTag,
    required this.dialogTitle,
    required this.hint,
    required this.contentCtl,
    required this.onFocusContent,
  });

  final String openTag;
  final String closeTag;
  final String dialogTitle;
  final String hint;
  final BBCodeController contentCtl;
  final VoidCallback onFocusContent;

  @override
  State<_InlineInputDialog> createState() => _InlineInputDialogState();
}

class _InlineInputDialogState extends State<_InlineInputDialog> {
  final _textCtl = TextEditingController();

  @override
  void dispose() {
    _textCtl.dispose();
    super.dispose();
  }

  /// 写入 BBCode 并关闭；内容为空时不动作（保持弹窗打开）
  void _submit(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    widget.contentCtl.wrapInline(widget.openTag, widget.closeTag, v);
    widget.onFocusContent();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Row(
        children: [
          Expanded(child: Text(widget.dialogTitle)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: TextField(
        controller: _textCtl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => _submit(_textCtl.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
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
  showDialog(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      label: label,
      hint: hint,
      value: value,
      secondLabel: secondLabel,
      secondHint: secondHint,
      secondValue: secondValue,
      onSubmit: onSubmit,
    ),
  );
}

/// 文本输入弹窗内容（单个或双输入框）
///
/// 控制器由本 State 持有，理由同 [_InlineInputDialog]。
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.value,
    this.secondLabel,
    this.secondHint,
    this.secondValue,
    required this.onSubmit,
  });

  final String title;
  final String label;
  final String hint;
  final String value;
  final String? secondLabel;
  final String? secondHint;
  final String? secondValue;
  final void Function(String, String) onSubmit;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _urlCtl = TextEditingController(
    text: widget.value,
  );
  late final TextEditingController _textCtl = TextEditingController(
    text: widget.secondValue ?? '',
  );

  @override
  void dispose() {
    _urlCtl.dispose();
    _textCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlCtl.text.trim();
    final text = _textCtl.text.trim();
    Navigator.of(context).pop();
    widget.onSubmit(url, text);
  }

  void _swap() {
    final tmp = _urlCtl.text;
    _urlCtl.text = _textCtl.text;
    _textCtl.text = tmp;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlCtl,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            autofocus: true,
          ),
          if (widget.secondLabel != null) ...[
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
                  onPressed: _swap,
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _textCtl,
              decoration: InputDecoration(
                labelText: widget.secondLabel,
                hintText: widget.secondHint ?? '',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
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

/// 显示原始 BBCode 预览对话框（长按预览内容触发）
void showRawBbcodeDialog(BuildContext context, String bbcode) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.code, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('预览 BBCode', style: TextStyle(fontSize: 16)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(ctx).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(
          bbcode,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.5,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: bbcode));
            showToast('已复制');
            Navigator.of(ctx).pop();
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

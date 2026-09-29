part of 'editor_dialogs.dart';

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

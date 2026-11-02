import 'package:flutter/material.dart';

import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 通用多行文本输入弹窗。
///
/// 返回去除首尾空白后的文本；取消或内容为空返回 null。
///
/// 主要用于「读取剪切板失败 / 剪贴板为空」时的降级入口：弹窗内既可以手动
/// 输入，也可以点「读取剪切板」重试，避免用户只能退出流程重新复制。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? hintText,
  String initialText = '',
  int maxLines = 8,
  String confirmText = '确定',
  bool monospace = false,
  bool readClipboard = true,
  double maxWidth = 420,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(
      title: title,
      message: message,
      hintText: hintText,
      initialText: initialText,
      maxLines: maxLines,
      confirmText: confirmText,
      monospace: monospace,
      readClipboard: readClipboard,
      maxWidth: maxWidth,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    this.message,
    this.hintText,
    required this.initialText,
    required this.maxLines,
    required this.confirmText,
    required this.monospace,
    required this.readClipboard,
    required this.maxWidth,
  });

  final String title;
  final String? message;
  final String? hintText;
  final String initialText;
  final int maxLines;
  final String confirmText;
  final bool monospace;
  final bool readClipboard;
  final double maxWidth;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final text = await ClipboardHelper.read();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      showToast('剪切板为空或无法读取');
      return;
    }
    _ctl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
    showToast('已读取剪切板内容');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSubmit = _ctl.text.trim().isNotEmpty;
    return AlertDialog(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      title: Text(widget.title),
      // 内容可能很长（JSON / 多行文本），必须可滚动（docs/07 #92）
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _ctl,
              autofocus: true,
              maxLines: widget.maxLines,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                fontSize: widget.monospace ? 11 : 13,
                fontFamily: widget.monospace ? 'monospace' : null,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.readClipboard)
          TextButton.icon(
            onPressed: _pasteFromClipboard,
            icon: const Icon(Icons.content_paste, size: 16),
            label: const Text('读取剪切板'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSubmit
              ? () => Navigator.of(context).pop(_ctl.text.trim())
              : null,
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

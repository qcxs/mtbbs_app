import 'package:flutter/material.dart';

/// 通用跳转页码对话框。
///
/// 输入页码后校验范围（1 ~ [totalPages]，[totalPages]<=0 表示未知不限上限），
/// 合法则关闭对话框并回调 [onGoToPage]。
Future<void> showPageJumpDialog(
  BuildContext context, {
  required int currentPage,
  int totalPages = 0,
  required void Function(int page) onGoToPage,
  String title = '跳转页',
  String? initialText,
  bool autofocus = false,
  bool showSummary = true,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PageJumpDialog(
      currentPage: currentPage,
      totalPages: totalPages,
      onGoToPage: onGoToPage,
      title: title,
      initialText: initialText,
      autofocus: autofocus,
      showSummary: showSummary,
    ),
  );
}

/// 页码跳转弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：pop 只完成 Future，
/// 弹窗退场动画期间子树仍在；提前或延后 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _PageJumpDialog extends StatefulWidget {
  const _PageJumpDialog({
    required this.currentPage,
    required this.totalPages,
    required this.onGoToPage,
    required this.title,
    required this.initialText,
    required this.autofocus,
    required this.showSummary,
  });

  final int currentPage;
  final int totalPages;
  final void Function(int page) onGoToPage;
  final String title;
  final String? initialText;
  final bool autofocus;
  final bool showSummary;

  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController _tc = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  /// 校验合法才关闭并回调；页码非法时保持弹窗打开
  void _submit() {
    final p = int.tryParse(_tc.text);
    if (p != null &&
        p >= 1 &&
        (widget.totalPages <= 0 || p <= widget.totalPages)) {
      Navigator.of(context).pop();
      widget.onGoToPage(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showSummary &&
              (widget.totalPages > 0 || widget.currentPage > 0)) ...[
            Text(
              widget.totalPages > 0
                  ? '共 ${widget.totalPages} 页，当前第 ${widget.currentPage} 页'
                  : '当前第 ${widget.currentPage} 页',
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _tc,
            autofocus: widget.autofocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: widget.totalPages > 0
                  ? '输入页码 (1-${widget.totalPages})'
                  : '输入页码',
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('跳转')),
      ],
    );
  }
}

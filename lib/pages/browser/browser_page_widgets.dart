part of 'browser_page.dart';

/// URL 编辑弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：pop 只完成 Future，
/// 弹窗退场动画期间子树仍在；提前或延后 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _UrlEditorDialog extends StatefulWidget {
  const _UrlEditorDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_UrlEditorDialog> createState() => _UrlEditorDialogState();
}

class _UrlEditorDialogState extends State<_UrlEditorDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialUrl,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入网址'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'https://...',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('前往'),
        ),
      ],
    );
  }
}

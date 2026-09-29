part of 'web_login_page.dart';

/// URL 输入弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：pop 只完成 Future，
/// 弹窗退场动画期间子树仍在；提前或延后 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _UrlInputDialog extends StatefulWidget {
  const _UrlInputDialog({
    required this.initialUrl,
    required this.cs,
    required this.onNavigate,
  });

  final String initialUrl;
  final ColorScheme cs;
  final void Function(String text) onNavigate;

  @override
  State<_UrlInputDialog> createState() => _UrlInputDialogState();
}

class _UrlInputDialogState extends State<_UrlInputDialog> {
  late final TextEditingController _ctl = TextEditingController(
    text: widget.initialUrl,
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// 先关闭弹窗，再取本控制器文本回调（与弹窗打开时的时序一致）
  void _navigate() {
    Navigator.of(context).pop();
    widget.onNavigate(_ctl.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入网址'),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.go,
        decoration: InputDecoration(
          hintText: 'https://...',
          border: const OutlineInputBorder(),
          isDense: true,
          fillColor: widget.cs.surfaceContainerHighest.withValues(alpha: 0.5),
          filled: true,
        ),
        onSubmitted: (_) => _navigate(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _navigate, child: const Text('前往')),
      ],
    );
  }
}

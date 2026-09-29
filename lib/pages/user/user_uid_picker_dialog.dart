import 'package:flutter/material.dart';

/// UID 跳转弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：pop 只完成 Future，
/// 弹窗退场动画期间子树仍在；提前或延后 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class UidPickerDialog extends StatefulWidget {
  const UidPickerDialog({super.key, required this.onNavigateToUid});

  final void Function(int uid) onNavigateToUid;

  @override
  State<UidPickerDialog> createState() => _UidPickerDialogState();
}

class _UidPickerDialogState extends State<UidPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// UID 合法才关闭并跳转；非法时保持弹窗打开
  void _submit() {
    final uid = int.tryParse(_controller.text);
    if (uid != null && uid > 0) {
      Navigator.of(context).pop();
      widget.onNavigateToUid(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳转用户'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '输入 UID',
          border: OutlineInputBorder(),
          isDense: true,
        ),
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

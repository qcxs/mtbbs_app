import 'package:flutter/material.dart';

/// 收藏备注输入弹窗（仿手机端收藏弹窗，可填备注后提交）
///
/// 返回备注文本；用户取消返回 null；空备注返回空字符串（表示收藏但不备注）。
class FavoriteNoteDialog extends StatefulWidget {
  final String tid;

  const FavoriteNoteDialog({super.key, required this.tid});

  @override
  State<FavoriteNoteDialog> createState() => _FavoriteNoteDialogState();
}

class _FavoriteNoteDialogState extends State<FavoriteNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('收藏帖子 #${widget.tid}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 100,
        decoration: const InputDecoration(
          hintText: '备注（可选）',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('收藏'),
        ),
      ],
    );
  }
}

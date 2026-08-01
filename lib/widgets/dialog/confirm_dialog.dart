import 'package:flutter/material.dart';

/// 通用确认对话框。
///
/// 返回 `true` 表示确认，`false`/`null` 表示取消。
/// [danger] 为 true 时确认按钮使用错误色。
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
  double maxWidth = 400,
  TextStyle? titleStyle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: BoxConstraints(maxWidth: maxWidth),
      title: Text(title, style: titleStyle),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          child: Text(confirmText),
        ),
      ],
    ),
  );
}

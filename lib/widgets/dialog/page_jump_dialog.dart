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
  final tc = TextEditingController(text: initialText);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSummary && (totalPages > 0 || currentPage > 0)) ...[
            Text(
              totalPages > 0
                  ? '共 $totalPages 页，当前第 $currentPage 页'
                  : '当前第 $currentPage 页',
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: tc,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: totalPages > 0 ? '输入页码 (1-$totalPages)' : '输入页码',
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
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final p = int.tryParse(tc.text);
            if (p != null && p >= 1 && (totalPages <= 0 || p <= totalPages)) {
              Navigator.of(ctx).pop();
              onGoToPage(p);
            }
          },
          child: const Text('跳转'),
        ),
      ],
    ),
  );
}

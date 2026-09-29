import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_toolbar.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

part 'editor_dialogs_input.dart';
part 'editor_dialogs_pickers.dart';

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

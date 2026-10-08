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

/// 发布前拦下「不兼容 Emoji」（4 字节字符）。
///
/// 返回 true = 用户选择删除 Emoji。注意：**本次提交一律被阻止**，删除后由用户
/// 自行再次发布（内容已改动，可通过「撤销」反悔）。
Future<bool> showIncompatibleEmojiDialog(
  BuildContext context,
  int emojiCount,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '包含不兼容的 Emoji',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Text(
        '正文里有 $emojiCount 个 Emoji，提交后可能被站点截断。\n\n'
        '可以先删除它们再发布，删除后可用「撤销」恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('先不改'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('删除 $emojiCount 个 Emoji'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 发布前提醒「已上传但未插入正文」的图片 / 附件。
///
/// 返回 true = 继续发布（这些内容会由 `attachnew` 追加到正文末尾）。
Future<bool> showUninsertedMediaDialog(
  BuildContext context, {
  required int imageCount,
  required int attachCount,
}) async {
  final parts = [
    if (imageCount > 0) '$imageCount 张图片',
    if (attachCount > 0) '$attachCount 个附件',
  ].join('、');
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: const Row(
        children: [
          Icon(Icons.attachment_outlined, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '有内容未插入正文',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: Text('$parts 还没有插入到正文。继续发布的话，它们会被自动追加到正文末尾。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('返回插入'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('追加并发布'),
        ),
      ],
    ),
  );
  return result ?? false;
}

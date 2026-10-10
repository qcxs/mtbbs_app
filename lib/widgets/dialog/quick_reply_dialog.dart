import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 常用语条目：显示文本（[ManagedItem.name]）与实际插入内容（`data['insert']`）。
///
/// 二者可不同，用于"显示'感谢分享'、插入美化后的 BBCode"。
String quickReplyInsertOf(ManagedItem item) {
  final v = item.data?['insert'];
  if (v is String && v.trim().isNotEmpty) return v;
  return item.name;
}

/// 常用语选择弹窗：列出当前可见常用语，点选后把其"插入内容"写入 [contentCtl]。
///
/// 完整版与迷你版共用（作为工具栏项 `quickReply` 的动作）。弹窗右上角有设置
/// 入口，直达编辑器设置以管理常用语。
Future<void> showQuickReplyPicker(
  BuildContext context,
  BBCodeController contentCtl,
  VoidCallback focus,
) async {
  final replies = context
      .read<SettingsProvider>()
      .quickReplies
      .where((e) => e.visible)
      .toList();
  if (replies.isEmpty) {
    showToast('暂无常用语，可在设置中添加');
    return;
  }
  final picked = await showDialog<ManagedItem>(
    context: context,
    builder: (dctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
      title: Row(
        children: [
          const Expanded(child: Text('常用语')),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '常用语设置',
            onPressed: () {
              Navigator.of(dctx).pop();
              context.push('/settings/editor');
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: '关闭',
            onPressed: () => Navigator.of(dctx).pop(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in replies)
              ListTile(
                dense: true,
                title: Text(r.name),
                subtitle: quickReplyInsertOf(r) == r.name
                    ? null
                    : Text(
                        quickReplyInsertOf(r),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                onTap: () => Navigator.of(dctx).pop(r),
              ),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return;
  contentCtl.wrapInline('', '', quickReplyInsertOf(picked));
  focus();
}

/// 新增 / 编辑「常用语」弹窗。
///
/// - 显示文本：≤ [kQuickReplyMaxLength]
/// - 插入内容：可选，≤ [kQuickReplyInsertMaxLength]；留空则插入显示文本
///
/// 返回 null 表示取消 / 显示文本为空。
Future<ManagedItem?> showQuickReplyDialog(
  BuildContext context, {
  ManagedItem? initial,
}) async {
  final result = await showDialog<ManagedItem>(
    context: context,
    builder: (_) => _QuickReplyDialog(initial: initial),
  );
  return result;
}

class _QuickReplyDialog extends StatefulWidget {
  final ManagedItem? initial;
  const _QuickReplyDialog({this.initial});

  @override
  State<_QuickReplyDialog> createState() => _QuickReplyDialogState();
}

class _QuickReplyDialogState extends State<_QuickReplyDialog> {
  late final TextEditingController _labelCtl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _insertCtl = TextEditingController(
    text: widget.initial?.data?['insert']?.toString() ?? '',
  );

  @override
  void dispose() {
    _labelCtl.dispose();
    _insertCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelCtl.text.trim();
    if (label.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final insert = _insertCtl.text.trim();
    Navigator.of(context).pop(
      ManagedItem(
        id: widget.initial?.id ?? 'qr_${DateTime.now().millisecondsSinceEpoch}',
        name: label.length > kQuickReplyMaxLength
            ? label.substring(0, kQuickReplyMaxLength)
            : label,
        visible: widget.initial?.visible ?? true,
        data: insert.isEmpty ? null : {'insert': insert},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 400),
      title: Text(widget.initial == null ? '新增常用语' : '编辑常用语'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _labelCtl,
              autofocus: true,
              maxLength: kQuickReplyMaxLength,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '显示文本',
                hintText: '如：感谢分享',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _insertCtl,
              maxLength: kQuickReplyInsertMaxLength,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '插入内容（可选）',
                hintText: '留空则插入显示文本；可填 BBCode，如 [b]感谢分享[/b]',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

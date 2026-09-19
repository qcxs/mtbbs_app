import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';

/// 快捷链接管理对话框 — 独立组件，可在任意页面调用
class ShortcutLinksDialog {
  static void show(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    showManagedListDialog(
      context: context,
      title: '快捷链接',
      items: settings.shortcutLinks,
      allowAdd: true,
      allowDelete: true,
      allowEdit: true,
      allowReorder: true,
      allowToggleVisibility: true,
      itemBuilder: (item, isVisible) => Text(
        item.name,
        style: TextStyle(color: isVisible ? null : cs.onSurfaceVariant),
      ),
      onAdd: () => _handleAdd(context, settings),
      onEdit: (item) => _handleEdit(context, settings, item),
      onReorder: (from, to) => settings.moveShortcutLink(from, to),
      onDelete: (id) async {
        await settings.removeShortcutLink(id);
        return true;
      },
    );
  }

  static Future<ManagedItem?> _handleAdd(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final added = await _showForm(
      context: context,
      title: '添加快捷链接',
      name: '',
      url: '',
      imageUrl: '',
      submitLabel: '添加',
      onSubmit: (name, url, imageUrl) {
        if (name.trim().isEmpty) return null;
        return ManagedItem(
          id: 'link_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}',
          name: name.trim(),
          data: {
            'url': url.trim(),
            if (imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
          },
        );
      },
    );
    if (added != null) await settings.addShortcutLink(added);
    return null;
  }

  static Future<ManagedItem?> _handleEdit(
    BuildContext context,
    SettingsProvider settings,
    ManagedItem item,
  ) async {
    final edited = await _showForm(
      context: context,
      title: '编辑快捷链接',
      name: item.name,
      url: item.data?['url']?.toString() ?? '',
      imageUrl: item.data?['imageUrl']?.toString() ?? '',
      submitLabel: '保存',
      onSubmit: (name, url, imageUrl) {
        if (name.trim().isEmpty) return null;
        return item.copyWith(
          name: name.trim(),
          data: {
            'url': url.trim(),
            if (imageUrl.trim().isNotEmpty) 'imageUrl': imageUrl.trim(),
          },
        );
      },
    );
    if (edited != null) await settings.updateShortcutLink(item.id, edited);
    return null;
  }

  static Future<ManagedItem?> _showForm({
    required BuildContext context,
    required String title,
    required String name,
    required String url,
    required String imageUrl,
    required String submitLabel,
    required ManagedItem? Function(String name, String url, String imageUrl)
    onSubmit,
  }) {
    return showDialog<ManagedItem>(
      context: context,
      builder: (_) => _ShortcutLinkFormDialog(
        title: title,
        name: name,
        url: url,
        imageUrl: imageUrl,
        submitLabel: submitLabel,
        onSubmit: onSubmit,
      ),
    );
  }
}

/// 快捷链接表单弹窗内容
///
/// 三个控制器由本 State 持有、随弹窗子树卸载才释放：pop 之后弹窗仍在退场动画中、
/// 子树仍会重建（保存设置会触发 notifyListeners 重建 MaterialApp），在 pop 前后
/// 提前 dispose 会抛「A TextEditingController was used after being disposed」。
class _ShortcutLinkFormDialog extends StatefulWidget {
  const _ShortcutLinkFormDialog({
    required this.title,
    required this.name,
    required this.url,
    required this.imageUrl,
    required this.submitLabel,
    required this.onSubmit,
  });

  final String title;
  final String name;
  final String url;
  final String imageUrl;
  final String submitLabel;
  final ManagedItem? Function(String name, String url, String imageUrl)
  onSubmit;

  @override
  State<_ShortcutLinkFormDialog> createState() =>
      _ShortcutLinkFormDialogState();
}

class _ShortcutLinkFormDialogState extends State<_ShortcutLinkFormDialog> {
  late final TextEditingController _nameCtl = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _urlCtl = TextEditingController(
    text: widget.url,
  );
  late final TextEditingController _imgCtl = TextEditingController(
    text: widget.imageUrl,
  );

  @override
  void dispose() {
    _nameCtl.dispose();
    _urlCtl.dispose();
    _imgCtl.dispose();
    super.dispose();
  }

  /// 提交：onSubmit 返回 null（名称为空）时不关闭弹窗
  void _submit() {
    final result = widget.onSubmit(_nameCtl.text, _urlCtl.text, _imgCtl.text);
    if (result != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtl,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtl,
            decoration: const InputDecoration(
              labelText: '链接 URL',
              hintText: 'https://... 或 /thread/xxx',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _imgCtl,
            decoration: const InputDecoration(
              labelText: '图标 URL（可选）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}

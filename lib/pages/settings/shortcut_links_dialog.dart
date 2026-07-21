import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/managed_item.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/managed_list_dialog.dart';

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
    final nameCtl = TextEditingController();
    final urlCtl = TextEditingController();
    final imgCtl = TextEditingController();
    final added = await _showForm(
      context: context,
      title: '添加快捷链接',
      nameCtl: nameCtl,
      urlCtl: urlCtl,
      imgCtl: imgCtl,
      submitLabel: '添加',
      onSubmit: () {
        if (nameCtl.text.trim().isEmpty) return null;
        return ManagedItem(
          id:
              'link_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}',
          name: nameCtl.text.trim(),
          data: {
            'url': urlCtl.text.trim(),
            if (imgCtl.text.trim().isNotEmpty) 'imageUrl': imgCtl.text.trim(),
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
    final nameCtl = TextEditingController(text: item.name);
    final urlCtl =
        TextEditingController(text: item.data?['url']?.toString() ?? '');
    final imgCtl =
        TextEditingController(text: item.data?['imageUrl']?.toString() ?? '');
    final edited = await _showForm(
      context: context,
      title: '编辑快捷链接',
      nameCtl: nameCtl,
      urlCtl: urlCtl,
      imgCtl: imgCtl,
      submitLabel: '保存',
      onSubmit: () {
        if (nameCtl.text.trim().isEmpty) return null;
        return item.copyWith(
          name: nameCtl.text.trim(),
          data: {
            'url': urlCtl.text.trim(),
            if (imgCtl.text.trim().isNotEmpty) 'imageUrl': imgCtl.text.trim(),
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
    required TextEditingController nameCtl,
    required TextEditingController urlCtl,
    required TextEditingController imgCtl,
    required String submitLabel,
    required ManagedItem? Function() onSubmit,
  }) {
    return showDialog<ManagedItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtl,
              decoration: const InputDecoration(
                labelText: '链接 URL',
                hintText: 'https://... 或 /thread/xxx',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: imgCtl,
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
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final result = onSubmit();
              if (result != null) Navigator.of(ctx).pop(result);
            },
            child: Text(submitLabel),
          ),
        ],
      ),
    );
  }
}

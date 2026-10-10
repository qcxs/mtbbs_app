import 'package:flutter/material.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/key_recorder_dialog.dart';

/// 快捷键组设置项：直接列出全部快捷键（全局 + 编辑器工具栏），点击录制。
/// 工具栏项被隐藏时，其快捷键是否生效取决于「隐藏项快捷键可用」设置。
///
/// 工具栏部分遍历**实际** `settings.toolbarItems`（含用户自定义模板项），
/// 因此自定义模板也能绑定快捷键。
List<SettingsModel> shortcutSettings(SettingsProvider s) => [
  const HeaderSetting(title: '全局快捷键'),
  for (final action in ShortcutHelper.labels.keys) _globalShortcutItem(action),
  HeaderSetting(
    title: '编辑器工具栏快捷键',
    subtitle: s.toolbarShortcutWhenHidden
        ? '隐藏的工具栏项其快捷键仍然生效'
        : '隐藏的工具栏项其快捷键已失效',
  ),
  for (final item in s.toolbarItems) _toolbarShortcutItem(item),
  const HeaderSetting(title: '提示：修改后立即生效，无需重启'),
];

NormalSetting _globalShortcutItem(String action) {
  final label = ShortcutHelper.labels[action] ?? action;
  return NormalSetting(
    title: label,
    icon: Icons.keyboard,
    trailingBuilder: (ctx, s) => _keyBadge(ctx, s.shortcut(action)),
    onTap: (ctx, s) => _recordShortcut(
      ctx,
      initial: s.shortcut(action),
      onSave: (v) async {
        await s.setShortcut(action, v);
        if (ctx.mounted) {
          showToast('$label 已设置为 $v', duration: const Duration(seconds: 1));
        }
      },
    ),
  );
}

NormalSetting _toolbarShortcutItem(ManagedItem item) {
  return NormalSetting(
    title: item.name,
    icon: Icons.keyboard,
    subtitleBuilder: (s) {
      if (item.visible) return null;
      return s.toolbarShortcutWhenHidden ? '已隐藏（快捷键仍可用）' : '已隐藏（快捷键已失效）';
    },
    trailingBuilder: (ctx, s) => _keyBadge(ctx, s.toolbarShortcut(item.id)),
    onTap: (ctx, s) => _recordShortcut(
      ctx,
      initial: s.toolbarShortcut(item.id),
      onSave: (v) async {
        await s.setToolbarShortcut(item.id, v);
        if (ctx.mounted) {
          showToast(
            '${item.name} 已设置为 $v',
            duration: const Duration(seconds: 1),
          );
        }
      },
    ),
  );
}

Future<void> _recordShortcut(
  BuildContext context, {
  required String initial,
  required Future<void> Function(String) onSave,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => KeyRecorderDialog(initial: initial),
  );
  if (result != null && result.isNotEmpty) {
    await onSave(result);
  }
}

Widget _keyBadge(BuildContext context, String currentKey) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: cs.outlineVariant),
    ),
    child: Text(
      currentKey.isEmpty ? '未设置' : currentKey,
      style: TextStyle(
        fontSize: 12,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    ),
  );
}

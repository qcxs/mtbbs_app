import 'package:flutter/material.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/key_recorder_dialog.dart';

/// 快捷键组设置项：直接列出全部快捷键（全局 + 编辑器工具栏），点击录制。
/// 工具栏项隐藏时其快捷键自动失效（副标题提示"已隐藏"）。
List<SettingsModel> shortcutSettings() => [
  const HeaderSetting(title: '全局快捷键'),
  for (final action in ShortcutHelper.labels.keys) _globalShortcutItem(action),
  const HeaderSetting(title: '编辑器工具栏快捷键', subtitle: '隐藏的工具栏项其快捷键自动失效'),
  for (final config in allToolbarItemConfigs) _toolbarShortcutItem(config),
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

NormalSetting _toolbarShortcutItem(ToolbarItemConfig config) {
  return NormalSetting(
    title: config.name,
    icon: Icons.keyboard,
    subtitleBuilder: (s) {
      final visible = s.toolbarItems
          .where((e) => e.id == config.id)
          .firstOrNull
          ?.visible;
      return visible == false ? '已隐藏' : null;
    },
    trailingBuilder: (ctx, s) => _keyBadge(ctx, s.toolbarShortcut(config.id)),
    onTap: (ctx, s) => _recordShortcut(
      ctx,
      initial: s.toolbarShortcut(config.id),
      onSave: (v) async {
        await s.setToolbarShortcut(config.id, v);
        if (ctx.mounted) {
          showToast(
            '${config.name} 已设置为 $v',
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

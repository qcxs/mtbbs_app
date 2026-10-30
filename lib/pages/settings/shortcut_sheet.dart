import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/shortcut_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:provider/provider.dart';

/// 快捷键面板 — 全局快捷键 + 编辑器工具栏快捷键的唯一实现。
///
/// 设置页「编辑与快捷键」组与编辑器设置页都调用本函数，
/// 不再各维护一份列表。
Future<void> showShortcutSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => const _ShortcutSheet(),
  );
}

class _ShortcutSheet extends StatelessWidget {
  const _ShortcutSheet();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final models = shortcutSettings(settings);

    return AppSheetScaffold(
      title: '快捷键',
      child: ListView.builder(
        itemCount: models.length,
        itemBuilder: (_, i) => models[i].build(context, settings),
      ),
    );
  }
}

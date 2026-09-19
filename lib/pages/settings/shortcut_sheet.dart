import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/shortcut_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 快捷键面板 — 全局快捷键 + 编辑器工具栏快捷键的唯一实现。
///
/// 设置页「编辑与快捷键」组与编辑器设置页都调用本函数，
/// 不再各维护一份列表。
Future<void> showShortcutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _ShortcutSheet(),
  );
}

class _ShortcutSheet extends StatelessWidget {
  const _ShortcutSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final models = shortcutSettings();

    return Column(
      children: [
        // 拖拽手柄
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '快捷键',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView.builder(
            itemCount: models.length,
            itemBuilder: (_, i) => models[i].build(context, settings),
          ),
        ),
      ],
    );
  }
}

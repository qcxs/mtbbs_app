import 'package:flutter/material.dart';
import '../../config/nav_config.dart';
import '../../providers/settings_provider.dart';

/// 默认启动页设置对话框
///
/// 选择应用启动时默认选中的 Tab，数据源与导航栏共享 navItems。
class DefaultTabDialog {
  static void show(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) {
        int selected = settings.defaultTabIndex;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('默认启动页'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('选择应用启动时默认选中的页面：'),
                  const SizedBox(height: 16),
                  ...List.generate(navItems.length, (i) {
                    final item = navItems[i];
                    return RadioListTile<int>(
                      title: Row(
                        children: [
                          Icon(item.icon, size: 20),
                          const SizedBox(width: 8),
                          Text(item.label),
                        ],
                      ),
                      value: i,
                      groupValue: selected,
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selected = v);
                      },
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    await settings.setDefaultTabIndex(selected);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

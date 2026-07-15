import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/shortcut_helper.dart';
import '../../config/toolbar_config.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/key_recorder_dialog.dart';

/// 快捷键设置页
///
/// 两个区域：
///   1. 全局快捷键（导航/刷新等）
///   2. 编辑器工具栏快捷键（与工具栏项绑定，隐藏项自动失效）
class ShortcutSettingsPage extends StatelessWidget {
  const ShortcutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('快捷键设置')),
      body: ListView(
        children: [
          // ==================== 全局快捷键 ====================
          _sectionHeader(context, '全局快捷键'),
          for (final action in ShortcutHelper.labels.keys)
            _shortcutTile(
              context,
              label: ShortcutHelper.labels[action] ?? action,
              currentKey: settings.shortcut(action),
              onTap: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      KeyRecorderDialog(initial: settings.shortcut(action)),
                );
                if (result != null && result.isNotEmpty) {
                  await settings.setShortcut(action, result);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${ShortcutHelper.labels[action] ?? action} 已设置为 $result',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
            ),

          const Divider(height: 32),

          // ==================== 编辑器工具栏快捷键 ====================
          _sectionHeader(context, '编辑器工具栏快捷键',
              subtitle: '隐藏的工具栏项其快捷键自动失效'),
          for (final config in allToolbarItemConfigs)
            _shortcutTile(
              context,
              label: config.name,
              currentKey: settings.toolbarShortcut(config.id),
              visible: settings.toolbarItems
                  .where((e) => e.id == config.id)
                  .firstOrNull
                  ?.visible,
              onTap: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => KeyRecorderDialog(
                    initial: settings.toolbarShortcut(config.id),
                  ),
                );
                if (result != null && result.isNotEmpty) {
                  await settings.setToolbarShortcut(config.id, result);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${config.name} 已设置为 $result',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
            ),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '提示：修改后立即生效，无需重启',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
        ],
      ),
    );
  }

  Widget _shortcutTile(
    BuildContext context, {
    required String label,
    required String currentKey,
    bool? visible,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.keyboard, color: Colors.indigo.shade600, size: 22),
      ),
      title: Text(
        label,
        style: visible == false
            ? TextStyle(color: Colors.grey.shade400)
            : null,
      ),
      subtitle: visible == false
          ? Text('已隐藏', style: TextStyle(fontSize: 11, color: Colors.grey.shade400))
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          currentKey.isEmpty ? '未设置' : currentKey,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            color: currentKey.isEmpty ? Colors.grey.shade400 : Colors.grey.shade700,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

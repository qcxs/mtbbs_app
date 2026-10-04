import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/pages/settings/shortcut_sheet.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';
import 'package:mtbbs/widgets/dialog/toolbar_template_dialog.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 编辑器设置页 — 编辑器相关的所有设置
class EditorSettingsPage extends StatefulWidget {
  const EditorSettingsPage({super.key});

  @override
  State<EditorSettingsPage> createState() => _EditorSettingsPageState();
}

class _EditorSettingsPageState extends State<EditorSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final editorHistory = context.watch<EditorHistoryProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('编辑器设置'), surfaceTintColor: cs.surface),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('快照', [
            _sliderTile(
              icon: Icons.short_text,
              title: '最短字数',
              subtitle: '低于 ${settings.minSnapshotWordCount} 字的修改不保存快照，退出不拦截',
              value: settings.minSnapshotWordCount.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (v) => settings.setMinSnapshotWordCount(v.round()),
            ),
            _sliderTile(
              icon: Icons.timer_outlined,
              title: '自动保存间隔',
              subtitle: '每 ${settings.autoSaveInterval} 秒保存一次自动快照',
              value: settings.autoSaveInterval.toDouble(),
              min: 5,
              max: 300,
              divisions: 59,
              onChanged: (v) => settings.setAutoSaveInterval(v.round()),
            ),
            _sliderTile(
              icon: Icons.collections_bookmark,
              title: '自动快照数量',
              subtitle: '每会话最多 ${settings.maxAutoSnapshots} 条自动快照',
              value: settings.maxAutoSnapshots.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) => settings.setMaxAutoSnapshots(v.round()),
            ),
            ListTile(
              leading: _iconBox(Icons.delete_sweep, cs.error),
              title: const Text('清空编辑历史'),
              subtitle: Text(
                '删除所有保存的编辑历史记录',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              onTap: () => _confirmClearHistory(context, editorHistory),
            ),
          ]),
          const SizedBox(height: 8),
          _section('工具栏', [
            ListTile(
              leading: _iconBox(Icons.reorder, cs.onSurfaceVariant),
              title: const Text('工具栏排序'),
              subtitle: Text(
                '${settings.toolbarItems.length} 项（${settings.toolbarItems.where((e) => e.visible).length} 项显示）',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showToolbarDialog(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.keyboard, cs.onSurfaceVariant),
              title: const Text('快捷键设置'),
              subtitle: const Text('配置全局和工具栏快捷键'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showShortcutSheet(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return StatefulBuilder(
      builder: (ctx, setD) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: _iconBox(icon, cs.onSurfaceVariant),
            title: Text(title),
            subtitle: Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: value.round().toString(),
              onChanged: (v) {
                setD(() {});
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Future<void> _showToolbarDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    await showManagedListDialog(
      context: context,
      title: '工具栏排序',
      items: settings.toolbarItems,
      allowAdd: true,
      allowDelete: true,
      allowEdit: true,
      // 内置项不可删（会被下次同步还原）；仅模板项可编辑（复杂项由代码实现）
      canDelete: isCustomToolbarItem,
      canEdit: (item) => toolbarTemplateOf(item) != null,
      onAdd: () => _editToolbarTemplate(context, settings, null),
      onEdit: (item) => _editToolbarTemplate(context, settings, item),
      onDelete: (id) async {
        await settings.deleteToolbarItem(id);
        return true;
      },
      onReorder: (from, to) => settings.moveToolbarItem(from, to),
      onToggleVisibility: (id) => settings.toggleToolbarItem(id),
      emptyHint: '工具栏为空',
      titleActions: [
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 22),
          // 重置的是「顺序 + 显隐 + 模板 + 快捷键」四项（resetToolbarItems），
          // 文案不能只说排序——否则用户找不到"恢复默认快捷键"的入口
          tooltip: '重置工具栏与快捷键为默认（保留自定义模板）',
          onPressed: () async {
            await settings.resetToolbarItems();
            if (context.mounted) {
              showToast('已恢复默认工具栏与快捷键', duration: const Duration(seconds: 1));
            }
          },
        ),
      ],
    );
  }

  /// 新增 / 编辑模板项；完成后重开工具栏面板（保证始终只有一层浮层）
  Future<ManagedItem?> _editToolbarTemplate(
    BuildContext context,
    SettingsProvider settings,
    ManagedItem? initial,
  ) async {
    final result = await showToolbarTemplateDialog(context, initial: initial);
    if (result == null || !context.mounted) return null;

    if (initial == null) {
      await settings.addToolbarItem(result);
      if (context.mounted) {
        showToast('已新增「${result.name}」', duration: const Duration(seconds: 1));
      }
    } else {
      await settings.updateToolbarItem(initial.id, result);
    }

    if (context.mounted) await _showToolbarDialog(context, settings);
    return result;
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    EditorHistoryProvider editorHistory,
  ) async {
    final confirm = await showConfirmDialog(
      context,
      title: '清空编辑历史',
      message: '确定删除所有编辑历史记录吗？此操作不可撤销。',
      confirmText: '清空',
      danger: true,
      maxWidth: 360,
    );

    if (confirm == true && context.mounted) {
      // Clear all sessions
      final prov = context.read<EditorHistoryProvider>();
      for (final session in await prov.getAllSessions()) {
        await prov.deleteSession(session.key);
      }
      if (mounted) {
        showToast('已清空');
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/widgets/managed_list_dialog.dart';

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

  void _showToolbarDialog(BuildContext context, SettingsProvider settings) {
    showManagedListDialog(
      context: context,
      title: '工具栏排序',
      items: settings.toolbarItems,
      allowAdd: false,
      allowDelete: false,
      allowEdit: false,
      allowReorder: true,
      allowToggleVisibility: true,
      onReorder: (from, to) => settings.moveToolbarItem(from, to),
      onToggleVisibility: (id) => settings.toggleToolbarItem(id),
      emptyHint: '工具栏为空',
      titleActions: [
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 22),
          tooltip: '重置为默认排序',
          onPressed: () async {
            await settings.resetToolbarItems();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已重置为默认排序'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    EditorHistoryProvider editorHistory,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('清空编辑历史'),
        content: const Text('确定删除所有编辑历史记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      // Clear all sessions
      final prov = context.read<EditorHistoryProvider>();
      for (final session in await prov.getAllSessions()) {
        await prov.deleteSession(session.key);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已清空')));
      }
    }
  }
}

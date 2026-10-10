import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/pages/settings/shortcut_sheet.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';
import 'package:mtbbs/widgets/dialog/quick_reply_dialog.dart';
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
              title: const Text('完整编辑器工具栏'),
              subtitle: Text(
                '${settings.toolbarItems.length} 项（${settings.toolbarItems.where((e) => e.visible).length} 项显示）· 顺序与列表',
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
            for (final ctx in MiniToolbarContext.values)
              ListTile(
                leading: _iconBox(Icons.vertical_split, cs.onSurfaceVariant),
                title: Text('迷你工具栏 · ${ctx.label}'),
                subtitle: Text(
                  '${settings.miniToolbarItems(ctx).length} 项显示 · 与完整编辑器共用一套（顺序随其排序）',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showMiniToolbarDialog(context, settings, ctx),
              ),
            ListTile(
              leading: _iconBox(Icons.quickreply_outlined, cs.onSurfaceVariant),
              title: const Text('帖子常用语'),
              subtitle: Text('${settings.quickReplies.length} 条'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showQuickRepliesDialog(context, settings),
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
      title: '完整编辑器工具栏',
      items: settings.toolbarItems,
      allowAdd: true,
      allowDelete: true,
      allowEdit: true,
      allowFilterVisible: true,
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
          // 重置的是「顺序 + 显隐 + 模板 + 快捷键 + 迷你可见性」，
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

  /// 迷你工具栏（帖子页 / 私信页）：与完整编辑器**共用一套工具栏**。
  /// 面板展示**整条工具栏**（顺序即共享顺序，故这里也能排序），
  /// 只切换该上下文的可见性；该上下文不支持的项禁用显隐开关。
  Future<void> _showMiniToolbarDialog(
    BuildContext context,
    SettingsProvider settings,
    MiniToolbarContext ctx,
  ) async {
    await showManagedListDialog(
      context: context,
      title: '迷你工具栏 · ${ctx.label}',
      items: [
        for (final e in settings.toolbarItems)
          e.copyWith(visible: toolbarMiniVisible(e, ctx)),
      ],
      allowAdd: false,
      allowDelete: false,
      allowEdit: false,
      allowFilterVisible: true,
      // 该上下文不支持（如私信页的论坛图片/附件/常用语）的项：不显示显隐开关
      canToggleVisibility: (item) => miniToolbarSupportsItem(ctx, item.id),
      onReorder: (from, to) => settings.moveToolbarItem(from, to),
      onToggleVisibility: (id) => settings.toggleToolbarMiniVisible(ctx, id),
      emptyHint: '暂无可显示项',
      titleActions: [
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 22),
          tooltip: '恢复默认工具栏（含迷你可见性）',
          onPressed: () async {
            await settings.resetToolbarItems();
            if (context.mounted) {
              showToast('已恢复默认工具栏', duration: const Duration(seconds: 1));
            }
          },
        ),
      ],
    );
  }

  /// 帖子常用语管理：增 / 删 / 改 / 排序 / 显隐（复用统一列表管理面板）
  Future<void> _showQuickRepliesDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    await showManagedListDialog(
      context: context,
      title: '帖子常用语',
      items: settings.quickReplies,
      emptyHint: '暂无常用语',
      onAdd: () => _addQuickReply(context, settings),
      onEdit: (item) => _editQuickReply(context, settings, item),
      onDelete: (id) async {
        await settings.deleteQuickReply(id);
        return true;
      },
      onReorder: (from, to) => settings.moveQuickReply(from, to),
      onToggleVisibility: (id) => settings.toggleQuickReply(id),
      titleActions: [
        IconButton(
          icon: const Icon(Icons.restart_alt, size: 22),
          tooltip: '恢复默认常用语',
          onPressed: () async {
            await settings.resetQuickReplies();
            if (context.mounted) {
              showToast('已恢复默认常用语', duration: const Duration(seconds: 1));
            }
          },
        ),
      ],
    );
  }

  Future<ManagedItem?> _addQuickReply(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final result = await showQuickReplyDialog(context);
    if (result == null || !context.mounted) return null;
    await settings.addQuickReply(result);
    if (context.mounted) await _showQuickRepliesDialog(context, settings);
    return result;
  }

  Future<ManagedItem?> _editQuickReply(
    BuildContext context,
    SettingsProvider settings,
    ManagedItem item,
  ) async {
    final result = await showQuickReplyDialog(context, initial: item);
    if (result == null || !context.mounted) return null;
    await settings.updateQuickReply(item.id, result);
    if (context.mounted) await _showQuickRepliesDialog(context, settings);
    return result;
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

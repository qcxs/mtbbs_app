import 'package:flutter/material.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/forum/misc/export.dart' as forum_misc;
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/widgets/managed_list_dialog.dart';
import '../../../providers/settings_provider.dart';

/// 论坛管理 — 查看、添加、编辑、删除论坛
///
/// 使用统一 ManagedListDialog，额外提供"从 API 刷新"功能。
class ForumManagement {
  /// 弹出版块管理对话框
  static void showPicker(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    final items = settings.forumEntries
        .map((e) => ManagedItem(id: e.key, name: e.value, visible: true))
        .toList();

    showManagedListDialog(
      context: context,
      title: '板块管理',
      items: items,
      allowAdd: true,
      allowDelete: true,
      allowEdit: true,
      allowReorder: true,
      allowToggleVisibility: false,
      itemBuilder: (item, _) => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                item.id,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: const TextStyle(fontSize: 14)),
              Text(
                'fid=${item.id}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
      onReorder: (from, to) => settings.moveForum(from, to),
      titleActions: [
        IconButton(
          icon: Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
          tooltip: '从 API 刷新',
          onPressed: () async {
            // 先关弹窗（弹窗在根 Navigator 上）
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true).pop();
            }
            // 后台刷新
            final result = await forum_misc.fetchForumNav(ApiService().dio);
            if (result['success'] == true) {
              final refreshed =
                  (result['forums'] as Map<String, dynamic>?)?.map(
                    (k, v) => MapEntry(k, v.toString()),
                  ) ??
                  {};
              if (refreshed.isNotEmpty) {
                await settings.replaceForums(refreshed);
              }
            }
            // 弹窗已关，用设置页 context 显示 SnackBar
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    result['success'] == true
                        ? '板块已更新'
                        : '刷新失败: ${result['message']}',
                  ),
                ),
              );
            }
          },
        ),
      ],
      onAdd: () async {
        // 关闭主对话框，打开添加对话框
        final fidCtl = TextEditingController();
        final nameCtl = TextEditingController();
        final added = await showDialog<MapEntry<String, String>>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('添加板块'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fidCtl,
                  decoration: const InputDecoration(
                    labelText: '版块 ID (fid)',
                    hintText: '例如：2',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: '版块名称',
                    hintText: '例如：综合交流',
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
                  final fid = fidCtl.text.trim();
                  final name = nameCtl.text.trim();
                  if (fid.isEmpty || name.isEmpty) return;
                  Navigator.of(ctx).pop(MapEntry(fid, name));
                },
                child: const Text('添加'),
              ),
            ],
          ),
        );
        if (added != null) {
          await settings.addForum(added.key, added.value);
        }
        return null;
      },
      onEdit: (item) async {
        final fidCtl = TextEditingController(text: item.id);
        final nameCtl = TextEditingController(text: item.name);
        final edited = await showDialog<({String fid, String name})>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('编辑板块'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fidCtl,
                  decoration: const InputDecoration(
                    labelText: '版块 ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: '版块名称',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  autofocus: true,
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
                  final fid = fidCtl.text.trim();
                  final name = nameCtl.text.trim();
                  if (fid.isEmpty || name.isEmpty) return;
                  Navigator.of(ctx).pop((fid: fid, name: name));
                },
                child: const Text('保存'),
              ),
            ],
          ),
        );
        if (edited != null) {
          // 如果 fid 变了，先添加新 fid，再删旧 fid
          if (edited.fid != item.id) {
            await settings.addForum(edited.fid, edited.name);
            await settings.removeForum(item.id);
          } else {
            await settings.renameForum(item.id, edited.name);
          }
        }
        return null;
      },
      onDelete: (id) async {
        await settings.removeForum(id);
        return true;
      },
    );
  }
}

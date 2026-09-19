import 'package:flutter/material.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/api/forum/misc/export.dart' as forum_misc;
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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
            // 弹窗已关，用设置页 context 显示 Toast
            if (context.mounted) {
              showToast(
                result['success'] == true
                    ? '板块已更新'
                    : '刷新失败: ${result['message']}',
              );
            }
          },
        ),
      ],
      onAdd: () async {
        // 关闭主对话框，打开添加对话框
        final added = await showDialog<MapEntry<String, String>>(
          context: context,
          builder: (_) => const _AddForumDialog(),
        );
        if (added != null) {
          await settings.addForum(added.key, added.value);
        }
        return null;
      },
      onEdit: (item) async {
        final edited = await showDialog<({String fid, String name})>(
          context: context,
          builder: (_) =>
              _EditForumDialog(initialFid: item.id, initialName: item.name),
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

/// 添加板块弹窗内容
///
/// 控制器由本 State 持有、随弹窗子树卸载才释放：showDialog 返回的 Future 在 pop
/// 时即完成，而弹窗退场动画期间子树仍会重建（设置项保存触发 notifyListeners
/// 会重建 MaterialApp），在 pop 前后提前 dispose 会抛
/// 「A TextEditingController was used after being disposed」。
class _AddForumDialog extends StatefulWidget {
  const _AddForumDialog();

  @override
  State<_AddForumDialog> createState() => _AddForumDialogState();
}

class _AddForumDialogState extends State<_AddForumDialog> {
  final _fidCtl = TextEditingController();
  final _nameCtl = TextEditingController();

  @override
  void dispose() {
    _fidCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加板块'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _fidCtl,
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
            controller: _nameCtl,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final fid = _fidCtl.text.trim();
            final name = _nameCtl.text.trim();
            if (fid.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop(MapEntry(fid, name));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}

/// 编辑板块弹窗内容
///
/// 控制器由本 State 持有，理由同 [_AddForumDialog]。
class _EditForumDialog extends StatefulWidget {
  const _EditForumDialog({required this.initialFid, required this.initialName});

  final String initialFid;
  final String initialName;

  @override
  State<_EditForumDialog> createState() => _EditForumDialogState();
}

class _EditForumDialogState extends State<_EditForumDialog> {
  late final TextEditingController _fidCtl = TextEditingController(
    text: widget.initialFid,
  );
  late final TextEditingController _nameCtl = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _fidCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑板块'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _fidCtl,
            decoration: const InputDecoration(
              labelText: '版块 ID',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtl,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final fid = _fidCtl.text.trim();
            final name = _nameCtl.text.trim();
            if (fid.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop((fid: fid, name: name));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../models/managed_item.dart';

/// 统一有序列表管理弹窗
///
/// 一套 UI 覆盖 增/删/改/排序/隐藏 五种操作，每个操作独立开关。
/// 适用于版块管理、快捷链接、工具栏排序、Tab 排序等所有场景。
///
/// 安全性：
///   打开时对 items 做快照，提交时用 ID 匹配，防止索引越界。
///
/// 关闭原则：
///   执行增/删/改操作前应关闭本对话框（调用 Navigator.of(context).pop()），
///   操作完成后由调用方重新打开。这样确保始终只有一层对话框，
///   且重新打开时自动读取最新数据，无需手动刷新 UI。
///
/// 用法：
/// ```dart
/// final changed = await showManagedListDialog(
///   context: context,
///   title: '快捷链接管理',
///   items: settings.shortcutLinks,
///   allowAdd: true,
///   allowDelete: true,
///   onReorder: (from, to) => settings.moveShortcutLink(from, to),
///   onToggleVisibility: (id) => settings.toggleShortcutLink(id),
/// );
/// ```
Future<void> showManagedListDialog({
  required BuildContext context,
  required String title,
  required List<ManagedItem> items,
  bool allowAdd = true,
  bool allowDelete = true,
  bool allowEdit = true,
  bool allowReorder = true,
  bool allowToggleVisibility = true,
  Future<ManagedItem?> Function()? onAdd,
  Future<ManagedItem?> Function(ManagedItem item)? onEdit,
  Future<bool> Function(String id)? onDelete,
  void Function(int from, int to)? onReorder,
  void Function(String id)? onToggleVisibility,
  String emptyHint = '暂无数据',
  Widget Function(ManagedItem item, bool isVisible)? itemBuilder,

  /// 标题栏右侧额外操作按钮（如图标刷新），放在添加按钮之后
  List<Widget>? titleActions,
}) async {
  // 快照：用列表副本 + ID 集合，后续操作基于 ID
  final itemsSnapshot = List<ManagedItem>.from(items);
  final initialIds = itemsSnapshot.map((e) => e.id).toSet();

  await showDialog(
    context: context,
    builder: (ctx) => _ManagedListDialogContent(
      title: title,
      items: itemsSnapshot,
      initialIds: initialIds,
      allowAdd: allowAdd,
      allowDelete: allowDelete,
      allowEdit: allowEdit,
      allowReorder: allowReorder,
      allowToggleVisibility: allowToggleVisibility,
      onAdd: onAdd,
      onEdit: onEdit,
      onDelete: onDelete,
      onReorder: onReorder,
      onToggleVisibility: onToggleVisibility,
      emptyHint: emptyHint,
      itemBuilder: itemBuilder,
      titleActions: titleActions,
    ),
  );
}

class _ManagedListDialogContent extends StatefulWidget {
  final String title;
  final List<ManagedItem> items;
  final Set<String> initialIds;
  final bool allowAdd,
      allowDelete,
      allowEdit,
      allowReorder,
      allowToggleVisibility;
  final Future<ManagedItem?> Function()? onAdd;
  final Future<ManagedItem?> Function(ManagedItem item)? onEdit;
  final Future<bool> Function(String id)? onDelete;
  final void Function(int from, int to)? onReorder;
  final void Function(String id)? onToggleVisibility;
  final String emptyHint;
  final Widget Function(ManagedItem item, bool isVisible)? itemBuilder;
  final List<Widget>? titleActions;

  const _ManagedListDialogContent({
    required this.title,
    required this.items,
    required this.initialIds,
    required this.allowAdd,
    required this.allowDelete,
    required this.allowEdit,
    required this.allowReorder,
    required this.allowToggleVisibility,
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.onReorder,
    this.onToggleVisibility,
    required this.emptyHint,
    this.itemBuilder,
    this.titleActions,
  });

  @override
  State<_ManagedListDialogContent> createState() =>
      _ManagedListDialogContentState();
}

class _ManagedListDialogContentState extends State<_ManagedListDialogContent> {
  late List<_ItemHolder> _items;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((e) => _ItemHolder(e)).toList();
  }

  bool _isValidId(String id) => widget.initialIds.contains(id);

  Future<void> _handleAdd() async {
    if (widget.onAdd == null) return;
    if (!mounted) return;
    Navigator.of(context).pop(); // 先关主对话框，确保同时只有一层
    final newItem = await widget.onAdd!();
    if (newItem != null && widget.allowAdd) {
      // 如果 onAdd 返回了条目，调用方需要自行管理
    }
  }

  Future<void> _handleEdit(int index) async {
    if (widget.onEdit == null) return;
    final item = _items[index];
    if (!_isValidId(item.id)) return;
    if (!mounted) return;
    Navigator.of(context).pop(); // 先关主对话框
    final updated = await widget.onEdit!(item.item);
    if (updated != null && widget.allowEdit) {
      // 如果 onEdit 返回了条目，调用方需要自行管理
    }
  }

  Future<void> _handleDelete(int index) async {
    if (widget.onDelete == null) return;
    final item = _items[index];
    if (!_isValidId(item.id)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${item.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final ok = await widget.onDelete!(item.id);
      if (ok && mounted) {
        setState(() => _items.removeAt(index));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleToggleVisibility(int index) {
    if (widget.onToggleVisibility == null) return;
    final item = _items[index];
    if (!_isValidId(item.id)) return;
    widget.onToggleVisibility!(item.id);
    setState(
      () => _items[index] = _ItemHolder(
        item.item.copyWith(visible: !item.item.visible),
      ),
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (!widget.allowReorder || widget.onReorder == null) return;
    final idx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final moved = _items.removeAt(oldIndex);
    _items.insert(idx, moved);
    widget.onReorder!(oldIndex, idx);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          if (widget.titleActions != null) ...widget.titleActions!,
          if (widget.allowAdd)
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22),
              tooltip: '新增',
              onPressed: _loading ? null : _handleAdd,
            ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: _items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    widget.emptyHint,
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                ),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                onReorderItem: _handleReorder,
                buildDefaultDragHandles: false,
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final isVisible = item.item.visible;
                  return ListTile(
                    key: ValueKey(item.id),
                    leading: widget.allowReorder
                        ? ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.drag_handle, size: 18),
                            ),
                          )
                        : null,
                    title: widget.itemBuilder != null
                        ? widget.itemBuilder!(item.item, isVisible)
                        : Text(
                            item.name,
                            style: TextStyle(
                              color: isVisible ? null : Colors.grey,
                            ),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.allowToggleVisibility)
                          IconButton(
                            icon: Icon(
                              isVisible
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: 18,
                              color: isVisible ? Colors.blue : Colors.grey,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: isVisible ? '隐藏' : '显示',
                            onPressed: _loading
                                ? null
                                : () => _handleToggleVisibility(i),
                          ),
                        if (widget.allowEdit)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: '编辑',
                            onPressed: _loading ? null : () => _handleEdit(i),
                          ),
                        if (widget.allowDelete)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: '删除',
                            color: Colors.red.shade300,
                            onPressed: _loading ? null : () => _handleDelete(i),
                          ),
                      ],
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ItemHolder {
  final String id;
  final String name;
  final ManagedItem item;
  _ItemHolder(this.item) : id = item.id, name = item.name;
}

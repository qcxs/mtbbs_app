import 'package:flutter/material.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

/// 统一有序列表管理面板（底部抽屉）
///
/// 一套 UI 覆盖 增/删/改/排序/隐藏 五种操作，每个操作独立开关。
/// 适用于版块管理、快捷链接、工具栏排序、Tab 排序等所有场景。
///
/// 用底部抽屉而非弹窗：弹窗正文被写死 360px，宽屏下两侧全是空的；
/// 抽屉可以铺开到 [maxWidth]（手机即全宽），列表行有更多横向空间。
///
/// 安全性：
///   打开时对 items 做快照，提交时用 ID 匹配，防止索引越界。
///
/// 关闭原则：
///   执行增/删/改操作前应关闭本面板（调用 Navigator.of(context).pop()），
///   操作完成后由调用方重新打开。这样确保始终只有一层浮层，
///   且重新打开时自动读取最新数据，无需手动刷新 UI。
///
/// 用法：
/// ```dart
/// await showManagedListDialog(
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
}) {
  // 快照：用列表副本 + ID 集合，后续操作基于 ID
  final itemsSnapshot = List<ManagedItem>.from(items);
  final initialIds = itemsSnapshot.map((e) => e.id).toSet();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // maxHeight 必须给：面板内容是 Column + Expanded，无上界会直接崩
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => _ManagedListSheetContent(
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

class _ManagedListSheetContent extends StatefulWidget {
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

  const _ManagedListSheetContent({
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
  State<_ManagedListSheetContent> createState() =>
      _ManagedListSheetContentState();
}

class _ManagedListSheetContentState extends State<_ManagedListSheetContent> {
  late List<ManagedItem> _items;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
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
    final updated = await widget.onEdit!(item);
    if (updated != null && widget.allowEdit) {
      // 如果 onEdit 返回了条目，调用方需要自行管理
    }
  }

  Future<void> _handleDelete(int index) async {
    if (widget.onDelete == null) return;
    final item = _items[index];
    if (!_isValidId(item.id)) return;

    final confirm = await showConfirmDialog(
      context,
      title: '确认删除',
      message: '确定要删除「${item.name}」吗？',
      confirmText: '删除',
      danger: true,
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
    toggleManagedItem(_items, item.id);
    setState(() {});
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (!widget.allowReorder || widget.onReorder == null) return;
    reorderManagedItems(_items, oldIndex, newIndex);
    widget.onReorder!(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.titleActions != null) ...widget.titleActions!,
              if (widget.allowAdd)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  tooltip: '新增',
                  onPressed: _loading ? null : _handleAdd,
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
          child: _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      widget.emptyHint,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : ReorderableListView.builder(
                  itemCount: _items.length,
                  onReorderItem: _handleReorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final isVisible = item.visible;
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
                          ? widget.itemBuilder!(item, isVisible)
                          : Text(
                              item.name,
                              style: TextStyle(
                                color: isVisible ? null : cs.onSurfaceVariant,
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
                                color: isVisible
                                    ? cs.onSurfaceVariant
                                    : cs.onSurfaceVariant,
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
                              color: cs.error,
                              onPressed: _loading
                                  ? null
                                  : () => _handleDelete(i),
                            ),
                        ],
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

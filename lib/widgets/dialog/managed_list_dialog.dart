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

  /// 是否提供「只看已显示项」勾选项（标题栏）。用于隐藏项很多时减少干扰
  /// （尤其迷你工具栏只启用一小部分）。排序仍可用：内部会把可见子序列的
  /// 重排换算成对完整列表的移动（见 `reorderVisibleToFull`）。
  bool allowFilterVisible = false,
  Future<ManagedItem?> Function()? onAdd,
  Future<ManagedItem?> Function(ManagedItem item)? onEdit,
  Future<bool> Function(String id)? onDelete,
  void Function(int from, int to)? onReorder,
  void Function(String id)? onToggleVisibility,

  /// 逐项判断是否可删除（默认全部可删）。用于「内置项不可删、自定义项可删」。
  bool Function(ManagedItem item)? canDelete,

  /// 逐项判断是否可编辑（默认全部可编辑）。
  bool Function(ManagedItem item)? canEdit,

  /// 逐项判断是否可切换显隐（默认全部可切换）。用于禁用"该上下文不支持"的项。
  bool Function(ManagedItem item)? canToggleVisibility,
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
      allowFilterVisible: allowFilterVisible,
      onAdd: onAdd,
      onEdit: onEdit,
      onDelete: onDelete,
      onReorder: onReorder,
      onToggleVisibility: onToggleVisibility,
      canDelete: canDelete,
      canEdit: canEdit,
      canToggleVisibility: canToggleVisibility,
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
      allowToggleVisibility,
      allowFilterVisible;
  final Future<ManagedItem?> Function()? onAdd;
  final Future<ManagedItem?> Function(ManagedItem item)? onEdit;
  final Future<bool> Function(String id)? onDelete;
  final void Function(int from, int to)? onReorder;
  final void Function(String id)? onToggleVisibility;
  final bool Function(ManagedItem item)? canDelete;
  final bool Function(ManagedItem item)? canEdit;
  final bool Function(ManagedItem item)? canToggleVisibility;
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
    this.allowFilterVisible = false,
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.onReorder,
    this.onToggleVisibility,
    this.canDelete,
    this.canEdit,
    this.canToggleVisibility,
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

  /// 只看已显示项（勾选后隐藏未启用项，减少干扰；此时禁用排序）
  bool _onlyVisible = false;

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

  Future<void> _handleEdit(ManagedItem item) async {
    if (widget.onEdit == null) return;
    if (!_isValidId(item.id)) return;
    if (!mounted) return;
    Navigator.of(context).pop(); // 先关主对话框
    final updated = await widget.onEdit!(item);
    if (updated != null && widget.allowEdit) {
      // 如果 onEdit 返回了条目，调用方需要自行管理
    }
  }

  Future<void> _handleDelete(ManagedItem item) async {
    if (widget.onDelete == null) return;
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
        setState(() => _items.removeWhere((e) => e.id == item.id));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleToggleVisibility(ManagedItem item) {
    if (widget.onToggleVisibility == null) return;
    if (!_isValidId(item.id)) return;
    widget.onToggleVisibility!(item.id);
    toggleManagedItem(_items, item.id);
    setState(() {});
  }

  /// 重排。
  ///
  /// 不过滤时就是对完整列表的一次移动；过滤（只看已显示）时用
  /// [reorderVisibleToFull] 把可见子序列的重排换算成对完整列表的一次移动，
  /// 保证可见项相对顺序与用户操作一致（隐藏项可能位移但不可见）。
  void _handleReorder(int oldIndex, int newIndex) {
    if (!widget.allowReorder || widget.onReorder == null) return;
    if (!_onlyVisible) {
      reorderManagedItems(_items, oldIndex, newIndex);
      widget.onReorder!(oldIndex, newIndex);
      setState(() {});
      return;
    }
    final r = reorderVisibleToFull(_items, oldIndex, newIndex);
    if (r == null) return;
    reorderManagedItems(_items, r.from, r.to);
    widget.onReorder!(r.from, r.to);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 只看已显示项时按可见性过滤（排序仍可用：见 [_handleReorder] 的下标换算）
    final displayed = _onlyVisible
        ? _items.where((e) => e.visible).toList()
        : _items;

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
              if (widget.allowFilterVisible)
                IconButton(
                  icon: Icon(
                    _onlyVisible ? Icons.filter_alt : Icons.filter_alt_off,
                    size: 20,
                  ),
                  tooltip: _onlyVisible ? '显示全部' : '只看已显示项',
                  color: _onlyVisible ? cs.primary : null,
                  onPressed: () => setState(() => _onlyVisible = !_onlyVisible),
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
          child: displayed.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _onlyVisible ? '没有已显示的项' : widget.emptyHint,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                )
              : _loading
              ? const Center(child: CircularProgressIndicator())
              : ReorderableListView.builder(
                  itemCount: displayed.length,
                  onReorderItem: _handleReorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (ctx, i) {
                    final item = displayed[i];
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
                          if (widget.allowToggleVisibility &&
                              (widget.canToggleVisibility?.call(item) ?? true))
                            IconButton(
                              icon: Icon(
                                isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: isVisible ? '隐藏' : '显示',
                              onPressed: _loading
                                  ? null
                                  : () => _handleToggleVisibility(item),
                            ),
                          if (widget.allowEdit &&
                              (widget.canEdit?.call(item) ?? true))
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              tooltip: '编辑',
                              onPressed: _loading
                                  ? null
                                  : () => _handleEdit(item),
                            ),
                          if (widget.allowDelete &&
                              (widget.canDelete?.call(item) ?? true))
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
                                  : () => _handleDelete(item),
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

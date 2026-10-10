import 'dart:convert';

/// 统一可管理条目
///
/// 适用于版块、快捷链接、工具栏、Tab 等所有需要"有序列表 + 可见性"的场景。
/// [data] 存放业务自定义字段（如快捷链接的 url/imageUrl）。
class ManagedItem {
  final String id;
  final String name;
  final bool visible;
  final Map<String, dynamic>? data;

  const ManagedItem({
    required this.id,
    required this.name,
    this.visible = true,
    this.data,
  });

  ManagedItem copyWith({
    String? id,
    String? name,
    bool? visible,
    Map<String, dynamic>? data,
  }) => ManagedItem(
    id: id ?? this.id,
    name: name ?? this.name,
    visible: visible ?? this.visible,
    data: data ?? this.data,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'visible': visible,
    if (data != null) 'data': data,
  };

  factory ManagedItem.fromJson(Map<String, dynamic> json) => ManagedItem(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    visible: json['visible'] == true,
    data: json['data'] as Map<String, dynamic>?,
  );

  static String encodeList(List<ManagedItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<ManagedItem> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => ManagedItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

/// 按 ReorderableListView.onReorderItem 语义移动条目。
///
/// onReorderItem 回调的 [to] 已是「移除后」的最终插入位（框架在
/// newIndex > oldIndex 时已内部减 1），此处只做越界保护，不再二次修正。
/// 弹窗与 Provider 共用此函数，避免索引计算分叉。
void reorderManagedItems(List<ManagedItem> items, int from, int to) {
  if (from < 0 || from >= items.length) return;
  final item = items.removeAt(from);
  items.insert(to.clamp(0, items.length), item);
}

/// 切换条目可见性；id 不存在时安全返回。
void toggleManagedItem(List<ManagedItem> items, String id) {
  final i = items.indexWhere((e) => e.id == id);
  if (i < 0) return;
  items[i] = items[i].copyWith(visible: !items[i].visible);
}

/// 把「只显示可见项」视图里的一次重排，换算成对完整 [items] 的一次移动。
///
/// 该视图里只有可见项，[oldVisibleIndex]/[newVisibleIndex] 是**可见子序列**的下标；
/// 返回值是对完整列表（[reorderManagedItems] 语义）的 `(from, to)`。
///
/// 语义：只保证**可见项的相对顺序**与用户操作一致；隐藏项可能随之位移
/// （它们不可见，用户无感）。无可见项或下标越界返回 null。
({int from, int to})? reorderVisibleToFull(
  List<ManagedItem> items,
  int oldVisibleIndex,
  int newVisibleIndex,
) {
  final visible = items.where((e) => e.visible).toList();
  if (oldVisibleIndex < 0 || oldVisibleIndex >= visible.length) return null;
  final moved = visible[oldVisibleIndex];
  final from = items.indexOf(moved);
  if (from < 0) return null;

  // 完整列表移除被拖项后，其可见子序列决定插入点
  final without = List<ManagedItem>.from(items)..removeAt(from);
  final visibleWithout = without.where((e) => e.visible).toList();
  final int to;
  if (newVisibleIndex >= visibleWithout.length) {
    // 落到可见子序列末尾：插到最后一个可见项之后（无可见项则放末尾）
    to = visibleWithout.isEmpty
        ? without.length
        : without.indexOf(visibleWithout.last) + 1;
  } else {
    to = without.indexOf(visibleWithout[newVisibleIndex]);
  }
  if (to < 0) return null;
  return (from: from, to: to);
}

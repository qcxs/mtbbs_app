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
  }) =>
      ManagedItem(
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

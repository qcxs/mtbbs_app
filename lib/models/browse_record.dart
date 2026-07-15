import 'dart:convert';

/// 浏览记录
///
/// [info] 存储类型相关的原始数据，供后续渲染卡片、插入格式等场景使用。
///
/// 帖子 (type=thread) 的 info 字段：
/// ```json
/// {
///   "tid": "123",
///   "title": "帖子标题",
///   "author": "楼主昵称",
///   "authorUid": "456",
///   "time": "2024-01-01 12:00",
///   "url": "https://bbs.binmt.cc/forum.php?mod=viewthread&tid=123"
/// }
/// ```
///
/// 用户 (type=user) 的 info 字段：
/// ```json
/// {
///   "uid": "456",
///   "nickname": "用户名",
///   "avatar": "https://...",
///   "url": "https://bbs.binmt.cc/home.php?mod=space&uid=456"
/// }
/// ```
class BrowseRecord {
  /// 唯一标识 "thread_123" / "user_456"
  final String id;

  /// 记录类型 "thread" | "user"
  final String type;

  /// 列表展示用标题（帖子标题/用户昵称）
  final String title;

  /// App 路由路径 "/thread/123" / "/user/456"
  final String routePath;

  /// 浏览时间
  final DateTime timestamp;

  /// 类型相关的原始数据
  final Map<String, dynamic> info;

  const BrowseRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.routePath,
    required this.timestamp,
    this.info = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'routePath': routePath,
        'timestamp': timestamp.toIso8601String(),
        'info': info,
      };

  factory BrowseRecord.fromJson(Map<String, dynamic> json) => BrowseRecord(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        routePath: json['routePath']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        info: _toMap(json['info']),
      );

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return {};
  }

  static String encodeList(List<BrowseRecord> records) =>
      jsonEncode(records.map((e) => e.toJson()).toList());

  static List<BrowseRecord> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => BrowseRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

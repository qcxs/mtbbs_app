import 'dart:convert';

/// 浏览记录
///
/// [info] 存储类型相关的原始数据，标题通过 [displayTitle] 动态渲染。
///
/// 帖子 (type=thread) 的 info 字段：
/// ```json
/// {
///   "tid": "123",
///   "title": "帖子标题",
///   "author": "楼主昵称",
///   "authorUid": "456",
///   "time": "2024-01-01 12:00",
///   "page": 1,
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

  /// 记录类型 "thread" | "user" | "mythread" | "reply"
  final String type;

  /// App 路由路径 "/thread/123" / "/user/456"
  final String routePath;

  /// 浏览时间
  final DateTime timestamp;

  /// 类型相关的原始数据
  final Map<String, dynamic> info;

  const BrowseRecord({
    required this.id,
    required this.type,
    required this.routePath,
    required this.timestamp,
    this.info = const {},
  });

  /// 根据模板渲染标题
  ///
  /// 可用占位符：
  /// - `{typeLabel}` — 自动注入的中文类型名（帖子/用户/我的帖子/回复）
  /// - `info` 中的字段键名
  /// 找不到的占位符保留原样。
  String displayTitle(String template) {
    final allInfo = <String, String>{
      'typeLabel': switch (type) {
        'thread' => '帖子',
        'user' => '用户',
        'mythread' => '我的帖子',
        'reply' => '回复',
        _ => type,
      },
      for (final e in info.entries) e.key: e.value?.toString() ?? '',
    };
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final key = m.group(1)!;
      return allInfo[key] ?? m.group(0)!;
    });
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'routePath': routePath,
        'timestamp': timestamp.toIso8601String(),
        'info': info,
      };

  factory BrowseRecord.fromJson(Map<String, dynamic> json) => BrowseRecord(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
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

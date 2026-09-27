/// 一个 MCP 访问令牌 —— 由用户手动创建，可备注、可刷新、可删除。
///
/// 明文保存在本机 sembast 中（与 Cookie 同级的敏感数据），
/// 只在设置页展示/复制，**绝不进入任何 MCP 出站响应**。
class McpToken {
  const McpToken({
    required this.id,
    required this.value,
    required this.note,
    required this.createdAt,
  });

  /// 稳定标识（刷新令牌值时保持不变）
  final String id;

  /// 令牌明文，AI 客户端作为 Bearer 令牌使用
  final String value;

  /// 用户备注，用于区分使用它的客户端
  final String note;

  final DateTime createdAt;

  /// 未填写备注时的占位名
  static const String fallbackNote = '未命名令牌';

  /// 掩码展示（保留前后各 4 位便于辨认）
  String get masked {
    if (value.length <= 10) return value;
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  McpToken copyWith({String? value, String? note}) => McpToken(
    id: id,
    value: value ?? this.value,
    note: note ?? this.note,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'value': value,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory McpToken.fromJson(Map<String, dynamic> json) => McpToken(
    id: json['id']?.toString() ?? '',
    value: json['value']?.toString() ?? '',
    note: json['note']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
  );
}

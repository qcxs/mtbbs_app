import 'package:flutter/foundation.dart';

/// 一次 MCP 工具调用记录（仅存内存，重启即清空）。
class McpAuditEntry {
  const McpAuditEntry({
    required this.time,
    required this.tool,
    required this.ok,
    required this.elapsedMs,
    this.error,
  });

  final DateTime time;
  final String tool;
  final bool ok;
  final int elapsedMs;
  final String? error;
}

/// MCP 调用审计 —— 让用户能确认"AI 到底读了什么"。
class McpAuditLog extends ChangeNotifier {
  McpAuditLog._();
  static final McpAuditLog instance = McpAuditLog._();

  static const int maxEntries = 100;

  final List<McpAuditEntry> _entries = [];

  /// 最新在前
  List<McpAuditEntry> get entries => List.unmodifiable(_entries);

  void add(McpAuditEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

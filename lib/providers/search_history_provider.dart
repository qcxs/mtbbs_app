import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/database_helper.dart';

/// 搜索历史记录
class SearchHistoryItem {
  final String text;
  final DateTime time;

  const SearchHistoryItem({required this.text, required this.time});

  Map<String, dynamic> toJson() => {
    'text': text,
    'time': time.toIso8601String(),
  };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(
        text: json['text']?.toString() ?? '',
        time:
            DateTime.tryParse(json['time']?.toString() ?? '') ?? DateTime.now(),
      );
}

/// 搜索历史管理
///
/// 使用 SQLite 持久化（search_history 表），增量写入。
class SearchHistoryProvider extends ChangeNotifier {
  List<SearchHistoryItem> _items = [];
  static const int _maxCount = 100;

  /// 获取所有搜索历史（按时间倒序）
  List<SearchHistoryItem> getAll() => List.unmodifiable(_items);

  /// 添加搜索记录
  Future<void> add(String text) async {
    if (text.trim().isEmpty) return;
    final trimmed = text.trim();

    // 去重：移除相同的旧记录
    _items.removeWhere((i) => i.text == trimmed);
    // 插到头部
    _items.insert(0, SearchHistoryItem(text: trimmed, time: DateTime.now()));
    // 超限淘汰
    while (_items.length > _maxCount) {
      _items.removeLast();
    }

    // 增量写入：先删旧记录再插入新记录
    await DatabaseHelper.instance.deleteSearchHistoryByText(trimmed);
    await DatabaseHelper.instance.insertSearchHistory(
      trimmed,
      DateTime.now().toIso8601String(),
    );
    // 超限时从 DB 删除最旧的
    await DatabaseHelper.instance.trimSearchHistory(_maxCount);

    notifyListeners();
  }

  /// 删除单条
  Future<void> remove(String text) async {
    _items.removeWhere((i) => i.text == text);
    await DatabaseHelper.instance.deleteSearchHistoryByText(text);
    notifyListeners();
  }

  /// 清空所有
  Future<void> clear() async {
    _items.clear();
    await DatabaseHelper.instance.clearSearchHistory();
    notifyListeners();
  }

  /// 从 SQLite 恢复
  Future<void> load() async {
    final rows = await DatabaseHelper.instance.getAllSearchHistory();
    _items = rows.map((row) {
      return SearchHistoryItem(
        text: row.value['text'] as String? ?? '',
        time:
            DateTime.tryParse(row.value['time'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
    notifyListeners();
  }
}

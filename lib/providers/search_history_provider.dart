import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// 独立于浏览历史，单独持久化到 'search_history' key。
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
    await _persist();
    notifyListeners();
  }

  /// 删除单条
  Future<void> remove(String text) async {
    _items.removeWhere((i) => i.text == text);
    await _persist();
    notifyListeners();
  }

  /// 清空所有
  Future<void> clear() async {
    _items.clear();
    await _persist();
    notifyListeners();
  }

  /// 从 SharedPreferences 恢复
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('search_history');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = (jsonDecode(jsonStr) as List<dynamic>)
            .map((e) => SearchHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _items = list;
      } catch (_) {
        _items = [];
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString('search_history', jsonStr);
  }
}

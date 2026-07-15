import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/browse_record.dart';

/// 浏览记录管理
///
/// 使用 SharedPreferences 持久化，key 为 'browse_history'。
/// 自动去重（同 id 更新时间戳移到头部），超限淘汰最旧记录。
class HistoryProvider extends ChangeNotifier {
  List<BrowseRecord> _records = [];

  /// 最大记录数，从 SettingsProvider 同步
  int _maxCount = 200;

  /// 未过滤的记录总数
  int get totalCount => _records.length;

  /// 获取所有记录（按时间倒序）
  List<BrowseRecord> getAll() => List.unmodifiable(_records);

  /// 按类型过滤记录
  List<BrowseRecord> getByType(String type) =>
      _records.where((r) => r.type == type).toList();

  /// 设置最大记录数（不立刻截断，下次 add 时生效）
  void setMaxCount(int count) {
    _maxCount = count.clamp(10, 1000);
  }

  /// 添加或更新记录
  ///
  /// - 同 id 存在 → 删除旧记录，新记录插到头部（更新时间戳）
  /// - 不存在 → 插到头部
  /// - 超限 → 淘汰尾部最旧的
  Future<void> addRecord(BrowseRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    _records.insert(0, record);

    // 超限淘汰
    while (_records.length > _maxCount) {
      _records.removeLast();
    }

    await _persist();
    notifyListeners();
  }

  /// 删除单条记录
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _persist();
    notifyListeners();
  }

  /// 按类型清空
  Future<void> clearByType(String type) async {
    _records.removeWhere((r) => r.type == type);
    await _persist();
    notifyListeners();
  }

  /// 清空所有记录
  Future<void> clear() async {
    _records.clear();
    await _persist();
    notifyListeners();
  }

  /// 从 SharedPreferences 恢复
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('browse_history');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        _records = BrowseRecord.decodeList(jsonStr);
      } catch (_) {
        _records = [];
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('browse_history', BrowseRecord.encodeList(_records));
  }
}

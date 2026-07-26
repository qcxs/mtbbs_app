import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/models/browse_record.dart';

/// 浏览记录管理
///
/// 使用 SQLite 持久化（browse_records 表）。
/// 内存缓存 + 增量写入：每次操作只更新受影响的记录，避免全量重写。
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

    while (_records.length > _maxCount) {
      final removed = _records.removeLast();
      await DatabaseHelper.instance.deleteBrowseRecord(removed.id);
    }

    await DatabaseHelper.instance.upsertBrowseRecord(record);
    notifyListeners();
  }

  /// 删除单条记录
  Future<void> remove(String id) async {
    _records.removeWhere((r) => r.id == id);
    await DatabaseHelper.instance.deleteBrowseRecord(id);
    notifyListeners();
  }

  /// 按类型清空
  Future<void> clearByType(String type) async {
    _records.removeWhere((r) => r.type == type);
    await DatabaseHelper.instance.deleteBrowseRecordsByType(type);
    notifyListeners();
  }

  /// 清空所有记录
  Future<void> clear() async {
    _records.clear();
    await DatabaseHelper.instance.clearBrowseRecords();
    notifyListeners();
  }

  /// 从 SQLite 恢复
  Future<void> load() async {
    _records = await DatabaseHelper.instance.getAllBrowseRecords();
    notifyListeners();
  }
}

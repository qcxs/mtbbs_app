import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/app/event_bus.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/models/browse_record.dart';

/// 浏览记录管理
///
/// 使用 sembast 持久化（browse_records 表），内存缓存 + 增量写入。
///
/// 多站点隔离：对外暴露的列表只包含当前站点的记录（见 [BrowseRecord.belongsTo]），
/// 清空也只清当前站点，避免在 A 站操作把 B 站的记录一起清掉。
/// 站点切换后通过 [SiteChangedEvent] 触发重建，列表随新站点刷新。
class HistoryProvider extends ChangeNotifier {
  HistoryProvider() {
    _siteSub = EventBus.stream
        .where((e) => e is SiteChangedEvent)
        .listen((_) => notifyListeners());
  }

  StreamSubscription<AppEvent>? _siteSub;

  /// 全量记录（跨站点），始终按时间倒序
  List<BrowseRecord> _records = [];

  /// 最大记录数，从 SettingsProvider 同步
  int _maxCount = 200;

  /// 当前站点可见的记录
  List<BrowseRecord> get _visible {
    final host = SiteStore.instance.host;
    return _records.where((r) => r.belongsTo(host)).toList();
  }

  /// 当前站点的记录总数
  int get totalCount => _visible.length;

  /// 获取当前站点所有记录（按时间倒序）
  List<BrowseRecord> getAll() => List.unmodifiable(_visible);

  /// 按类型过滤当前站点的记录
  List<BrowseRecord> getByType(String type) =>
      _visible.where((r) => r.type == type).toList();

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

  /// 按类型清空**当前站点**的记录
  Future<void> clearByType(String type) async {
    await _removeWhere((r) => r.type == type);
  }

  /// 清空**当前站点**的全部记录
  Future<void> clear() async {
    await _removeWhere((_) => true);
  }

  /// 删除满足条件的当前站点记录（内存 + 持久化）
  Future<void> _removeWhere(bool Function(BrowseRecord) test) async {
    final host = SiteStore.instance.host;
    final targets = _records
        .where((r) => r.belongsTo(host) && test(r))
        .map((r) => r.id)
        .toList();
    if (targets.isEmpty) return;

    _records.removeWhere((r) => targets.contains(r.id));
    for (final id in targets) {
      await DatabaseHelper.instance.deleteBrowseRecord(id);
    }
    notifyListeners();
  }

  /// 从 sembast 恢复
  Future<void> load() async {
    _records = await DatabaseHelper.instance.getAllBrowseRecords();
    notifyListeners();
  }

  @override
  void dispose() {
    _siteSub?.cancel();
    super.dispose();
  }
}

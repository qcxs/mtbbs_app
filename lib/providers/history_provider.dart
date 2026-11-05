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
/// 多站点：数据全量保留，**浏览记录页默认展示全部站点**，并可按站点筛选
/// （见 [query] / [count] / [recordHosts]）。
/// 其余入口（编辑器历史选择器、`totalCount` / `getAll` / `getByType`）仍只看**当前站点**，
/// 清空也只清当前站点，避免在 A 站操作把 B 站的记录一起清掉（历史页的清空走 [clearFiltered]，
/// 由页面显式传入站点范围）。
/// 站点切换后通过 [SiteChangedEvent] 触发重建，当前站点的计数随新站点刷新。
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

  /// 按类型 / 站点筛选记录。
  ///
  /// [type] 为空表示全部类型；[host] 为空表示**全部站点**（历史页默认），
  /// 传站点 host 则只保留该站点（归属未知的老记录按 [BrowseRecord.belongsTo] 处理）。
  /// 结果始终按时间倒序。
  List<BrowseRecord> query({String type = '', String? host}) {
    return _records.where((r) {
      if (host != null && !r.belongsTo(host)) return false;
      return type.isEmpty || r.type == type;
    }).toList();
  }

  /// 按类型 / 站点统计条数（口径同 [query]）
  int count({String type = '', String? host}) {
    var n = 0;
    for (final r in _records) {
      if (host != null && !r.belongsTo(host)) continue;
      if (type.isNotEmpty && r.type != type) continue;
      n++;
    }
    return n;
  }

  /// 有记录的站点（按最近一条记录的时间倒序，去重）
  ///
  /// 归属未知（host 为空）的老记录不参与筛选，它们在「全部站点」下照常显示。
  List<String> get recordHosts {
    final seen = <String>{};
    final hosts = <String>[];
    for (final r in _records) {
      final h = r.effectiveHost;
      if (h.isEmpty || !seen.add(h)) continue;
      hosts.add(h);
    }
    return hosts;
  }

  /// 站点显示名（未配置的 host 原样返回）
  String siteLabel(String host) {
    for (final site in SiteStore.instance.sites) {
      if (site.host == host) return site.name;
    }
    return host;
  }

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

  /// 按页面选定的范围清空：`host == null` 表示全部站点，[type] 为空表示全部类型。
  ///
  /// 历史页专用；不做隐式兜底，范围由调用方显式给出并在确认弹窗里说明。
  Future<void> clearFiltered({String? host, String type = ''}) async {
    final targets = _records
        .where(
          (r) =>
              (host == null || r.belongsTo(host)) &&
              (type.isEmpty || r.type == type),
        )
        .map((r) => r.id)
        .toList();
    if (targets.isEmpty) return;

    _records.removeWhere((r) => targets.contains(r.id));
    for (final id in targets) {
      await DatabaseHelper.instance.deleteBrowseRecord(id);
    }
    notifyListeners();
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

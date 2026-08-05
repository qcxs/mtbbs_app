import 'package:sembast/sembast_io.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/models/browse_record.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 数据库帮助类 — 基于 sembast（纯 Dart NoSQL）的统一持久化层
///
/// 全应用唯一持久化方案，替代 SharedPreferences。
/// 所有数据存储在单一 .db 文件中，按 Store 隔离。
///
/// sembast 100% Dart 实现，无需任何原生依赖，全平台开箱即用。
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await AppPaths.databasePath;
    final db = await databaseFactoryIo.openDatabase(dbPath);
    AppLogger.i('DB', 'opened: $dbPath');
    return db;
  }

  // =================== Store 定义 ===================

  /// 浏览记录 — String key（record.id），Map value
  static final _browseStore = stringMapStoreFactory.store('browse_records');

  /// 搜索历史 — int auto-increment key，Map value
  static final _searchStore = intMapStoreFactory.store('search_history');

  /// 编辑器快照 — String key（snapshot.id），Map value
  static final _snapshotStore = stringMapStoreFactory.store('editor_snapshots');

  /// 帖子预览缓存 — String key（tid_pid），Map value
  static final _previewStore = stringMapStoreFactory.store('preview_cache');

  /// 设置项 — String key → {value: String}，替代 SharedPreferences
  static final _settingsStore = stringMapStoreFactory.store('app_settings');

  /// 账号列表 — String key (host) → JSON: List<Account>
  static final _accountsStore = stringMapStoreFactory.store('app_accounts');

  /// 图床历史 — 固定 key "history" → JSON: List<MtUploadResult>
  static final _imageHistoryStore = stringMapStoreFactory.store(
    'image_history',
  );

  /// 站点列表 — 固定 key "sites" → JSON: List<Site>
  static final _sitesStore = stringMapStoreFactory.store('app_sites');

  /// 快捷链接 — String key (host) → JSON: List<ManagedItem>
  static final _shortcutLinksStore = stringMapStoreFactory.store(
    'shortcut_links',
  );

  /// 工具栏项目 — 固定 key "items" → JSON: List<ManagedItem>
  static final _toolbarItemsStore = stringMapStoreFactory.store(
    'toolbar_items',
  );

  /// 快捷键映射 — 固定 key "shortcuts" → JSON: Map<String, String>
  static final _shortcutsStore = stringMapStoreFactory.store('app_shortcuts');

  /// 工具栏快捷键 — 固定 key "tb_shortcuts" → JSON: Map<String, String>
  static final _toolbarShortcutsStore = stringMapStoreFactory.store(
    'toolbar_shortcuts',
  );

  /// 禁用的 BBCode 标签 — 固定 key "disabled" → JSON: List<String>
  static final _disabledBbcodeStore = stringMapStoreFactory.store(
    'disabled_bbcode',
  );

  /// 积分公式 — String key (host) → {value: String}
  static final _creditFormulaStore = stringMapStoreFactory.store(
    'credit_formula',
  );

  /// 上次登录账号 — String key (host) → {value: String}
  static final _lastAccountStore = stringMapStoreFactory.store('last_account');

  /// 头像重定向映射 — 每条映射一条记录：key=原始URL → {final: 最终URL|null, updatedAt: ms}
  static final _avatarRedirectStore = stringMapStoreFactory.store(
    'avatar_redirects',
  );

  // =================== 头像重定向映射 ===================

  /// 读取全部映射记录（供启动加载、旧数据迁移、过期清理）
  Future<Map<String, Map<String, Object?>>> getAllAvatarRedirects() async {
    final db = await database;
    final records = await _avatarRedirectStore.find(
      db,
      finder: Finder(sortOrders: []),
    );
    final result = <String, Map<String, Object?>>{};
    for (final rec in records) {
      result[rec.key] = Map<String, Object?>.from(rec.value);
    }
    return result;
  }

  /// 增量写入/更新一条映射（[finalUrl] 为 null 表示无重定向）
  Future<void> putAvatarRedirect(
    String url,
    String? finalUrl,
    DateTime updatedAt,
  ) async {
    final db = await database;
    await _avatarRedirectStore.record(url).put(db, {
      'final': finalUrl,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    });
  }

  /// 批量删除映射记录
  Future<void> deleteAvatarRedirects(List<String> urls) async {
    if (urls.isEmpty) return;
    final db = await database;
    for (final url in urls) {
      await _avatarRedirectStore.record(url).delete(db);
    }
  }

  /// 清空全部映射记录（缓存管理中清除头像缓存时调用）
  Future<void> clearAvatarRedirects() async {
    final db = await database;
    await _avatarRedirectStore.delete(db);
  }

  // =================== 通用设置（替代 SharedPreferences） ===================

  /// 读取字符串设置项
  Future<String?> getSetting(String key) async {
    final db = await database;
    final record = await _settingsStore.record(key).get(db);
    return record?['value'] as String?;
  }

  /// 写入字符串设置项
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await _settingsStore.record(key).put(db, {'value': value});
  }

  /// 读取 int 设置项
  Future<int?> getSettingInt(String key) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v);
  }

  /// 写入 int 设置项
  Future<void> setSettingInt(String key, int value) async {
    await setSetting(key, value.toString());
  }

  /// 读取 double 设置项
  Future<double?> getSettingDouble(String key) async {
    final v = await getSetting(key);
    if (v == null || v.isEmpty) return null;
    return double.tryParse(v);
  }

  /// 写入 double 设置项
  Future<void> setSettingDouble(String key, double value) async {
    await setSetting(key, value.toString());
  }

  /// 读取 bool 设置项
  Future<bool?> getSettingBool(String key) async {
    final v = await getSetting(key);
    if (v == null) return null;
    if (v == 'true') return true;
    if (v == 'false') return false;
    return null;
  }

  /// 写入 bool 设置项
  Future<void> setSettingBool(String key, bool value) async {
    await setSetting(key, value.toString());
  }

  /// 删除设置项
  Future<void> deleteSetting(String key) async {
    final db = await database;
    await _settingsStore.record(key).delete(db);
  }

  // =================== 站点列表 ===================

  Future<String?> getSitesRaw() async {
    final db = await database;
    final record = await _sitesStore.record('sites').get(db);
    return record?['value'] as String?;
  }

  Future<void> setSitesRaw(String json) async {
    final db = await database;
    await _sitesStore.record('sites').put(db, {'value': json});
  }

  // =================== 账号列表（按站点隔离） ===================

  Future<String?> getAccountsRaw(String host) async {
    final db = await database;
    final record = await _accountsStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setAccountsRaw(String host, String json) async {
    final db = await database;
    await _accountsStore.record(host).put(db, {'value': json});
  }

  Future<void> deleteAccounts(String host) async {
    final db = await database;
    await _accountsStore.record(host).delete(db);
  }

  // =================== 上次登录账号 ===================

  Future<String?> getLastAccount(String host) async {
    final db = await database;
    final record = await _lastAccountStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setLastAccount(String host, String username) async {
    final db = await database;
    await _lastAccountStore.record(host).put(db, {'value': username});
  }

  Future<void> deleteLastAccount(String host) async {
    final db = await database;
    await _lastAccountStore.record(host).delete(db);
  }

  // =================== 积分公式（按站点） ===================

  Future<String?> getCreditFormula(String host) async {
    final db = await database;
    final record = await _creditFormulaStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setCreditFormula(String host, String formula) async {
    final db = await database;
    await _creditFormulaStore.record(host).put(db, {'value': formula});
  }

  // =================== 图床历史 ===================

  Future<String?> getImageHistoryRaw() async {
    final db = await database;
    final record = await _imageHistoryStore.record('history').get(db);
    return record?['value'] as String?;
  }

  Future<void> setImageHistoryRaw(String json) async {
    final db = await database;
    await _imageHistoryStore.record('history').put(db, {'value': json});
  }

  // =================== 快捷链接（按站点） ===================

  Future<String?> getShortcutLinksRaw(String host) async {
    final db = await database;
    final record = await _shortcutLinksStore.record(host).get(db);
    return record?['value'] as String?;
  }

  Future<void> setShortcutLinksRaw(String host, String json) async {
    final db = await database;
    await _shortcutLinksStore.record(host).put(db, {'value': json});
  }

  // =================== 工具栏配置 ===================

  Future<String?> getToolbarItemsRaw() async {
    final db = await database;
    final record = await _toolbarItemsStore.record('items').get(db);
    return record?['value'] as String?;
  }

  Future<void> setToolbarItemsRaw(String json) async {
    final db = await database;
    await _toolbarItemsStore.record('items').put(db, {'value': json});
  }

  // =================== 快捷键映射 ===================

  Future<String?> getShortcutsRaw() async {
    final db = await database;
    final record = await _shortcutsStore.record('shortcuts').get(db);
    return record?['value'] as String?;
  }

  Future<void> setShortcutsRaw(String json) async {
    final db = await database;
    await _shortcutsStore.record('shortcuts').put(db, {'value': json});
  }

  // =================== 工具栏快捷键 ===================

  Future<String?> getToolbarShortcutsRaw() async {
    final db = await database;
    final record = await _toolbarShortcutsStore.record('tb_shortcuts').get(db);
    return record?['value'] as String?;
  }

  Future<void> setToolbarShortcutsRaw(String json) async {
    final db = await database;
    await _toolbarShortcutsStore.record('tb_shortcuts').put(db, {
      'value': json,
    });
  }

  // =================== 禁用的 BBCode 标签 ===================

  Future<String?> getDisabledBbcodeRaw() async {
    final db = await database;
    final record = await _disabledBbcodeStore.record('disabled').get(db);
    return record?['value'] as String?;
  }

  Future<void> setDisabledBbcodeRaw(String json) async {
    final db = await database;
    await _disabledBbcodeStore.record('disabled').put(db, {'value': json});
  }

  // =================== 浏览记录 ===================

  Future<List<BrowseRecord>> getAllBrowseRecords() async {
    final db = await database;
    final records = await _browseStore.find(
      db,
      finder: Finder(sortOrders: [SortOrder('timestamp', false)]),
    );
    return records.map((r) => BrowseRecord.fromJson(r.value)).toList();
  }

  Future<List<BrowseRecord>> getBrowseRecordsByType(String type) async {
    final db = await database;
    final records = await _browseStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('type', type),
        sortOrders: [SortOrder('timestamp', false)],
      ),
    );
    return records.map((r) => BrowseRecord.fromJson(r.value)).toList();
  }

  Future<void> upsertBrowseRecord(BrowseRecord record) async {
    final db = await database;
    await _browseStore.record(record.id).put(db, record.toJson());
  }

  Future<void> deleteBrowseRecord(String id) async {
    final db = await database;
    await _browseStore.record(id).delete(db);
  }

  Future<void> deleteBrowseRecordsByType(String type) async {
    final db = await database;
    await _browseStore.delete(
      db,
      finder: Finder(filter: Filter.equals('type', type)),
    );
  }

  Future<void> clearBrowseRecords() async {
    final db = await database;
    await _browseStore.delete(db);
  }

  Future<int> countBrowseRecords() async {
    final db = await database;
    return _browseStore.count(db);
  }

  Future<void> trimBrowseRecords(int maxCount) async {
    final db = await database;
    final count = await _browseStore.count(db);
    if (count <= maxCount) return;
    final toDelete = count - maxCount;
    final records = await _browseStore.find(
      db,
      finder: Finder(
        sortOrders: [SortOrder('timestamp', true)],
        limit: toDelete,
      ),
    );
    for (final r in records) {
      await _browseStore.record(r.key).delete(db);
    }
  }

  // =================== 搜索历史 ===================

  Future<List<RecordSnapshot<int, Map<String, dynamic>>>>
  getAllSearchHistory() async {
    final db = await database;
    return _searchStore.find(
      db,
      finder: Finder(sortOrders: [SortOrder('id', false)]),
    );
  }

  Future<void> insertSearchHistory(String text, String time) async {
    final db = await database;
    await _searchStore.add(db, {'text': text, 'time': time});
  }

  Future<void> deleteSearchHistoryByText(String text) async {
    final db = await database;
    await _searchStore.delete(
      db,
      finder: Finder(filter: Filter.equals('text', text)),
    );
  }

  Future<void> clearSearchHistory() async {
    final db = await database;
    await _searchStore.delete(db);
  }

  Future<int> countSearchHistory() async {
    final db = await database;
    return _searchStore.count(db);
  }

  Future<void> trimSearchHistory(int maxCount) async {
    final db = await database;
    final count = await _searchStore.count(db);
    if (count <= maxCount) return;
    final toDelete = count - maxCount;
    final records = await _searchStore.find(
      db,
      finder: Finder(sortOrders: [SortOrder(Field.key, true)], limit: toDelete),
    );
    for (final r in records) {
      await _searchStore.record(r.key).delete(db);
    }
  }

  // =================== 编辑器快照 ===================

  Future<List<EditorSnapshot>> getSnapshotsBySession(
    String sessionKey, {
    bool? isManual,
  }) async {
    final db = await database;
    final filters = <Filter>[Filter.equals('sessionKey', sessionKey)];
    if (isManual != null) {
      filters.add(Filter.equals('isManual', isManual));
    }
    final records = await _snapshotStore.find(
      db,
      finder: Finder(
        filter: Filter.and(filters),
        sortOrders: [SortOrder('createdAt', false)],
      ),
    );
    return records.map((r) => EditorSnapshot.fromJson(r.value)).toList();
  }

  Future<List<EditorSnapshot>> getAllSnapshotsBySession(
    String sessionKey,
  ) async {
    return getSnapshotsBySession(sessionKey);
  }

  Future<EditorSnapshot?> getSnapshotById(String id) async {
    final db = await database;
    final record = await _snapshotStore.record(id).get(db);
    if (record == null) return null;
    return EditorSnapshot.fromJson(record);
  }

  Future<int> countAutoSnapshots(String sessionKey) async {
    final db = await database;
    return _snapshotStore.count(
      db,
      filter: Filter.and([
        Filter.equals('sessionKey', sessionKey),
        Filter.equals('isManual', false),
      ]),
    );
  }

  Future<bool> hasSessionSnapshots(String sessionKey) async {
    final db = await database;
    final records = await _snapshotStore.find(
      db,
      finder: Finder(filter: Filter.equals('sessionKey', sessionKey), limit: 1),
    );
    return records.isNotEmpty;
  }

  Future<void> insertEditorSnapshot(EditorSnapshot snapshot) async {
    final db = await database;
    await _snapshotStore.record(snapshot.id).put(db, snapshot.toJson());
  }

  Future<void> deleteEditorSnapshot(String id) async {
    final db = await database;
    await _snapshotStore.record(id).delete(db);
  }

  Future<void> deleteSnapshotsBySession(String sessionKey) async {
    final db = await database;
    await _snapshotStore.delete(
      db,
      finder: Finder(filter: Filter.equals('sessionKey', sessionKey)),
    );
  }

  Future<void> trimAutoSnapshots(String sessionKey, int maxCount) async {
    final db = await database;
    final count = await countAutoSnapshots(sessionKey);
    if (count <= maxCount) return;
    final toDelete = count - maxCount;
    final records = await _snapshotStore.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('sessionKey', sessionKey),
          Filter.equals('isManual', false),
        ]),
        sortOrders: [SortOrder('createdAt', true)],
        limit: toDelete,
      ),
    );
    for (final r in records) {
      await _snapshotStore.record(r.key).delete(db);
    }
  }

  Future<void> deleteSnapshotsBefore(DateTime cutoff) async {
    final db = await database;
    await _snapshotStore.delete(
      db,
      finder: Finder(
        filter: Filter.lessThan('createdAt', cutoff.millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> clearAllEditorSnapshots() async {
    final db = await database;
    await _snapshotStore.delete(db);
  }

  Future<List<String>> getAllSessionKeys() async {
    final db = await database;
    final records = await _snapshotStore.find(db);
    final keys = records.map((r) => r.value['sessionKey'] as String).toSet();
    return keys.toList();
  }

  // =================== 元数据存储（通用键值对） ===================

  /// 通用字符串元数据（供临时或非结构化数据使用）
  Future<String?> getMeta(String key) async {
    final db = await database;
    final record = await _settingsStore.record(key).get(db);
    return record?['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await _settingsStore.record(key).put(db, {'value': value});
  }

  Future<void> deleteMeta(String key) async {
    final db = await database;
    await _settingsStore.record(key).delete(db);
  }

  // =================== 帖子预览缓存 ===================

  Future<List<Map<String, dynamic>>> getAllPreviewCache() async {
    final db = await database;
    final records = await _previewStore.find(db);
    records.sort((a, b) => a.key.compareTo(b.key));
    return records.map((r) => r.value).toList();
  }

  Future<void> upsertPreviewCache(String tid, String pid, String bbcode) async {
    final db = await database;
    final key = '${tid}_$pid';
    await _previewStore.record(key).put(db, {
      'tid': tid,
      'pid': pid,
      'bbcode': bbcode,
    });
  }

  /// 按 key 删除单条预览缓存（FIFO 淘汰时与内存同步）
  Future<void> deletePreviewCache(String key) async {
    final db = await database;
    await _previewStore.record(key).delete(db);
  }

  Future<void> clearPreviewCache() async {
    final db = await database;
    await _previewStore.delete(db);
  }
}

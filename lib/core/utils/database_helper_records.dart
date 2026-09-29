part of 'database_helper.dart';

/// 结构化记录类读写：头像重定向、浏览记录、搜索历史、编辑器快照、预览缓存。
///
/// 公开命名扩展：随宿主 library 被 import/export 后进入调用方作用域，
/// 外部可像实例方法一样调用（extension 成员不是类成员，必须依赖此可见性）。
extension DatabaseHelperRecords on DatabaseHelper {
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

  // =================== 帖子预览缓存 ===================

  Future<List<Map<String, dynamic>>> getAllPreviewCache() async {
    final db = await database;
    final records = await _previewStore.find(db);
    records.sort((a, b) => a.key.compareTo(b.key));
    return records.map((r) => r.value).toList();
  }

  /// 写入/更新单条帖子预览缓存。
  ///
  /// key 含站点 host：MT 与 52 的 tid/pid 各自独立编号，不含 host 会互相覆盖。
  Future<void> upsertPreviewCache(
    String host,
    String tid,
    String pid,
    String bbcode,
  ) async {
    final db = await database;
    final key = '${host}_${tid}_$pid';
    await _previewStore.record(key).put(db, {
      'host': host,
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

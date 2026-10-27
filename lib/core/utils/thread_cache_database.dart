import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';

/// 帖子缓存数据库健康状态
enum ThreadCacheHealth {
  /// 尚未打开
  unknown,

  /// 可正常读写
  ready,

  /// 文件级损坏：整体禁用，等待用户手动重建/清空
  corrupted,
}

/// 帖子缓存统计
class ThreadCacheStats {
  /// 自动缓存帖数（按 host + viewer + tid 去重）
  final int autoThreads;

  /// 自动缓存版本数
  final int autoVersions;

  /// 自动缓存估算字节数
  final int autoBytes;

  /// 离线副本数
  final int offlineThreads;

  /// 离线副本估算字节数
  final int offlineBytes;

  const ThreadCacheStats({
    this.autoThreads = 0,
    this.autoVersions = 0,
    this.autoBytes = 0,
    this.offlineThreads = 0,
    this.offlineBytes = 0,
  });

  int get totalThreads => autoThreads + offlineThreads;
  int get totalBytes => autoBytes + offlineBytes;
}

/// 帖子缓存独立数据库（`threads.sembast`）
///
/// 与主库 [DatabaseHelper] 刻意分离：缓存体积大，独立文件损坏时不影响主库。
///
/// - `meta`：schema 版本
/// - `thread_meta`：轻量索引（列表/统计/过期清理）
/// - `thread_data`：完整快照 JSON
///
/// 所有公开方法自行吞掉异常：失败只记日志并返回空/失败，不向 UI 抛异常。
/// 文件级异常会把 [health] 置为 [ThreadCacheHealth.corrupted]；单条记录解析失败
/// 只跳过该条。
class ThreadCacheDatabase {
  ThreadCacheDatabase._();
  static final ThreadCacheDatabase instance = ThreadCacheDatabase._();

  static final _schemaStore = stringMapStoreFactory.store('meta');
  static final _indexStore = stringMapStoreFactory.store('thread_meta');

  /// 正文存 JSON 字符串：便于单条损坏隔离与精确估算大小
  static final _dataStore = StoreRef<String, String>('thread_data');

  /// 超过该大小的快照在后台 isolate 编码，避免阻塞 UI
  static const int _computeEncodeThreshold = 200 * 1024;

  /// 全局健康状态（App 壳层监听以弹一次 Toast）
  final ValueNotifier<ThreadCacheHealth> health = ValueNotifier(
    ThreadCacheHealth.unknown,
  );

  Database? _db;
  Future<void>? _opening;

  bool get isReady => _db != null;
  bool get isCorrupted => health.value == ThreadCacheHealth.corrupted;

  /// 数据库文件路径
  Future<String> get path => AppPaths.threadDatabasePath;

  // ==================== 打开 / 关闭 ====================

  /// 确保数据库可用；失败（含已损坏）返回 false
  Future<bool> ensureReady() async {
    if (isCorrupted) return false;
    if (_db != null) return true;
    final pending = _opening;
    if (pending != null) {
      await pending;
      return _db != null;
    }
    final future = _open();
    _opening = future;
    try {
      await future;
    } finally {
      _opening = null;
    }
    return _db != null;
  }

  Future<void> _open() async {
    try {
      final dbPath = await AppPaths.threadDatabasePath;
      final dir = Directory(p.dirname(dbPath));
      if (!await dir.exists()) await dir.create(recursive: true);
      final db = await databaseFactoryIo.openDatabase(dbPath);
      _db = db;
      final schema = await _schemaStore.record('schema').get(db);
      if (schema == null) {
        await _schemaStore.record('schema').put(db, {
          'version': kThreadSnapshotSchemaVersion,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
      health.value = ThreadCacheHealth.ready;
      AppLogger.i('THREAD_CACHE', 'db opened: $dbPath');
    } catch (e) {
      _db = null;
      _markCorrupted('open', e);
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    try {
      await db?.close();
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'close error: $e');
    }
  }

  // ==================== 读取索引 ====================

  /// 读取轻量索引；[kind] 为空时返回全部
  Future<List<ThreadSnapshotMeta>> listMeta({ThreadCacheKind? kind}) async {
    final db = await _ready();
    if (db == null) return const [];
    try {
      final records = await _indexStore.find(db);
      final result = <ThreadSnapshotMeta>[];
      for (final record in records) {
        final meta = ThreadSnapshotMeta.tryFromMap(record.value);
        if (meta == null) {
          AppLogger.w('THREAD_CACHE', 'skip bad meta: ${record.key}');
          continue;
        }
        if (kind != null && meta.kind != kind) continue;
        result.add(meta);
      }
      return result;
    } catch (e) {
      _markCorrupted('listMeta', e);
      return const [];
    }
  }

  /// 读取单条索引；不存在或损坏返回 null
  Future<ThreadSnapshotMeta?> readMeta(String key) async {
    final db = await _ready();
    if (db == null) return null;
    try {
      final raw = await _indexStore.record(key).get(db);
      return ThreadSnapshotMeta.tryFromMap(raw);
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'read meta failed $key: $e');
      return null;
    }
  }

  /// 读取完整快照；单条损坏返回 null
  Future<ThreadSnapshot?> readSnapshot(String key) async {
    final db = await _ready();
    if (db == null) return null;
    try {
      final raw = await _dataStore.record(key).get(db);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ThreadSnapshot.fromMap(Map<String, dynamic>.from(decoded));
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'skip bad snapshot $key: $e');
      return null;
    }
  }

  // ==================== 写入 ====================

  /// 写入快照（索引 + 正文同一事务）
  Future<bool> putSnapshot(ThreadSnapshot snapshot) async {
    final db = await _ready();
    if (db == null) return false;
    try {
      final map = snapshot.toMap();
      final payload = snapshot.approxBytes > _computeEncodeThreshold
          ? await compute(_encodeSnapshot, map)
          : jsonEncode(map);
      await db.transaction((txn) async {
        await _dataStore.record(snapshot.storageKey).put(txn, payload);
        await _indexStore.record(snapshot.storageKey).put(
          txn,
          snapshot.toMeta().toMap(),
        );
      });
      return true;
    } catch (e) {
      _markCorrupted('putSnapshot', e);
      return false;
    }
  }

  /// 只更新索引（TTL 刷新，避免重写大段正文）
  Future<bool> refreshAutoExpiry({
    required String host,
    required String viewer,
    required String tid,
    required DateTime expiresAt,
  }) async {
    final db = await _ready();
    if (db == null) return false;
    try {
      final records = await _indexStore.find(db);
      final targets = <String, Map<String, dynamic>>{};
      for (final record in records) {
        final meta = ThreadSnapshotMeta.tryFromMap(record.value);
        if (meta == null || !meta.isAuto) continue;
        if (meta.host != host || meta.tid != tid) continue;
        if ((meta.viewer ?? 'guest') != viewer) continue;
        targets[meta.key] = Map<String, dynamic>.from(record.value as Map);
      }
      if (targets.isEmpty) return true;
      await db.transaction((txn) async {
        for (final entry in targets.entries) {
          entry.value['expiresAt'] = expiresAt.toIso8601String();
          await _indexStore.record(entry.key).put(txn, entry.value);
        }
      });
      return true;
    } catch (e) {
      _markCorrupted('refreshAutoExpiry', e);
      return false;
    }
  }

  // ==================== 删除 / 清理 ====================

  Future<bool> deleteKeys(Iterable<String> keys) async {
    final list = keys.toList();
    if (list.isEmpty) return true;
    final db = await _ready();
    if (db == null) return false;
    try {
      await db.transaction((txn) async {
        for (final key in list) {
          await _indexStore.record(key).delete(txn);
          await _dataStore.record(key).delete(txn);
        }
      });
      return true;
    } catch (e) {
      _markCorrupted('deleteKeys', e);
      return false;
    }
  }

  /// 删除已过期的自动缓存，返回删除条数
  Future<int> deleteExpired(DateTime now) async {
    final metas = await listMeta(kind: ThreadCacheKind.auto);
    final expired = [
      for (final m in metas)
        if (m.isExpiredAt(now)) m.key,
    ];
    if (expired.isEmpty) return 0;
    return await deleteKeys(expired) ? expired.length : 0;
  }

  /// 清空指定类型；[viewer] 仅对自动缓存生效
  Future<bool> clearKind(ThreadCacheKind kind, {String? viewer}) async {
    final metas = await listMeta(kind: kind);
    final keys = [
      for (final m in metas)
        if (viewer == null || (m.viewer ?? 'guest') == viewer) m.key,
    ];
    return deleteKeys(keys);
  }

  /// 清空全部缓存
  Future<bool> clearAllRecords() async {
    final db = await _ready();
    if (db == null) return false;
    try {
      await db.transaction((txn) async {
        await _indexStore.delete(txn);
        await _dataStore.delete(txn);
      });
      return true;
    } catch (e) {
      _markCorrupted('clearAllRecords', e);
      return false;
    }
  }

  // ==================== 统计 / 文件 ====================

  Future<ThreadCacheStats> stats() async {
    final metas = await listMeta();
    var autoThreads = 0;
    var autoVersions = 0;
    var autoBytes = 0;
    var offlineThreads = 0;
    var offlineBytes = 0;
    final autoGroups = <String>{};
    for (final m in metas) {
      if (m.isAuto) {
        autoVersions++;
        autoBytes += m.approxBytes;
        autoGroups.add(m.threadGroupKey);
      } else {
        offlineThreads++;
        offlineBytes += m.approxBytes;
      }
    }
    autoThreads = autoGroups.length;
    return ThreadCacheStats(
      autoThreads: autoThreads,
      autoVersions: autoVersions,
      autoBytes: autoBytes,
      offlineThreads: offlineThreads,
      offlineBytes: offlineBytes,
    );
  }

  /// 数据库文件实际大小（不存在时为 0）
  Future<int> fileSizeBytes() async {
    try {
      final file = File(await AppPaths.threadDatabasePath);
      return await file.exists() ? await file.length() : 0;
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'fileSize error: $e');
      return 0;
    }
  }

  // ==================== 损坏恢复 ====================

  /// 重建缓存库：原文件改名为 `.corrupt-{时间}` 保留备份，再创建空库。
  ///
  /// [deleteIfRenameFails] 为 true 时，重命名失败会直接删除原文件（调用方需先确认）。
  Future<bool> rebuild({bool deleteIfRenameFails = false}) async {
    final dbPath = await AppPaths.threadDatabasePath;
    await close();
    try {
      final file = File(dbPath);
      if (await file.exists()) {
        final backup = '$dbPath.corrupt-${_timestamp()}';
        try {
          await file.rename(backup);
          AppLogger.i('THREAD_CACHE', 'corrupt backup: $backup');
        } catch (e) {
          if (!deleteIfRenameFails) {
            AppLogger.e('THREAD_CACHE', 'rename corrupt file failed: $e');
            return false;
          }
          await file.delete();
        }
      }
      await _deleteSiblings(dbPath);
      health.value = ThreadCacheHealth.unknown;
      return await ensureReady();
    } catch (e) {
      _markCorrupted('rebuild', e);
      return false;
    }
  }

  /// 清空缓存库：直接删除文件后重建（离线副本会丢失）
  Future<bool> clearAndRebuild() async {
    final dbPath = await AppPaths.threadDatabasePath;
    await close();
    try {
      final file = File(dbPath);
      if (await file.exists()) await file.delete();
      await _deleteSiblings(dbPath);
      health.value = ThreadCacheHealth.unknown;
      return await ensureReady();
    } catch (e) {
      _markCorrupted('clearAndRebuild', e);
      return false;
    }
  }

  // ==================== 内部 ====================

  Future<Database?> _ready() async => await ensureReady() ? _db : null;

  void _markCorrupted(String action, Object error) {
    _db = null;
    if (health.value != ThreadCacheHealth.corrupted) {
      health.value = ThreadCacheHealth.corrupted;
    }
    AppLogger.e('THREAD_CACHE', '$action failed, cache disabled: $error');
  }

  /// 删除数据库旁边的锁/临时文件
  Future<void> _deleteSiblings(String dbPath) async {
    try {
      final dir = Directory(p.dirname(dbPath));
      if (!await dir.exists()) return;
      final name = p.basename(dbPath);
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path != dbPath) {
          final sibling = p.basename(entity.path);
          if (sibling.startsWith(name)) await entity.delete();
        }
      }
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'delete siblings error: $e');
    }
  }

  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}

/// 顶层函数：供 `compute` 在后台 isolate 编码大快照
String _encodeSnapshot(Map<String, dynamic> map) => jsonEncode(map);

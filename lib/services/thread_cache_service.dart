import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/thread_cache_database.dart';
import 'package:mtbbs/core/utils/thread_cache_policy.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/models/thread_snapshot.dart';

/// 离线保存结果状态
enum ThreadCacheSaveStatus {
  saved,
  tooLarge,
  disabled,
  failed,
}

/// 离线保存结果
class ThreadCacheSaveResult {
  final ThreadCacheSaveStatus status;

  /// 实际大小（估算字节数）
  final int bytes;

  /// 单帖上限（字节）
  final int limit;

  final String? message;

  const ThreadCacheSaveResult(
    this.status, {
    this.bytes = 0,
    this.limit = 0,
    this.message,
  });

  bool get isSaved => status == ThreadCacheSaveStatus.saved;
}

/// 帖子缓存服务
///
/// 负责新帖判定、内容哈希、版本/TTL/单帖上限、写队列、离线保存与降级。
/// 不碰 UI，不发网络请求。
///
/// 所有写操作经单链 Future 串行化，避免同帖并发访问造成索引与正文不一致。
class ThreadCacheService {
  ThreadCacheService._();
  static final ThreadCacheService instance = ThreadCacheService._();

  /// 自动缓存默认保留天数（不含「永不过期」）
  static const int defaultTtlDays = 1;

  /// 单帖默认上限：128 KiB（纯文字快照足够，用户可在管理页调整）
  static const int defaultMaxBytesPerThread = 128 * 1024;

  /// 每帖默认保留的自动缓存正文版本数
  static const int defaultMaxVersions = kThreadAutoMaxVersions;

  /// 版本数可调范围
  static const int minMaxVersions = 1;
  static const int maxMaxVersions = 10;

  /// 单帖上限可调范围（KB）
  static const int minMaxKB = 16;
  static const int maxMaxKB = 10240;

  final ThreadCacheDatabase _db = ThreadCacheDatabase.instance;

  int _ttlDays = defaultTtlDays;
  int _maxBytesPerThread = defaultMaxBytesPerThread;
  int _maxVersions = defaultMaxVersions;

  Future<void> _queue = Future<void>.value();

  /// 数据库健康状态（App 壳层监听以提示一次损坏 Toast）
  ValueNotifier<ThreadCacheHealth> get health => _db.health;

  bool get isDisabled => _db.health.value == ThreadCacheHealth.corrupted;

  int get ttlDays => _ttlDays;
  int get maxBytesPerThread => _maxBytesPerThread;
  int get maxVersions => _maxVersions;

  /// 由设置层注入（TTL 下限 1 天；上限与版本数来自设置，缺省取 cache.json）
  void configure({int? ttlDays, int? maxBytesPerThread, int? maxVersions}) {
    if (ttlDays != null) _ttlDays = ttlDays <= 0 ? defaultTtlDays : ttlDays;
    if (maxBytesPerThread != null && maxBytesPerThread > 0) {
      _maxBytesPerThread = maxBytesPerThread;
    }
    if (maxVersions != null && maxVersions > 0) {
      _maxVersions = maxVersions;
    }
  }

  /// 账号标识见 `viewerTag`（core/utils/thread_cache_policy.dart）

  // ==================== 自动缓存 ====================

  /// 帖子成功加载后写入自动缓存。
  ///
  /// 返回该帖的缓存键（用于后续评论页回写）；不满足缓存条件、已禁用、
  /// 超限等返回 null。调用方应 `unawaited`，不要阻塞渲染。
  Future<String?> onThreadLoaded({
    required ThreadViewData data,
    required String host,
    required String viewer,
    String? authorid,
  }) {
    final key = autoCacheKey(
      data: data,
      host: host,
      viewer: viewer,
      authorid: authorid,
    );
    if (key == null) return Future<String?>.value();
    return _enqueue(() async {
      try {
        await _writeAuto(data: data, host: host, viewer: viewer, key: key);
        return key;
      } catch (e) {
        AppLogger.w('THREAD_CACHE', 'auto write failed: $e');
        return null;
      }
    });
  }

  /// 同步判断该帖是否应写入自动缓存，并返回缓存键。
  ///
  /// 条件：非作者筛选视图、楼主帖存在、楼主发帖时间是相对时间（新帖）。
  String? autoCacheKey({
    required ThreadViewData data,
    required String host,
    required String viewer,
    String? authorid,
  }) {
    if (isDisabled) return null;
    if (authorid != null && authorid.isNotEmpty) return null;
    final main = data.mainPost;
    if (main == null) return null;
    if (!isNewThreadTime(main.postTime)) return null;
    return ThreadSnapshot.autoKey(
      host: host,
      viewer: viewerTag(viewer),
      tid: data.tid,
      contentHash: threadContentHash(data.title, main.bbcode),
    );
  }

  Future<void> _writeAuto({
    required ThreadViewData data,
    required String host,
    required String viewer,
    required String key,
  }) async {
    if (isDisabled) return;
    if (!await _db.ensureReady()) return;

    final main = data.mainPost;
    if (main == null) return;

    final viewerTagValue = viewerTag(viewer);
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: _ttlDays));

    final existing = await _db.readSnapshot(key);
    if (existing != null) {
      var updated = existing.copyWith(
        totalPages: data.totalPages,
        lastVisitedAt: now,
        expiresAt: expiresAt,
      );
      updated = updated.withCommentPage(1, data.posts);
      if (updated.approxBytes > _maxBytesPerThread) {
        AppLogger.w(
          'THREAD_CACHE',
          'skip auto update over limit: ${updated.approxBytes} > '
          '$_maxBytesPerThread',
        );
        return;
      }
      if (!await _makeRoom(
        host: host,
        viewer: viewerTagValue,
        tid: data.tid,
        incomingKey: key,
        incomingBytes: updated.approxBytes,
      )) {
        return;
      }
      await _db.putSnapshot(updated);
      await _refreshExpiry(
        host: host,
        viewer: viewerTagValue,
        tid: data.tid,
        expiresAt: expiresAt,
      );
      return;
    }

    final snapshot = ThreadSnapshot(
      kind: ThreadCacheKind.auto,
      host: host,
      viewer: viewerTagValue,
      tid: data.tid,
      title: data.title,
      contentHash: threadContentHash(data.title, main.bbcode),
      postTimeText: main.postTime,
      isNewAtCapture: true,
      mainPost: main,
      commentPages: {1: List<PostItem>.from(data.posts)},
      cachedPages: const [1],
      totalPages: data.totalPages,
      createdAt: now,
      lastVisitedAt: now,
      expiresAt: expiresAt,
    ).recomputeBytes();

    if (snapshot.approxBytes > _maxBytesPerThread) {
      AppLogger.w(
        'THREAD_CACHE',
        'skip auto snapshot over limit: ${snapshot.approxBytes} > '
        '$_maxBytesPerThread',
      );
      return;
    }
    if (!await _makeRoom(
      host: host,
      viewer: viewerTagValue,
      tid: data.tid,
      incomingKey: key,
      incomingBytes: snapshot.approxBytes,
    )) {
      return;
    }
    if (await _db.putSnapshot(snapshot)) {
      await _refreshExpiry(
        host: host,
        viewer: viewerTagValue,
        tid: data.tid,
        expiresAt: expiresAt,
      );
    }
  }

  /// 评论页加载成功后回写。
  Future<void> onCommentPageLoaded({
    required String cacheKey,
    required int page,
    required List<PostItem> posts,
    required int totalPages,
  }) {
    if (isDisabled) return Future<void>.value();
    return _enqueue(() async {
      try {
        if (!await _db.ensureReady()) return;
        final existing = await _db.readSnapshot(cacheKey);
        if (existing == null) return;
        final now = DateTime.now();
        var updated = existing.copyWith(
          totalPages: totalPages,
          lastVisitedAt: now,
          expiresAt: now.add(Duration(days: _ttlDays)),
        );
        updated = updated.withCommentPage(page, posts);
        if (updated.approxBytes > _maxBytesPerThread) {
          AppLogger.w(
            'THREAD_CACHE',
            'skip comment page over limit: ${updated.approxBytes} > '
            '$_maxBytesPerThread',
          );
          return;
        }
        if (!await _makeRoom(
          host: updated.host,
          viewer: viewerTag(updated.viewer ?? 'guest'),
          tid: updated.tid,
          incomingKey: cacheKey,
          incomingBytes: updated.approxBytes,
        )) {
          return;
        }
        await _db.putSnapshot(updated);
        await _refreshExpiry(
          host: updated.host,
          viewer: viewerTag(updated.viewer ?? 'guest'),
          tid: updated.tid,
          expiresAt: updated.expiresAt ?? now.add(Duration(days: _ttlDays)),
        );
      } catch (e) {
        AppLogger.w('THREAD_CACHE', 'comment page write failed: $e');
      }
    });
  }

  /// 为自动缓存腾出空间：先按版本上限淘汰最旧版本，再按单帖上限淘汰。
  /// 返回 false 表示即使删光旧版本，新内容仍超限。
  Future<bool> _makeRoom({
    required String host,
    required String viewer,
    required String tid,
    required String incomingKey,
    required int incomingBytes,
  }) async {
    final metas = (await _db.listMeta(kind: ThreadCacheKind.auto))
        .where(
          (m) =>
              m.key != incomingKey &&
              m.host == host &&
              m.tid == tid &&
              (m.viewer ?? 'guest') == viewer,
        )
        .toList()
      ..sort((a, b) => a.sortTime.compareTo(b.sortTime));

    final toDelete = <String>[];
    while (metas.length + 1 > _maxVersions) {
      toDelete.add(metas.removeAt(0).key);
    }
    var total = incomingBytes + metas.fold<int>(0, (s, m) => s + m.approxBytes);
    while (total > _maxBytesPerThread && metas.isNotEmpty) {
      final removed = metas.removeAt(0);
      toDelete.add(removed.key);
      total -= removed.approxBytes;
    }
    if (total > _maxBytesPerThread) return false;
    if (toDelete.isNotEmpty) {
      AppLogger.i('THREAD_CACHE', 'evict auto versions: $toDelete');
      await _db.deleteKeys(toDelete);
    }
    return true;
  }

  Future<void> _refreshExpiry({
    required String host,
    required String viewer,
    required String tid,
    required DateTime expiresAt,
  }) => _db.refreshAutoExpiry(
    host: host,
    viewer: viewerTag(viewer),
    tid: tid,
    expiresAt: expiresAt,
  );

  // ==================== 离线帖子 ====================

  /// 是否已有离线副本
  Future<bool> hasOffline({required String host, required String tid}) async =>
      await _db.readMeta(ThreadSnapshot.offlineKey(host: host, tid: tid)) !=
      null;

  /// 保存离线副本（同键覆盖）
  Future<ThreadCacheSaveResult> saveOffline({
    required ThreadViewData data,
    required Map<int, List<PostItem>> commentPages,
    required String host,
    required String viewer,
  }) {
    return _enqueue(() async {
      if (isDisabled) {
        return const ThreadCacheSaveResult(ThreadCacheSaveStatus.disabled);
      }
      try {
        if (!await _db.ensureReady()) {
          return const ThreadCacheSaveResult(ThreadCacheSaveStatus.disabled);
        }
        final main = data.mainPost;
        if (main == null) {
          return const ThreadCacheSaveResult(
            ThreadCacheSaveStatus.failed,
            message: '没有可保存的楼主帖',
          );
        }
        final pages = <int, List<PostItem>>{
          for (final e in commentPages.entries)
            if (e.key > 0) e.key: List<PostItem>.from(e.value),
        };
        final now = DateTime.now();
        final snapshot = ThreadSnapshot(
          kind: ThreadCacheKind.offline,
          host: host,
          viewer: null,
          savedBy: viewerTag(viewer),
          tid: data.tid,
          title: data.title,
          contentHash: threadContentHash(data.title, main.bbcode),
          postTimeText: main.postTime,
          isNewAtCapture: isNewThreadTime(main.postTime),
          mainPost: main,
          commentPages: pages,
          cachedPages: pages.keys.toList()..sort(),
          totalPages: data.totalPages,
          createdAt: now,
          savedAt: now,
        ).recomputeBytes();

        if (snapshot.approxBytes > _maxBytesPerThread) {
          return ThreadCacheSaveResult(
            ThreadCacheSaveStatus.tooLarge,
            bytes: snapshot.approxBytes,
            limit: _maxBytesPerThread,
          );
        }
        final ok = await _db.putSnapshot(snapshot);
        return ok
            ? ThreadCacheSaveResult(
                ThreadCacheSaveStatus.saved,
                bytes: snapshot.approxBytes,
                limit: _maxBytesPerThread,
              )
            : const ThreadCacheSaveResult(
                ThreadCacheSaveStatus.failed,
                message: '写入缓存失败',
              );
      } catch (e) {
        AppLogger.w('THREAD_CACHE', 'save offline failed: $e');
        return ThreadCacheSaveResult(
          ThreadCacheSaveStatus.failed,
          message: '$e',
        );
      }
    });
  }

  // ==================== 查询 / 删除 ====================

  /// 只读快照（索引时间覆盖到正文，保证 TTL 刷新后的导出一致）
  Future<ThreadSnapshot?> readSnapshot(String key) async {
    final snapshot = await _db.readSnapshot(key);
    if (snapshot == null) return null;
    final meta = await _db.readMeta(key);
    if (meta == null) return snapshot;
    return snapshot.copyWith(
      lastVisitedAt: meta.lastVisitedAt,
      expiresAt: meta.expiresAt,
      savedAt: meta.savedAt,
      approxBytes: meta.approxBytes,
    );
  }

  Future<List<ThreadSnapshotMeta>> listAuto({String? viewer}) async {
    final tag = viewer == null ? null : viewerTag(viewer);
    final metas = await _db.listMeta(kind: ThreadCacheKind.auto);
    if (tag == null) return metas;
    return [
      for (final m in metas)
        if ((m.viewer ?? 'guest') == tag) m,
    ];
  }

  Future<List<ThreadSnapshotMeta>> listOffline() =>
      _db.listMeta(kind: ThreadCacheKind.offline);

  /// 某帖的全部缓存：自动（当前账号）+ 离线
  Future<List<ThreadSnapshotMeta>> snapshotsForThread({
    required String host,
    required String tid,
    required String viewer,
  }) async {
    final tag = viewerTag(viewer);
    final all = await _db.listMeta();
    return [
      for (final m in all)
        if (m.tid == tid &&
            m.host == host &&
            (m.isOffline || (m.viewer ?? 'guest') == tag))
          m,
    ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));
  }

  Future<bool> deleteSnapshot(String key) => _db.deleteKeys([key]);

  /// 删除某帖全部自动缓存版本
  Future<bool> deleteAutoThread({
    required String host,
    required String viewer,
    required String tid,
  }) async {
    final tag = viewerTag(viewer);
    final metas = await _db.listMeta(kind: ThreadCacheKind.auto);
    return _db.deleteKeys([
      for (final m in metas)
        if (m.host == host && m.tid == tid && (m.viewer ?? 'guest') == tag)
          m.key,
    ]);
  }

  /// 删除离线副本
  Future<bool> deleteOfflineThread({
    required String host,
    required String tid,
  }) => _db.deleteKeys([ThreadSnapshot.offlineKey(host: host, tid: tid)]);

  Future<bool> clearAuto({String? viewer}) =>
      _db.clearKind(ThreadCacheKind.auto, viewer: viewer == null ? null : viewerTag(viewer));

  Future<bool> clearOffline() => _db.clearKind(ThreadCacheKind.offline);

  /// 清理已过期的自动缓存，返回条数（App 启动时与管理页刷新时调用）
  Future<int> cleanExpired() async => _db.deleteExpired(DateTime.now());

  Future<ThreadCacheStats> stats() => _db.stats();

  Future<int> fileSizeBytes() => _db.fileSizeBytes();

  /// 重建缓存库（保留损坏备份）
  Future<bool> rebuild({bool deleteIfRenameFails = false}) async {
    return _db.rebuild(deleteIfRenameFails: deleteIfRenameFails);
  }

  /// 清空并重建缓存库（离线副本会丢失）
  Future<bool> clearAndRebuild() async {
    return _db.clearAndRebuild();
  }

  // ==================== 内部 ====================

  /// 单链队列：所有写操作串行执行
  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

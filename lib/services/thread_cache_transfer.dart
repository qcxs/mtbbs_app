import 'dart:convert';
import 'dart:io';

import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/thread_cache_database.dart';
import 'package:mtbbs/core/utils/thread_cache_policy.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/services/thread_cache_service.dart';
import 'package:path/path.dart' as p;

/// 导入预览摘要
class ThreadCacheImportPreview {
  /// 顶层格式是否合法；false 时 [error] 给出原因
  final bool valid;
  final String? error;

  final int total;
  final int autoCount;
  final int offlineCount;
  final int invalidCount;
  final int oversizedCount;
  final int conflictAuto;
  final int conflictOffline;

  const ThreadCacheImportPreview({
    required this.valid,
    this.error,
    this.total = 0,
    this.autoCount = 0,
    this.offlineCount = 0,
    this.invalidCount = 0,
    this.oversizedCount = 0,
    this.conflictAuto = 0,
    this.conflictOffline = 0,
  });

  int get importableCount => total - invalidCount - oversizedCount;
}

/// 导入结果
class ThreadCacheImportResult {
  final bool fatal;
  final String? message;

  final int imported;
  final int skipped;
  final int failed;
  final int tooLarge;
  final int conflicts;
  final List<String> details;

  const ThreadCacheImportResult({
    this.fatal = false,
    this.message,
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
    this.tooLarge = 0,
    this.conflicts = 0,
    this.details = const [],
  });
}

/// 帖子缓存导入 / 导出
///
/// 只处理 JSON 与文件，不发网络请求、不执行 BBCode/HTML/脚本。
/// 导出为 UTF-8 pretty-print 明文，不加密。
class ThreadCacheTransfer {
  ThreadCacheTransfer._();
  static final ThreadCacheTransfer instance = ThreadCacheTransfer._();

  final ThreadCacheDatabase _db = ThreadCacheDatabase.instance;
  final ThreadCacheService _service = ThreadCacheService.instance;

  // ==================== 导出 ====================

  /// 收集某类型的全部快照（自动缓存可按账号过滤）
  Future<List<ThreadSnapshot>> collectForExport({
    required ThreadCacheKind kind,
    String? viewer,
  }) async {
    final metas = kind == ThreadCacheKind.auto
        ? await _service.listAuto(viewer: viewer)
        : await _service.listOffline();
    final result = <ThreadSnapshot>[];
    for (final meta in metas) {
      final snapshot = await _service.readSnapshot(meta.key);
      if (snapshot != null) result.add(snapshot);
    }
    return result;
  }

  /// 生成导出 JSON（pretty-print）
  String buildExportJson(List<ThreadSnapshot> snapshots) {
    final map = <String, dynamic>{
      'format': kThreadCacheExportFormat,
      'schemaVersion': kThreadSnapshotSchemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': '',
      'items': [for (final s in snapshots) s.toMap()],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 平台「另存为」不可用时的兜底：写入 `{appDataDir}/exports/`
  Future<String> writeExportFallback(String content) async {
    final dirPath = await AppPaths.exportsDir;
    await Directory(dirPath).create(recursive: true);
    final file = File(
      p.join(dirPath, 'mtbbs_threads_${timestampForFileName()}.json'),
    );
    await file.writeAsString(content);
    AppLogger.i('THREAD_CACHE', 'export fallback: ${file.path}');
    return file.path;
  }

  /// 复制原始 `threads.sembast` 到指定目录（损坏抢救备份）
  Future<String?> copyRawTo(String targetDir) async {
    try {
      final source = File(await AppPaths.threadDatabasePath);
      if (!await source.exists()) return null;
      await Directory(targetDir).create(recursive: true);
      final target = p.join(
        targetDir,
        'threads_${timestampForFileName()}.sembast',
      );
      await source.copy(target);
      AppLogger.i('THREAD_CACHE', 'raw backup: $target');
      return target;
    } catch (e) {
      AppLogger.w('THREAD_CACHE', 'copy raw failed: $e');
      return null;
    }
  }

  // ==================== 导入 ====================

  /// 导入前预览：解析文件并统计冲突/超限/损坏
  Future<ThreadCacheImportPreview> preview(
    String json, {
    required String viewer,
  }) async {
    final parsed = _parse(json);
    if (parsed.error != null) {
      return ThreadCacheImportPreview(valid: false, error: parsed.error);
    }
    final tag = viewerTag(viewer);
    final metas = await _db.listMeta();
    final keys = {for (final m in metas) m.key};
    var autoCount = 0;
    var offlineCount = 0;
    var oversized = 0;
    var conflictAuto = 0;
    var conflictOffline = 0;
    for (final item in parsed.items) {
      if (item.approxBytes > _service.maxBytesPerThread) {
        oversized++;
        continue;
      }
      if (item.isAuto) {
        autoCount++;
        final key = ThreadSnapshot.autoKey(
          host: item.host,
          viewer: tag,
          tid: item.tid,
          contentHash: item.contentHash,
        );
        if (keys.contains(key)) conflictAuto++;
      } else {
        offlineCount++;
        if (keys.contains(
          ThreadSnapshot.offlineKey(host: item.host, tid: item.tid),
        )) {
          conflictOffline++;
        }
      }
    }
    return ThreadCacheImportPreview(
      valid: true,
      total: parsed.items.length + parsed.invalidCount,
      autoCount: autoCount,
      offlineCount: offlineCount,
      invalidCount: parsed.invalidCount,
      oversizedCount: oversized,
      conflictAuto: conflictAuto,
      conflictOffline: conflictOffline,
    );
  }

  /// 执行导入
  ///
  /// - 自动缓存：`viewer` 改写为当前账号；`lastVisitedAt` 置为导入时间，
  ///   `expiresAt = now + threadCacheDays`；同键保留较新的版本。
  /// - 离线副本：保留 `savedBy` / `savedAt`；冲突时按 [overwriteOffline] 覆盖或跳过。
  Future<ThreadCacheImportResult> importJson(
    String json, {
    required String viewer,
    required bool overwriteOffline,
  }) async {
    if (_service.isDisabled) {
      return const ThreadCacheImportResult(
        fatal: true,
        message: '缓存功能已禁用，请先在缓存管理中处理损坏文件',
      );
    }
    final parsed = _parse(json);
    if (parsed.error != null) {
      return ThreadCacheImportResult(fatal: true, message: parsed.error);
    }
    if (!await _db.ensureReady()) {
      return const ThreadCacheImportResult(fatal: true, message: '缓存库不可用');
    }

    final tag = viewerTag(viewer);
    final now = DateTime.now();
    final expiresAt = now.add(Duration(days: _service.ttlDays));

    var imported = 0;
    var skipped = 0;
    var failed = parsed.invalidCount;
    var tooLarge = 0;
    var conflicts = 0;
    final details = <String>[];

    for (final item in parsed.items) {
      try {
        if (item.isAuto) {
          final rewritten = item
              .copyWith(viewer: tag, lastVisitedAt: now, expiresAt: expiresAt)
              .recomputeBytes();
          if (rewritten.approxBytes > _service.maxBytesPerThread) {
            tooLarge++;
            continue;
          }
          final key = rewritten.storageKey;
          final existingMeta = await _db.readMeta(key);
          if (existingMeta != null) {
            final existingTime = existingMeta.sortTime;
            final importedTime = item.lastVisitedAt ?? item.createdAt;
            if (!importedTime.isAfter(existingTime)) {
              conflicts++;
              skipped++;
              continue;
            }
            conflicts++;
          }
          if (await _db.putSnapshot(rewritten)) {
            imported++;
          } else {
            failed++;
          }
        } else {
          final key = item.storageKey;
          final exists = await _db.readMeta(key) != null;
          if (exists && !overwriteOffline) {
            conflicts++;
            skipped++;
            continue;
          }
          if (exists) conflicts++;
          var snapshot = item.recomputeBytes();
          if (snapshot.approxBytes > _service.maxBytesPerThread) {
            tooLarge++;
            continue;
          }
          if (await _db.putSnapshot(snapshot)) {
            imported++;
          } else {
            failed++;
          }
        }
      } catch (e, st) {
        failed++;
        if (details.length < 20) details.add('$e');
        AppLogger.w('THREAD_CACHE', 'import item failed: $e\n$st');
      }
    }

    AppLogger.i(
      'THREAD_CACHE',
      'import done: ok=$imported skip=$skipped fail=$failed '
          'large=$tooLarge conflict=$conflicts',
    );
    return ThreadCacheImportResult(
      imported: imported,
      skipped: skipped,
      failed: failed,
      tooLarge: tooLarge,
      conflicts: conflicts,
      details: details,
    );
  }

  // ==================== 内部 ====================

  _ParsedExport _parse(String json) {
    dynamic decoded;
    try {
      decoded = jsonDecode(json);
    } catch (e) {
      return const _ParsedExport(error: '文件不是合法 JSON');
    }
    if (decoded is! Map) {
      return const _ParsedExport(error: '文件结构不正确');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['format'] != kThreadCacheExportFormat) {
      return const _ParsedExport(error: '不是 mtbbs 帖子缓存文件');
    }
    final version = (map['schemaVersion'] as num?)?.toInt();
    if (version == null) {
      return const _ParsedExport(error: '缺少 schemaVersion');
    }
    if (version > kThreadSnapshotSchemaVersion) {
      return const _ParsedExport(error: '文件版本过高，请升级 App');
    }
    if (version != kThreadSnapshotSchemaVersion) {
      return const _ParsedExport(error: '不支持的文件版本');
    }
    final rawItems = map['items'];
    if (rawItems is! List) {
      return const _ParsedExport(error: '缺少 items 列表');
    }
    final items = <ThreadSnapshot>[];
    var invalid = 0;
    for (final raw in rawItems) {
      if (raw is! Map) {
        invalid++;
        continue;
      }
      try {
        items.add(ThreadSnapshot.fromMap(Map<String, dynamic>.from(raw)));
      } catch (e) {
        invalid++;
        AppLogger.w('THREAD_CACHE', 'skip bad import item: $e');
      }
    }
    return _ParsedExport(items: items, invalidCount: invalid);
  }

  /// 文件名时间戳：`yyyyMMdd_HHmmss`
  static String timestampForFileName() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}

class _ParsedExport {
  final String? error;
  final List<ThreadSnapshot> items;
  final int invalidCount;

  const _ParsedExport({
    this.error,
    this.items = const [],
    this.invalidCount = 0,
  });
}

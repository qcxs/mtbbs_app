import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 头像 301 重定向映射的持久化后端。
///
/// 生产环境走统一 [DatabaseHelper]（sembast 单库，每条映射一条记录）；
/// 测试可注入内存实现，避免依赖磁盘路径。
abstract class AvatarRedirectBackend {
  /// 读取全部记录：key=原始URL → `{final: String?, updatedAt: int(ms)}`
  Future<Map<String, Map<String, Object?>>> getAll();

  /// 写入/更新一条映射（[finalUrl] 为 null 表示无重定向）
  Future<void> put(String url, String? finalUrl, DateTime updatedAt);

  /// 批量删除记录
  Future<void> delete(List<String> urls);
}

class _DbBackend implements AvatarRedirectBackend {
  const _DbBackend();

  @override
  Future<Map<String, Map<String, Object?>>> getAll() =>
      DatabaseHelper.instance.getAllAvatarRedirects();

  @override
  Future<void> put(String url, String? finalUrl, DateTime updatedAt) =>
      DatabaseHelper.instance.putAvatarRedirect(url, finalUrl, updatedAt);

  @override
  Future<void> delete(List<String> urls) =>
      DatabaseHelper.instance.deleteAvatarRedirects(urls);
}

/// 头像 301 重定向映射的持久化存储。
///
/// 键为原始头像 URL（如 `{base}/uc_server/avatar.php?uid=1&size=middle`），
/// 值为解析后的最终 URL；值为 null 表示已验证无重定向。
///
/// 磁盘缓存以「最终 URL」为 key，不持久化该映射就无法在跳过 HEAD 请求的
/// 前提下定位缓存文件。本存储让 [UserAvatar] 在缓存命中时零网络请求，
/// 仅在缓存缺失/过期时才发 HEAD 重新解析。
///
/// 优化点：
/// - **过期**：每条记录带时间戳，超过 [cacheTtl]（与头像缓存周期一致）后
///   视为未知并清理，触发重新 HEAD，避免头像 URL 变化后永远显示旧头像。
/// - **压缩**：无重定向存 null（不冗余存完整 URL）；每条映射一条 sembast
///   记录增量写入，替代整体 JSON 全量重写。
/// - **容量**：[maxEntries] 上限，启动加载时惰性跳过过期项并淘汰最旧。
class AvatarRedirectStore {
  AvatarRedirectStore._();
  static final AvatarRedirectStore instance = AvatarRedirectStore._();

  /// 最大映射条数，超出后淘汰最久未更新的记录（测试可调小）
  int maxEntries = 3000;

  /// 持久化后端（测试可注入内存实现）
  AvatarRedirectBackend backend = const _DbBackend();

  final Map<String, String?> _map = {}; // url → 最终URL（null=无重定向）
  final Map<String, int> _updatedAt = {}; // url → 最后解析时间戳(ms)

  /// 映射有效期；null 或非正时长表示永不过期（与头像缓存「永不过期」语义一致）
  Duration? cacheTtl;

  Future<void>? _loading;
  Timer? _saveTimer;
  final Set<String> _dirty = {}; // 待增量写入的 url
  final Set<String> _deleted = {}; // 待删除的 url

  /// 从数据库加载映射（幂等，只加载一次）。
  Future<void> loadIfNeeded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      final all = await backend.getAll();
      final obsolete = <String>[];
      for (final entry in all.entries) {
        final value = entry.value;
        // 旧格式迁移：整体 JSON 存于固定 key "redirects"
        if (entry.key == 'redirects' && value['value'] is String) {
          await _migrateLegacy(value['value'] as String);
          obsolete.add(entry.key);
          continue;
        }
        final ts = value['updatedAt'] is int
            ? value['updatedAt'] as int
            : now.millisecondsSinceEpoch;
        // 惰性跳过过期记录（不载入内存）
        if (_isExpired(now, ts)) {
          obsolete.add(entry.key);
          continue;
        }
        _map[entry.key] = value['final'] as String?;
        _updatedAt[entry.key] = ts;
      }

      // 超容量上限：淘汰最久未更新的记录
      if (_map.length > maxEntries) {
        final extra = _map.length - maxEntries;
        final oldest = _updatedAt.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (final e in oldest.take(extra)) {
          _map.remove(e.key);
          _updatedAt.remove(e.key);
          obsolete.add(e.key);
        }
      }

      if (obsolete.isNotEmpty) {
        unawaited(backend.delete(obsolete));
      }
    } catch (e) {
      AppLogger.w('AVATAR', 'load redirect map failed: $e');
    }
  }

  /// 旧格式（整体 JSON `Map<String, String>`）迁移为新格式记录
  Future<void> _migrateLegacy(String raw) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      decoded.forEach((k, v) {
        final url = k.toString();
        _map[url] = v is String ? v : null;
        _updatedAt[url] = now;
        _dirty.add(url);
      });
      // 迁移结果写回新格式
      await _flushSave();
    }
  }

  /// 查询映射。
  ///
  /// 返回 `known=false` 表示从未解析过或已过期（需重新 HEAD）；
  /// `known=true` 时 [value] 为最终 URL（null 归一为原始 URL，表示无重定向）。
  ({bool known, String value}) lookup(String url) {
    if (!_map.containsKey(url)) return (known: false, value: url);
    final now = DateTime.now();
    if (_isExpired(now, _updatedAt[url]!)) {
      // 过期：视为未知并清理，触发重新解析
      _map.remove(url);
      _updatedAt.remove(url);
      _scheduleDelete(url);
      return (known: false, value: url);
    }
    return (known: true, value: _map[url] ?? url);
  }

  /// 记录映射并持久化（内存即时生效，磁盘防抖 1 秒批量写入）。
  ///
  /// [finalUrl] 等于 [url]（无重定向）时归一为 null 存储，避免冗余。
  void set(String url, String? finalUrl) {
    final normalized = (finalUrl == url) ? null : finalUrl;
    _map[url] = normalized;
    _updatedAt[url] = DateTime.now().millisecondsSinceEpoch;
    _scheduleSave(url);
  }

  /// 是否过期：TTL 为 null/非正（永不过期）时不淘汰
  bool _isExpired(DateTime now, int updatedAtMs) {
    final ttl = cacheTtl;
    if (ttl == null || ttl <= Duration.zero) return false;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(updatedAtMs)) >
        ttl;
  }

  void _scheduleSave(String url) {
    _dirty.add(url);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_flushSave()),
    );
  }

  void _scheduleDelete(String url) {
    _deleted.add(url);
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_flushSave()),
    );
  }

  Future<void> _flushSave() async {
    final dirty = _dirty.toList();
    final deleted = _deleted.toList();
    _dirty.clear();
    _deleted.clear();
    try {
      for (final url in dirty) {
        final ts = _updatedAt[url];
        if (ts == null) continue;
        await backend.put(
          url,
          _map[url],
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
      }
      if (deleted.isNotEmpty) {
        await backend.delete(deleted);
      }
    } catch (e) {
      AppLogger.w('AVATAR', 'save redirect map failed: $e');
    }
  }

  // =================== 测试辅助 ===================

  /// 重置内存状态与后端（测试隔离用）
  @visibleForTesting
  void debugReset() {
    _map.clear();
    _updatedAt.clear();
    _dirty.clear();
    _deleted.clear();
    _saveTimer?.cancel();
    _saveTimer = null;
    _loading = null;
    cacheTtl = null;
    maxEntries = 3000;
    backend = const _DbBackend();
  }

  /// 覆盖某条映射的更新时间（测试模拟过期用）
  @visibleForTesting
  void debugSetUpdatedAt(String url, DateTime at) {
    _updatedAt[url] = at.millisecondsSinceEpoch;
  }

  /// 立即冲刷防抖写入（测试验证持久化结果用）
  @visibleForTesting
  Future<void> debugFlush() => _flushSave();
}

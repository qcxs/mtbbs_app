import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mtbbs/api/site/cdn/export.dart' as cdn_api;
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 站点 CDN 的自动识别结果存储（按 host 隔离）。
///
/// 站点 CDN 由 Discuz 自己下发（模板头部内联的 `STATICURL`，见
/// `api/site/cdn/http.dart`），**不再由用户配置**——用户既不知道也不需要知道。
/// 这里只负责：内存缓存 + sembast 持久化 + 变更通知。
///
/// 读取方统一走 `SiteStore.cdnUrl`（命中则用识别值，否则回退站点 baseUrl）。
class SiteCdnStore extends ChangeNotifier {
  SiteCdnStore._();
  static final SiteCdnStore instance = SiteCdnStore._();

  /// 持久化键：整个 host → {cdn, at} 映射存一条 meta
  static const String _metaKey = 'site_cdn_map';

  /// 识别结果有效期：超过后启动/切站会重新探测（手动刷新不受此限制）
  static const Duration ttl = Duration(days: 1);

  final Map<String, String> _cdn = {};
  final Map<String, int> _at = {};
  Future<void>? _loading;

  /// 同步读取某 host 已识别的 CDN；未识别到时返回 null（调用方回退 baseUrl）
  String? cdnFor(String host) => _cdn[host];

  /// 从数据库加载（幂等，只加载一次）
  Future<void> loadIfNeeded() => _loading ??= _load();

  /// 是否需要（重新）探测：从未探测过，或距**上次探测**已超过 [ttl]。
  ///
  /// 判据是"上次探测时间"而非"是否识别到 CDN"：无独立 CDN 的站点（未配 `staticurl`）
  /// 探测结果为负，也必须记时间戳，否则每次启动都会重探（见 docs/07 #90）。
  bool needsDetect(String host) => cdnNeedsDetect(_at[host]);

  Future<void> _load() async {
    try {
      final raw = await DatabaseHelper.instance.getMeta(_metaKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        // at：上次探测时间（识别成功与"已探测但无 CDN"都会写入）
        _at[entry.key] = (value['at'] as num?)?.toInt() ?? 0;
        // cdn：仅识别到才写；空串 = 探测过但无 CDN（不回填 _cdn，cdnFor 仍返回 null）
        final cdn = value['cdn']?.toString() ?? '';
        if (cdn.isNotEmpty) _cdn[entry.key] = cdn;
      }
    } catch (e) {
      AppLogger.w('CDN', 'load site cdn map failed: $e');
    }
  }

  /// 记录识别结果并持久化，变更时通知监听者
  Future<void> setCdn(String host, String cdn) async {
    final changed = _cdn[host] != cdn;
    _cdn[host] = cdn;
    _at[host] = DateTime.now().millisecondsSinceEpoch;
    if (changed) notifyListeners();
    await _persist();
  }

  /// 记录一次"已探测但未识别到 CDN"的负结果：只更新时间戳并持久化。
  ///
  /// 目的：让无 CDN 的站点也走 [ttl] 周期，而不是每次启动都重探。
  Future<void> markChecked(String host) async {
    _at[host] = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      // 以 _cdn 与 _at 的并集为准：负结果只有 _at、没有 _cdn
      final hosts = {..._cdn.keys, ..._at.keys};
      final payload = <String, dynamic>{
        for (final h in hosts) h: {'cdn': _cdn[h] ?? '', 'at': _at[h] ?? 0},
      };
      await DatabaseHelper.instance.setMeta(_metaKey, jsonEncode(payload));
    } catch (e) {
      AppLogger.w('CDN', 'save site cdn map failed: $e');
    }
  }

  /// 重置内存状态（测试隔离用）
  @visibleForTesting
  void debugReset() {
    _cdn.clear();
    _at.clear();
    _loading = null;
  }
}

/// 纯函数：按"上次探测时间"判断是否需要重新探测 CDN（供单测，不碰持久化）。
///
/// [lastCheckedAtMs] = 上次探测时间（识别成功或"已探测但无 CDN"都会记录）；
/// null = 从未探测过 → 需要。距 [now] 严格超过 [ttl] 才需要重探。
bool cdnNeedsDetect(
  int? lastCheckedAtMs, {
  DateTime? now,
  Duration ttl = SiteCdnStore.ttl,
}) {
  if (lastCheckedAtMs == null) return true;
  final at = DateTime.fromMillisecondsSinceEpoch(lastCheckedAtMs);
  return (now ?? DateTime.now()).difference(at) > ttl;
}

/// 探测并记录某站点的 CDN；返回当前生效的 CDN（未识别到时为 null）。
///
/// - [force] 为 true 时忽略 [SiteCdnStore.ttl]（设置页「刷新 CDN」用）
/// - 探测**完成但未识别到** CDN 时也会记录时间戳（负结果）：这样无 CDN 的站点
///   按 [SiteCdnStore.ttl] 定期重探，而不是每次启动都重试
/// - 探测**抛异常**时不记录时间戳（下次启动/切站会再试），仅打 WARN 日志
Future<String?> detectSiteCdn({
  required String host,
  Dio? dio,
  bool force = false,
}) async {
  final store = SiteCdnStore.instance;
  if (!force && !store.needsDetect(host)) return store.cdnFor(host);
  try {
    final result = await cdn_api.fetchSiteCdn(dio ?? ApiService().dio);
    final cdn = result['success'] == true ? result['cdn']?.toString() : null;
    if (cdn != null && cdn.isNotEmpty) {
      await store.setCdn(host, cdn);
      AppLogger.i('CDN', '$host ← $cdn');
      return cdn;
    }
    // 已探测但无 CDN（站点未配 staticurl / 无独立静态域）：记负结果时间戳
    await store.markChecked(host);
    AppLogger.w('CDN', '$host 探测未识别到 CDN：${result['message'] ?? '?'}');
  } catch (e) {
    AppLogger.w('CDN', '$host 探测失败: $e');
  }
  return store.cdnFor(host);
}

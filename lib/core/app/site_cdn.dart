import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mtbbs/api/site/cdn/export.dart' as cdn_api;
import 'package:mtbbs/core/settings/settings_repository.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 站点 CDN 的自动识别结果（站点派生状态，按 host 隔离）。
///
/// 存储在 [SettingsRepository] 的 `SiteSettings.cdn` 中；读取方统一走
/// `SiteStore.cdnUrl`（命中则用识别值，否则回退站点 baseUrl）。
class SiteCdnStore extends ChangeNotifier {
  SiteCdnStore._();
  static final SiteCdnStore instance = SiteCdnStore._();

  /// 识别结果有效期：超过后启动/切站会重新探测（手动刷新不受此限制）
  static const Duration ttl = Duration(days: 1);

  SettingsRepository get _settings => SettingsRepository.instance;

  /// 同步读取某 host 已识别的 CDN；未识别到时返回 null（调用方回退 baseUrl）
  String? cdnFor(String host) => _settings.cdnFor(host);

  /// 是否需要（重新）探测：从未探测过，或距**上次探测**已超过 [ttl]。
  bool needsDetect(String host) => cdnNeedsDetect(_settings.cdnCheckedAt(host));

  /// 记录识别结果并持久化，变更时通知监听者
  Future<void> setCdn(String host, String cdn) async {
    final changed = cdnFor(host) != cdn;
    await _settings.setCdn(host, cdn);
    if (changed) notifyListeners();
  }

  /// 记录一次"已探测但未识别到 CDN"的负结果：只更新时间戳并持久化。
  Future<void> markChecked(String host) async {
    await _settings.markCdnChecked(host);
  }
}

/// 纯函数：按"上次探测时间"判断是否需要重新探测 CDN（供单测，不碰持久化）。
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
    await store.markChecked(host);
    AppLogger.w('CDN', '$host 探测未识别到 CDN：${result['message'] ?? '?'}');
  } catch (e) {
    AppLogger.w('CDN', '$host 探测失败: $e');
  }
  return store.cdnFor(host);
}

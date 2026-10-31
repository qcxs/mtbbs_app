import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/models/settings/account_settings.dart';
import 'package:mtbbs/models/settings/app_settings.dart';
import 'package:mtbbs/models/settings/site_settings.dart';

/// 分层设置的唯一读写入口。
///
/// - 应用设置：一份 [AppSettings]
/// - 站点设置：每个 host 一份 [SiteSettings]
/// - 账号设置：每个 `host|uid` 一份 [AccountSettings]（预留）
///
/// 所有 getter 都是同步的：启动时 [loadAll] 把文档读进内存，之后的
/// ApiService / 路由 redirect / 图片缓存都能直接按 host 查询，不再依赖
/// 「切站时把值 push 到模块变量」。
class SettingsRepository {
  SettingsRepository._();
  static final SettingsRepository instance = SettingsRepository._();

  DatabaseHelper get _db => DatabaseHelper.instance;

  AppSettings _app = AppSettings.defaults();
  final Map<String, SiteSettings> _sites = {};
  final Map<String, AccountSettings> _accounts = {};

  AppSettings get app => _app;

  /// 按 host 取站点设置；未知站点返回默认值（并记住，供后续写入）
  SiteSettings site(String host) =>
      _sites.putIfAbsent(host, () => SiteSettings.defaults(host));

  AccountSettings account(String host, String uid) => _accounts.putIfAbsent(
    '$host|$uid',
    () => AccountSettings.defaults(host, uid),
  );

  /// 启动时加载：应用文档 + 给定站点的站点文档。
  ///
  /// 文档不存在时使用默认值（本次为破坏性重构，不读取旧扁平键）。
  Future<void> loadAll(Iterable<String> hosts) async {
    await loadApp();
    for (final host in hosts) {
      await loadSite(host);
    }
  }

  Future<AppSettings> loadApp() async {
    try {
      final raw = await _db.getAppSettingsRaw();
      if (raw != null && raw.isNotEmpty) {
        _app = AppSettings.fromMap(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      }
    } catch (e) {
      AppLogger.w('SETTINGS', 'load app settings failed: $e');
      _app = AppSettings.defaults();
    }
    return _app;
  }

  Future<SiteSettings> loadSite(String host) async {
    try {
      final raw = await _db.getSiteSettingsRaw(host);
      if (raw != null && raw.isNotEmpty) {
        _sites[host] = SiteSettings.fromMap(
          host,
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      } else {
        _sites[host] = SiteSettings.defaults(host);
      }
    } catch (e) {
      AppLogger.w('SETTINGS', 'load site settings $host failed: $e');
      _sites[host] = SiteSettings.defaults(host);
    }
    return _sites[host]!;
  }

  Future<void> saveApp() async {
    try {
      await _db.setAppSettingsRaw(jsonEncode(_app.toMap()));
    } catch (e) {
      AppLogger.w('SETTINGS', 'save app settings failed: $e');
    }
  }

  Future<void> setApp(AppSettings settings) async {
    _app = settings;
    await saveApp();
  }

  Future<void> saveSite(String host) async {
    try {
      await _db.setSiteSettingsRaw(host, jsonEncode(site(host).toMap()));
    } catch (e) {
      AppLogger.w('SETTINGS', 'save site settings $host failed: $e');
    }
  }

  Future<SiteSettings> updateSite(
    String host,
    SiteSettings Function(SiteSettings current) update,
  ) async {
    _sites[host] = update(site(host));
    await saveSite(host);
    return _sites[host]!;
  }

  /// 删除站点时级联清理
  Future<void> deleteSite(String host) async {
    _sites.remove(host);
    _accounts.removeWhere((key, _) => key.startsWith('$host|'));
    await _db.deleteSiteSettings(host);
    await _db.deleteSiteState(host);
  }

  // ==================== 站点派生状态 ====================

  Future<String?> getSiteState(String host, String kind) =>
      _db.getSiteStateRaw(host, kind);

  Future<void> setSiteState(String host, String kind, String json) =>
      _db.setSiteStateRaw(host, kind, json);

  Future<void> deleteSiteState(String host, {String? kind}) =>
      _db.deleteSiteState(host, kind: kind);

  // ==================== CDN ====================

  String? cdnFor(String host) {
    final value = site(host).cdn?.value ?? '';
    return value.isEmpty ? null : value;
  }

  int? cdnCheckedAt(String host) => site(host).cdn?.checkedAtMs;

  Future<void> setCdn(String host, String value) async {
    await updateSite(
      host,
      (s) => s.copyWith(
        cdn: SiteCdnRecord(
          value: value,
          checkedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Future<void> markCdnChecked(String host) async {
    await updateSite(
      host,
      (s) => s.copyWith(
        cdn: SiteCdnRecord(
          value: s.cdn?.value ?? '',
          checkedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  // ==================== 账号设置（预留） ====================

  Future<AccountSettings> loadAccount(String host, String uid) async {
    try {
      final raw = await _db.getAccountSettingsRaw(host, uid);
      if (raw != null && raw.isNotEmpty) {
        _accounts['$host|$uid'] = AccountSettings.fromMap(
          host,
          uid,
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      }
    } catch (e) {
      AppLogger.w('SETTINGS', 'load account settings $host/$uid failed: $e');
    }
    return account(host, uid);
  }

  Future<void> saveAccount(String host, String uid) async {
    final value = account(host, uid);
    await _db.setAccountSettingsRaw(host, uid, jsonEncode(value.toMap()));
  }

  /// 测试用：直接写入内存中的站点设置（不落盘）
  @visibleForTesting
  void debugSetSite(SiteSettings settings) {
    _sites[settings.host] = settings;
  }
}

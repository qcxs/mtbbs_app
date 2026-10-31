import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/settings/settings_repository.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 设置与账号 Cookie 的导入导出（不含任何缓存）。
///
/// 两类文件格式独立：
/// - `mtbbs.settings`：应用设置 + 各站点设置
/// - `mtbbs.cookies`：各站点账号列表 + 游客/账号 Cookie
class DataPortability {
  DataPortability._();

  static const String settingsFormat = 'mtbbs.settings';
  static const String cookiesFormat = 'mtbbs.cookies';
  static const int formatVersion = 1;

  static final JsonEncoder _pretty = const JsonEncoder.withIndent('  ');

  // ==================== 设置 ====================

  static Future<String> exportSettingsJson() async {
    final repo = SettingsRepository.instance;
    final db = DatabaseHelper.instance;
    final sites = <String, dynamic>{};
    for (final site in SiteStore.instance.sites) {
      final raw = await db.getSiteSettingsRaw(site.host);
      if (raw != null && raw.isNotEmpty) {
        try {
          sites[site.host] = jsonDecode(raw);
          continue;
        } catch (_) {}
      }
      sites[site.host] = repo.site(site.host).toMap();
    }
    return _pretty.convert({
      'format': settingsFormat,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': repo.app.toMap(),
      'sites': sites,
    });
  }

  /// 导入设置文档；返回站点设置数量。
  static Future<int> importSettingsJson(String text) async {
    final doc = _decodeDoc(text, settingsFormat);
    final db = DatabaseHelper.instance;
    final app = doc['app'];
    if (app is Map) {
      await db.setAppSettingsRaw(jsonEncode(app));
    }
    final sites = doc['sites'];
    var count = 0;
    if (sites is Map) {
      for (final entry in sites.entries) {
        final host = entry.key.toString();
        final value = entry.value;
        if (host.isEmpty || value is! Map) continue;
        await db.setSiteSettingsRaw(host, jsonEncode(value));
        count++;
      }
    }
    return count;
  }

  // ==================== 账号 Cookie ====================

  static Future<String> exportCookiesJson() async {
    final sites = <Map<String, dynamic>>[];
    for (final site in SiteStore.instance.sites) {
      final accounts = await _readAccounts(site.host);
      final cookies = <String, List<Map<String, dynamic>>>{};
      cookies[''] = await _readJar(
        host: site.host,
        baseUrl: site.baseUrl,
        account: null,
      );
      for (final account in accounts) {
        final username = account['username']?.toString() ?? '';
        final uid = account['uid']?.toString() ?? '';
        if (username.isEmpty || uid.isEmpty || uid == '0') continue;
        cookies[username] = await _readJar(
          host: site.host,
          baseUrl: site.baseUrl,
          account: username,
        );
      }
      sites.add({
        'host': site.host,
        'baseUrl': site.baseUrl,
        'accounts': accounts,
        'cookies': cookies,
      });
    }
    return _pretty.convert({
      'format': cookiesFormat,
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'sites': sites,
    });
  }

  /// 导入账号 Cookie；返回涉及站点与写入数量。
  static Future<({Set<String> hosts, int accounts, int jars})>
  importCookiesJson(String text) async {
    final doc = _decodeDoc(text, cookiesFormat);
    final rawSites = doc['sites'];
    final hosts = <String>{};
    var accountCount = 0;
    var jarCount = 0;
    if (rawSites is! List) {
      return (hosts: hosts, accounts: 0, jars: 0);
    }
    for (final rawSite in rawSites) {
      if (rawSite is! Map) continue;
      final site = rawSite.cast<String, dynamic>();
      final host = site['host']?.toString() ?? '';
      if (host.isEmpty) continue;
      var baseUrl = site['baseUrl']?.toString() ?? '';
      if (baseUrl.isEmpty) {
        for (final s in SiteStore.instance.sites) {
          if (s.host == host) {
            baseUrl = s.baseUrl;
            break;
          }
        }
      }
      if (baseUrl.isEmpty) baseUrl = 'https://$host';

      final accounts = site['accounts'];
      if (accounts is List) {
        accountCount += await _mergeAccounts(host, accounts);
      }

      final cookies = site['cookies'];
      if (cookies is Map) {
        for (final entry in cookies.entries) {
          final account = entry.key.toString();
          final list = entry.value;
          if (list is! List) continue;
          final jar = await _jarFor(host, account.isEmpty ? null : account);
          await jar.deleteAll();
          final parsed = <Cookie>[];
          for (final item in list) {
            if (item is! Map) continue;
            final cookie = _cookieFromMap(item.cast<String, dynamic>());
            if (cookie != null) parsed.add(cookie);
          }
          if (parsed.isNotEmpty) {
            await jar.saveFromResponse(Uri.parse(_rootUrl(baseUrl)), parsed);
          }
          jarCount++;
        }
      }
      ApiService().dropScopedForHost(host);
      hosts.add(host);
    }
    return (hosts: hosts, accounts: accountCount, jars: jarCount);
  }

  // ==================== 内部 ====================

  static Map<String, dynamic> _decodeDoc(String text, String expectedFormat) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('不是有效的 JSON 对象');
    final doc = decoded.cast<String, dynamic>();
    if (doc['format']?.toString() != expectedFormat) {
      throw FormatException(
        '不是 MTBBS ${expectedFormat == settingsFormat ? '设置' : '账号 Cookie'}文件',
      );
    }
    final version = (doc['version'] as num?)?.toInt() ?? 0;
    if (version <= 0 || version > formatVersion) {
      throw FormatException('不支持的文件版本：$version');
    }
    return doc;
  }

  static Future<List<Map<String, dynamic>>> _readAccounts(String host) async {
    final raw = await DatabaseHelper.instance.getAccountsRaw(host);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (e) {
      AppLogger.w('PORTABILITY', '读取 $host 账号失败: $e');
      return const [];
    }
  }

  /// 合并账号列表（按 uid 去重，后导入字段覆盖旧字段）；返回新增数量。
  static Future<int> _mergeAccounts(String host, List<dynamic> incoming) async {
    final current = await _readAccounts(host);
    final merged = List<Map<String, dynamic>>.from(current);
    var added = 0;
    for (final item in incoming) {
      if (item is! Map) continue;
      final account = item.cast<String, dynamic>();
      final uid = account['uid']?.toString() ?? '';
      final username = account['username']?.toString() ?? '';
      if (uid.isEmpty && username.isEmpty) continue;
      final idx = merged.indexWhere(
        (e) => uid.isNotEmpty
            ? e['uid']?.toString() == uid
            : e['username']?.toString() == username,
      );
      if (idx >= 0) {
        merged[idx] = {...merged[idx], ...account};
      } else {
        merged.add(account);
        added++;
      }
    }
    await DatabaseHelper.instance.setAccountsRaw(host, jsonEncode(merged));
    return added;
  }

  static Future<PersistCookieJar> _jarFor(String host, String? account) async {
    final dir = account == null
        ? await AppPaths.cookiesDirForHost(host)
        : await AppPaths.cookiesDirForAccount(host, account);
    return PersistCookieJar(storage: FileStorage(dir), ignoreExpires: true);
  }

  static Future<List<Map<String, dynamic>>> _readJar({
    required String host,
    required String baseUrl,
    required String? account,
  }) async {
    try {
      final jar = await _jarFor(host, account);
      final root = _rootUrl(baseUrl);
      final byKey = <String, Cookie>{};
      for (final uri in {Uri.parse(root), Uri.parse('${root}forum.php')}) {
        for (final cookie in await jar.loadForRequest(uri)) {
          byKey['${cookie.domain}|${cookie.path}|${cookie.name}'] = cookie;
        }
      }
      return byKey.values.map(_cookieToMap).toList();
    } catch (e) {
      AppLogger.w(
        'PORTABILITY',
        '读取 $host/${account ?? 'guest'} Cookie 失败: $e',
      );
      return const [];
    }
  }

  static String _rootUrl(String baseUrl) =>
      baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';

  static Map<String, dynamic> _cookieToMap(Cookie cookie) => {
    'name': cookie.name,
    'value': cookie.value,
    if (cookie.domain != null && cookie.domain!.isNotEmpty)
      'domain': cookie.domain,
    if (cookie.path != null && cookie.path!.isNotEmpty) 'path': cookie.path,
    if (cookie.expires != null)
      'expires': cookie.expires!.toUtc().toIso8601String(),
    if (cookie.maxAge != null) 'maxAge': cookie.maxAge,
    'httpOnly': cookie.httpOnly,
    'secure': cookie.secure,
  };

  static Cookie? _cookieFromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString() ?? '';
    final value = map['value']?.toString() ?? '';
    if (name.isEmpty) return null;
    try {
      final cookie = Cookie(name, value);
      final domain = map['domain']?.toString() ?? '';
      if (domain.isNotEmpty) cookie.domain = domain;
      final path = map['path']?.toString() ?? '';
      if (path.isNotEmpty) cookie.path = path;
      final expires = DateTime.tryParse(map['expires']?.toString() ?? '');
      if (expires != null) cookie.expires = expires;
      final maxAge = (map['maxAge'] as num?)?.toInt();
      if (maxAge != null) cookie.maxAge = maxAge;
      cookie.httpOnly = map['httpOnly'] == true;
      cookie.secure = map['secure'] == true;
      return cookie;
    } catch (_) {
      return null;
    }
  }
}

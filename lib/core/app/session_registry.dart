import 'dart:convert';

import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_session.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';

/// 站点 / 账号会话注册表 —— 跨站点打开页面的**身份来源**。
///
/// 背景：此前 ApiService 单例把 baseUrl + CookieJar 绑死在"全局当前站点"，
/// 于是别的站点链接只能提示"请切换站点"。现在把身份从单例里解耦：
///
/// - [GlobalSiteSession]：全局当前站点 + 当前账号（行为不变）；
/// - [FixedSiteSession]：某站点的默认账号（未设置 → 游客），供跨站点页面临时使用。
///
/// 默认账号持久化在主库 settings 的 `defaultAccount_{host}`；
/// 账号数据直接读 `_accountsStore`（不依赖 AuthProvider，避免循环依赖）。
///
/// 只在启动时和"账号/站点变化"时刷新内存缓存，页面读取是同步的。
class SessionRegistry {
  SessionRegistry._();
  static final SessionRegistry instance = SessionRegistry._();

  final Map<String, _HostInfo> _hosts = {};
  final Map<String, FixedSiteSession> _sessions = {};

  /// 绑定主会话身份读取器（`AuthProvider`），由 main 在恢复登录态后调用
  void bindIdentity(SiteIdentity Function() reader) {
    SessionRegistryIdentity.bind(reader);
  }

  // ==================== 初始化 / 刷新 ====================

  /// 启动时预加载所有已配置站点的账号 + 默认账号，并建好作用域 Dio。
  ///
  /// 页面读取（[resolve]）是同步的，所以必须提前把异步的磁盘读取做完。
  Future<void> init() async {
    for (final site in SiteStore.instance.sites) {
      await refreshHost(site.host, baseUrl: site.baseUrl);
    }
  }

  /// 站点列表变化后重新加载（新增/删除/改域名）
  Future<void> reloadAll() async {
    _sessions.clear();
    _hosts.clear();
    await init();
  }

  /// 重新读取某站点的账号与默认账号，并重建它的作用域 Dio。
  Future<void> refreshHost(String host, {String? baseUrl}) async {
    final site = _siteForHost(host);
    final resolvedBase = baseUrl ?? site?.baseUrl;
    if (resolvedBase == null || resolvedBase.isEmpty) {
      _hosts.remove(host);
      _dropSessions(host);
      return;
    }
    final db = DatabaseHelper.instance;
    final accounts = _parseAccounts(await db.getAccountsRaw(host));
    final defaultAccount = await _readDefaultAccount(host);

    ApiService().dropScopedForHost(host);
    _dropSessions(host);
    _hosts[host] = _HostInfo(
      baseUrl: resolvedBase,
      accounts: accounts,
      defaultAccount: defaultAccount,
    );

    // 当前站点用全局 Dio（`GlobalSiteSession`），不建作用域会话：它的罐目录
    // 与全局活跃罐完全相同，两个 `PersistCookieJar` 实例指向同一份文件时会
    // 用各自的内存副本互相覆盖 —— 人机验证 cookie 被写回旧值，表现为
    // "验证过了还是被拦"（见 docs/27）。
    if (host == SiteStore.instance.host) return;

    try {
      await _buildSession(
        host,
        resolvedBase,
        account: null,
        uid: '0',
        username: '',
      );
      for (final a in accounts) {
        await _buildSession(
          host,
          resolvedBase,
          account: a.username,
          uid: a.uid,
          username: a.username,
        );
      }
    } catch (e) {
      AppLogger.w('SESSION', '构建 $host 作用域会话失败: $e');
    }
  }

  /// 账号登录态变化（登录 / 退出 / 切换）后调用：只重建该站点的罐。
  Future<void> onAccountsChanged(String host) async {
    try {
      await refreshHost(host);
    } catch (e) {
      AppLogger.w('SESSION', '刷新 $host 账号会话失败: $e');
    }
  }

  Future<FixedSiteSession> _buildSession(
    String host,
    String baseUrl, {
    required String? account,
    required String uid,
    required String username,
  }) async {
    final dio = await ApiService().scopedDio(
      host: host,
      baseUrl: baseUrl,
      account: account,
    );
    final session = FixedSiteSession(
      host: host,
      baseUrl: baseUrl,
      accountName: account,
      uid: uid,
      username: username,
      dio: dio,
    );
    _sessions['$host|${account ?? ''}'] = session;
    return session;
  }

  void _dropSessions(String host) {
    _sessions.removeWhere((k, _) => k.startsWith('$host|'));
  }

  // ==================== 页面读取（同步） ====================

  /// 解析页面需要的会话：没有任何 `site` 参数时返回 null（调用方用全局会话）。
  SiteSession? sessionForLocation(Uri uri) {
    final site = uri.queryParameters['site'];
    if (site == null || site.isEmpty) return null;
    if (site == SiteStore.instance.host) return null;
    return resolve(site, account: uri.queryParameters['as']);
  }

  /// 解析指定站点（可选指定账号）的临时会话。
  ///
  /// 顺序：显式账号 → 站点默认账号 → 游客。已过期/不存在的账号自动跳过。
  SiteSession? resolve(String host, {String? account}) {
    final info = _hosts[host];
    if (info == null) return null;
    final chosen = _pickAccount(info, account);
    return _sessions['$host|${chosen?.username ?? ''}'] ??
        _sessions['$host|'];
  }

  /// 站点 baseUrl（跨站页面拼 URL 用；未配置返回 null）
  String? baseUrlForHost(String host) {
    if (host == SiteStore.instance.host) return SiteStore.instance.baseUrl;
    return _hosts[host]?.baseUrl;
  }

  /// 站点显示名（未配置返回 host）
  String siteNameForHost(String host) {
    for (final site in SiteStore.instance.sites) {
      if (site.host == host) return site.name;
    }
    return host;
  }

  /// 按 host 反查站点配置（未配置返回 null）
  Site? siteForHost(String host) => _siteForHost(host);

  /// 某站点的默认账号（null = 游客 / 未设置）
  String? defaultAccountFor(String host) {
    final info = _hosts[host];
    if (info == null) return null;
    final chosen = _pickAccount(info, null);
    return chosen?.username;
  }

  /// 某站点可供"默认用户"选择的真实账号（已过期的不列出）
  List<String> accountNamesFor(String host) {
    final info = _hosts[host];
    if (info == null) return const [];
    return info.accounts.map((a) => a.username).toList(growable: false);
  }

  /// 某站点的账号明细（用户名 + uid），供「用户设置」页展示
  List<SiteAccount> accountsFor(String host) {
    final info = _hosts[host];
    if (info == null) return const [];
    return info.accounts
        .map((a) => SiteAccount(username: a.username, uid: a.uid))
        .toList(growable: false);
  }

  /// 设置某站点的默认账号（null / 空串 = 游客）
  Future<void> setDefaultAccount(String host, String? username) async {
    final db = DatabaseHelper.instance;
    final key = 'defaultAccount_$host';
    final name = username?.trim() ?? '';
    if (name.isEmpty) {
      await db.deleteMeta(key);
    } else {
      await db.setMeta(key, name);
    }
    await refreshHost(host);
  }

  /// 图片 Referer：按图片 URL 的 host 反查所属站点。
  ///
  /// 跨站点帖子里引用本站附件时，Referer 必须是目标站点，否则防盗链会拒绝。
  String refererForUrl(String url) {
    final uri = Uri.tryParse(url);
    final imageHost = uri?.host ?? '';
    if (imageHost.isEmpty) return SiteStore.instance.baseUrl;
    for (final site in SiteStore.instance.sites) {
      final siteHost = Uri.tryParse(site.baseUrl)?.host;
      if (siteHost != null && siteHost == imageHost) {
        return site.baseUrl;
      }
    }
    return SiteStore.instance.baseUrl;
  }

  // ==================== 内部 ====================

  Site? _siteForHost(String host) {
    for (final site in SiteStore.instance.sites) {
      if (site.host == host) return site;
    }
    return null;
  }

  _AccountInfo? _pickAccount(_HostInfo info, String? account) {
    if (account != null && account.isNotEmpty) {
      for (final a in info.accounts) {
        if (a.username == account) return a;
      }
    }
    final def = info.defaultAccount;
    if (def != null && def.isNotEmpty) {
      for (final a in info.accounts) {
        if (a.username == def) return a;
      }
    }
    return null;
  }

  List<_AccountInfo> _parseAccounts(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final result = <_AccountInfo>[];
      for (final item in list) {
        if (item is! Map) continue;
        final uid = item['uid']?.toString() ?? '';
        final username = item['username']?.toString() ?? '';
        final expired = item['expired'] == true;
        // 游客与过期账号不能作为默认身份
        if (uid.isEmpty || uid == '0' || username.isEmpty || expired) continue;
        result.add(_AccountInfo(username: username, uid: uid));
      }
      return result;
    } catch (e) {
      AppLogger.w('SESSION', '解析账号列表失败: $e');
      return const [];
    }
  }

  Future<String?> _readDefaultAccount(String host) async {
    final v = await DatabaseHelper.instance.getMeta('defaultAccount_$host');
    final name = v?.trim() ?? '';
    return name.isEmpty ? null : name;
  }
}

/// 站点账号（供「用户设置」页展示的最小信息）
class SiteAccount {
  final String username;
  final String uid;

  const SiteAccount({required this.username, required this.uid});
}

class _HostInfo {
  final String baseUrl;
  final List<_AccountInfo> accounts;
  final String? defaultAccount;

  const _HostInfo({
    required this.baseUrl,
    required this.accounts,
    required this.defaultAccount,
  });
}

class _AccountInfo {
  final String username;
  final String uid;

  const _AccountInfo({required this.username, required this.uid});
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/database_helper.dart';
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;

/// 账号模型
class Account {
  String username;
  String uid;
  String avatarUrl;
  String credits;
  String userGroup;
  String cookieString;

  // 个人资料扩展
  String nickname;
  String signature;
  String customTitle;
  bool online;
  bool emailVerified;
  String spaceUrl;
  int friends;
  int replies;
  int threads;
  String adminGroup;
  String onlineTime;
  String registerTime;
  String lastVisit;
  int reputation;
  int goldCoins;
  int credit;

  /// 登录是否已过期（服务器返回未登录但保留账号数据，供重新登录合并）
  bool expired;

  Account({
    required this.username,
    this.uid = '',
    this.expired = false,
    this.avatarUrl = '',
    this.credits = '',
    this.userGroup = '',
    this.cookieString = '',
    this.nickname = '',
    this.signature = '',
    this.customTitle = '',
    this.online = false,
    this.emailVerified = false,
    this.spaceUrl = '',
    this.friends = 0,
    this.replies = 0,
    this.threads = 0,
    this.adminGroup = '',
    this.onlineTime = '',
    this.registerTime = '',
    this.lastVisit = '',
    this.reputation = 0,
    this.goldCoins = 0,
    this.credit = 0,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'uid': uid,
    'expired': expired,
    'avatarUrl': avatarUrl,
    'credits': credits,
    'userGroup': userGroup,
    'cookieString': cookieString,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    username: json['username']?.toString() ?? '',
    uid: json['uid']?.toString() ?? '',
    expired: json['expired'] == true,
    avatarUrl: json['avatarUrl']?.toString() ?? '',
    credits: json['credits']?.toString() ?? '',
    userGroup: json['userGroup']?.toString() ?? '',
    cookieString: json['cookieString']?.toString() ?? '',
  );
}

/// 登录状态管理 — 按站点隔离
///
/// 每个站点的账号列表独立存储、独立活跃索引。
/// 切换站点时自动切换账号上下文。
class AuthProvider extends ChangeNotifier {
  /// 按站点 host 分组的账号列表
  final Map<String, List<Account>> _siteAccounts = {};

  /// 按站点 host 记录的活跃索引
  final Map<String, int> _siteActiveIndex = {};

  bool _guestInitialized = false;

  // ==================== 当前站点快捷访问 ====================

  String get _host => SiteStore.instance.host;

  List<Account> get _currentAccounts =>
      _siteAccounts.putIfAbsent(_host, () => []);

  int get _currentActiveIndex {
    _siteActiveIndex.putIfAbsent(_host, () => -1);
    return _siteActiveIndex[_host]!;
  }

  set _currentActiveIndex(int v) => _siteActiveIndex[_host] = v;

  // ==================== 公开 API ====================

  bool get isLoggedIn =>
      _currentActiveIndex >= 0 &&
      uid != '0' &&
      uid.isNotEmpty &&
      !_currentAccounts[_currentActiveIndex].expired;

  /// 当前活跃账号是否处于登录过期状态
  bool get isExpired =>
      _currentActiveIndex >= 0 && _currentAccounts[_currentActiveIndex].expired;

  String get username => _currentActiveIndex >= 0
      ? _currentAccounts[_currentActiveIndex].username
      : '';

  String get uid =>
      _currentActiveIndex >= 0 ? _currentAccounts[_currentActiveIndex].uid : '';

  String get avatarUrl => _currentActiveIndex >= 0
      ? _currentAccounts[_currentActiveIndex].avatarUrl
      : '';

  String get credits => _currentActiveIndex >= 0
      ? _currentAccounts[_currentActiveIndex].credits
      : '';

  String get userGroup => _currentActiveIndex >= 0
      ? _currentAccounts[_currentActiveIndex].userGroup
      : '';

  /// 当前站点的账号列表（含游客）
  List<Account> get accounts => List.unmodifiable(_currentAccounts);

  int get activeIndex => _currentActiveIndex;

  /// 当前活跃账号的完整 Cookie 字符串（游客返回 null）
  String? get currentCookieString {
    final idx = _currentActiveIndex;
    if (idx < 0 || idx >= _currentAccounts.length) return null;
    final a = _currentAccounts[idx];
    return a.uid == '0' ? null : a.cookieString;
  }

  // ==================== 网页登录 ====================

  Future<bool> saveWebLogin(
    String username,
    String uid,
    String cookieStr,
  ) async {
    if (cookieStr.isEmpty) return false;
    try {
      final name = username.isNotEmpty ? username : uid;
      final saved = await _saveCookieToAccount(name, uid, cookieStr);
      if (saved) await refreshCurrentUserInfo();
      return saved;
    } catch (e) {
      debugPrint('[AuthProvider] saveWebLogin error: $e');
      return false;
    }
  }

  /// 直接输入 Cookie 并验证有效性
  Future<Map<String, dynamic>> validateAndSaveCookie(String cookieStr) async {
    if (cookieStr.isEmpty) {
      return {'success': false, 'message': 'Cookie 不能为空'};
    }
    try {
      final tempDio = Dio(
        BaseOptions(
          baseUrl: SiteStore.instance.baseUrl,
          headers: {'User-Agent': Site.uaAndroid, 'Cookie': cookieStr},
        ),
      );
      final result = await userstatus_api.fetch(tempDio);
      if (result['success'] != true || result['uid'] == '0') {
        return {'success': false, 'message': 'Cookie 无效或已过期'};
      }
      final uid = result['uid']?.toString() ?? '';
      final username = result['username']?.toString() ?? '';
      final name = username.isNotEmpty ? username : '用户$uid';
      await _saveCookieToAccount(name, uid, cookieStr);
      await refreshCurrentUserInfo();
      return {'success': true, 'uid': uid, 'username': name, 'message': '登录成功'};
    } catch (e) {
      return {'success': false, 'message': '验证失败: $e'};
    }
  }

  // ==================== 用户信息刷新 ====================

  /// 刷新当前登录用户的信息
  ///
  /// 调用 userstatus API 获取用户名、uid、用户组、积分。
  /// - 服务器明确返回未登录（uid='0'）→ 标记登录过期（保留账号数据）
  /// - 请求/解析失败（网络错误、反爬挑战拦截等）→ 不视为过期，避免误伤登录态
  Future<void> refreshCurrentUserInfo() async {
    final idx = _currentActiveIndex;
    if (idx < 0 || idx >= _currentAccounts.length) return;
    final account = _currentAccounts[idx];
    if (account.uid == '0') return; // 游客无需刷新

    final result = await _fetchUserStatusWithRetry();

    if (result['success'] == true && result['uid'] != '0') {
      // 更新当前账号信息
      final a = _currentAccounts[_currentActiveIndex];
      a.username = result['username']?.toString() ?? a.username;
      a.userGroup = result['userGroup']?.toString() ?? a.userGroup;
      a.credits = result['credits']?.toString() ?? a.credits;
      final avatar = result['avatarUrl']?.toString() ?? '';
      if (avatar.isNotEmpty) {
        a.avatarUrl = avatar;
      }
      a.expired = false;
      _saveState();
      notifyListeners();
      return;
    }

    // 仅当服务器明确返回未登录时才标记过期；解析失败（如反爬拦截）不标记
    if (result['uid'] == '0' && !account.expired) {
      _currentAccounts[idx].expired = true;
      _saveState();
      notifyListeners();
    }
  }

  /// 获取 userstatus：优先走 Dio CookieJar（普通站点正常路径，Cookie 可被服务器更新）；
  /// jar 失败（如被反爬挑战拦截导致解析异常）时用账号原始 Cookie 串直注重试。
  Future<Map<String, dynamic>> _fetchUserStatusWithRetry() async {
    final result = await _tryFetchUserStatus(ApiService().dio);
    if (result['success'] == true) return result;

    final idx = _currentActiveIndex;
    final cookie = idx >= 0 ? _currentAccounts[idx].cookieString : '';
    if (cookie.isEmpty) return result;
    try {
      final tempDio = Dio(
        BaseOptions(
          baseUrl: SiteStore.instance.baseUrl,
          headers: {'User-Agent': Site.uaPc, 'Cookie': cookie},
        ),
      );
      final retry = await _tryFetchUserStatus(tempDio);
      if (retry['success'] == true) return retry;
    } catch (e) {
      debugPrint('[AuthProvider] userstatus retry error: $e');
    }
    return result;
  }

  Future<Map<String, dynamic>> _tryFetchUserStatus(Dio dio) async {
    try {
      return await userstatus_api.fetch(dio);
    } catch (e) {
      debugPrint('[AuthProvider] userstatus fetch error: $e');
      return {'success': false, 'message': '$e'};
    }
  }

  /// 标记当前账号登录过期（由登录过期事件触发）
  ///
  /// 幂等：仅当存在已登录账号且未标记时处理，并发事件只生效一次。
  void markSessionExpired() {
    final idx = _currentActiveIndex;
    if (idx < 0 || idx >= _currentAccounts.length) return;
    final a = _currentAccounts[idx];
    if (a.uid == '0' || a.expired) return;
    a.expired = true;
    _saveState();
    notifyListeners();
  }

  // ==================== 游客模式 ====================

  Future<void> initGuestCookies() async {
    if (_guestInitialized) return;
    _guestInitialized = true;
  }

  void _ensureGuestAccount() {
    final hasGuest = _currentAccounts.any((a) => a.uid == '0');
    if (!hasGuest) {
      _currentAccounts.add(Account(username: '游客', uid: '0'));
    }
    if (_currentActiveIndex < 0) {
      _currentActiveIndex = 0;
    }
  }

  /// 清理历史遗留的“游客(登录过期)”占位账号
  ///
  /// 旧版本过期逻辑把账号 uid 篡改为 '0' 且保留在列表，污染账号列表；
  /// 这类占位账号已无登录价值，加载/保存账号数据时直接移除。
  void _cleanupLegacyPlaceholders() {
    _currentAccounts.removeWhere(
      (a) => a.uid == '0' && a.username == '游客(登录过期)',
    );
    if (_currentAccounts.isEmpty) {
      _currentActiveIndex = -1;
    } else if (_currentActiveIndex >= _currentAccounts.length) {
      _currentActiveIndex = _currentAccounts.length - 1;
    }
  }

  // ==================== 清除当前站点数据 ====================

  Future<void> clearAllLoginData() async {
    try {
      await ApiService().deleteAllAccountJars();
      _siteAccounts[_host] = [];
      _siteActiveIndex[_host] = -1;
      _guestInitialized = false;
      await ApiService().switchToGuest();
      _ensureGuestAccount();
      await initGuestCookies();
      _saveState();
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] clearAllLoginData error: $e');
    }
  }

  // ==================== 账号导入导出 ====================

  String exportAccounts() {
    final real = _currentAccounts.where((a) => a.uid != '0').toList();
    return jsonEncode(real.map((a) => a.toJson()).toList());
  }

  Map<String, dynamic> importAccounts(String jsonStr) {
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      if (list.isEmpty) return {'success': false, 'message': '列表为空'};
      int added = 0;
      for (final item in list) {
        final account = Account.fromJson(item as Map<String, dynamic>);
        if (account.uid.isEmpty) continue;
        final idx = _currentAccounts.indexWhere((a) => a.uid == account.uid);
        if (idx >= 0) {
          final existing = _currentAccounts[idx];
          existing.avatarUrl = account.avatarUrl;
          existing.credits = account.credits;
          existing.userGroup = account.userGroup;
          if (account.cookieString.isNotEmpty) {
            existing.cookieString = account.cookieString;
          }
          if (existing.username.isEmpty || existing.uid == '0') {
            existing.username = account.username;
            existing.uid = account.uid;
          }
        } else {
          _currentAccounts.add(account);
          added++;
        }
      }
      _saveState();
      notifyListeners();
      return {
        'success': true,
        'message': added > 0 ? '导入了 $added 个新账号' : '没有新增账号',
        'count': added,
      };
    } catch (e) {
      return {'success': false, 'message': '解析失败: $e'};
    }
  }

  // ==================== Cookie 管理 ====================

  Future<bool> _saveCookieToAccount(
    String username,
    String uid,
    String cookieStr,
  ) async {
    if (cookieStr.isEmpty) return false;
    final name = username.isNotEmpty ? username : '用户$uid';

    await ApiService().switchToAccount(name);
    final cookies = _parseCookieString(cookieStr);
    if (cookies.isEmpty) return false;
    final cm =
        ApiService().dio.interceptors.firstWhere((i) => i is CookieManager)
            as CookieManager;
    await cm.cookieJar.saveFromResponse(
      Uri.parse(SiteStore.instance.baseUrl),
      cookies,
    );

    // 优先按 uid 匹配；旧版本过期逻辑曾篡改 uid，按 username 回退合并
    var idx = uid.isNotEmpty
        ? _currentAccounts.indexWhere((a) => a.uid == uid)
        : -1;
    if (idx < 0 && username.isNotEmpty) {
      idx = _currentAccounts.indexWhere(
        (a) => a.uid != '0' && a.username == username,
      );
    }

    if (idx >= 0) {
      _currentAccounts[idx].uid = uid;
      _currentAccounts[idx].username = name;
      _currentAccounts[idx].cookieString = cookieStr;
      _currentAccounts[idx].expired = false;
      _currentActiveIndex = idx;
    } else {
      _currentAccounts.add(
        Account(username: name, uid: uid, cookieString: cookieStr),
      );
      _currentActiveIndex = _currentAccounts.length - 1;
    }

    _cleanupLegacyPlaceholders();
    _saveState();
    _ensureGuestAccount();
    notifyListeners();
    return true;
  }

  Future<void> _restoreCookiesForActive() async {
    if (_currentActiveIndex < 0) return;
    final account = _currentAccounts[_currentActiveIndex];
    await ApiService().switchToAccount(account.username);
    await _restoreCookieString(account.cookieString);
  }

  Future<void> _restoreCookieString(String cookieStr) async {
    if (cookieStr.isEmpty) return;
    try {
      final cookies = _parseCookieString(cookieStr);
      if (cookies.isEmpty) return;
      final cm =
          ApiService().dio.interceptors.firstWhere((i) => i is CookieManager)
              as CookieManager;
      await cm.cookieJar.saveFromResponse(
        Uri.parse(SiteStore.instance.baseUrl),
        cookies,
      );
    } catch (e) {
      debugPrint('[AuthProvider] restoreCookieString error: $e');
    }
  }

  List<Cookie> _parseCookieString(String cookieStr) {
    final cookies = <Cookie>[];
    for (final pair in cookieStr.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      try {
        final c = Cookie(trimmed.substring(0, eq), trimmed.substring(eq + 1));
        c.domain = '.${Uri.parse(SiteStore.instance.baseUrl).host}';
        c.path = '/';
        c.maxAge = 86400 * 30;
        cookies.add(c);
      } catch (_) {
        // 跳过值中包含非法字符（如逗号）的 Cookie
      }
    }
    return cookies;
  }

  // ==================== 初始化与恢复 ====================

  Future<void> tryRestore() async {
    final db = DatabaseHelper.instance;

    // 恢复当前站点的账号列表
    final jsonStr = await db.getAccountsRaw(_host);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _siteAccounts[_host] = list
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    _cleanupLegacyPlaceholders();
    _ensureGuestAccount();

    // 恢复活跃索引
    final lastAccount = await db.getLastAccount(_host);
    if (lastAccount != null && _currentAccounts.isNotEmpty) {
      _currentActiveIndex = _currentAccounts.indexWhere(
        (a) => a.username == lastAccount,
      );
      if (_currentActiveIndex < 0) _currentActiveIndex = 0;
      await _restoreCookiesForActive();
    } else if (_currentAccounts.isNotEmpty) {
      _currentActiveIndex = 0;
      if (_currentAccounts[0].uid != '0') {
        await ApiService().switchToAccount(_currentAccounts[0].username);
        _restoreCookieString(_currentAccounts[0].cookieString);
      }
    }
    notifyListeners();
    initGuestCookies();
  }

  // ==================== 站点切换 ====================

  /// 在切换站点之前调用，保存当前站点的账号状态
  void saveCurrentSiteState() {
    _saveState();
  }

  /// 在外部切换站点后调用，恢复新站点的账号上下文
  Future<void> onSiteChanged() async {
    // 切换到新站点的 guest jar
    await ApiService().switchSite();

    // 恢复新站点的账号数据
    await _restoreSiteAccounts();

    _guestInitialized = false;
    notifyListeners();
    initGuestCookies();
  }

  Future<void> _restoreSiteAccounts() async {
    final db = DatabaseHelper.instance;
    final jsonStr = await db.getAccountsRaw(_host);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _siteAccounts[_host] = list
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
    } else {
      _siteAccounts[_host] = [];
    }
    _cleanupLegacyPlaceholders();
    _ensureGuestAccount();

    final lastAccount = await db.getLastAccount(_host);
    if (lastAccount != null && _currentAccounts.isNotEmpty) {
      _currentActiveIndex = _currentAccounts.indexWhere(
        (a) => a.username == lastAccount,
      );
      if (_currentActiveIndex < 0) _currentActiveIndex = 0;
      await _restoreCookiesForActive();
    } else {
      _currentActiveIndex = 0;
      await ApiService().switchToGuest();
    }
  }

  // ==================== 账号切换 ====================

  Future<void> switchTo(int index) async {
    if (index < 0 || index >= _currentAccounts.length) return;
    _currentActiveIndex = index;
    final account = _currentAccounts[index];
    if (account.uid == '0') {
      await ApiService().switchToGuest();
      await initGuestCookies();
    } else {
      await ApiService().switchToAccount(account.username);
      await _restoreCookieString(account.cookieString);
    }
    _saveActive();
    notifyListeners();
  }

  // ==================== 退出 ====================

  Future<void> logout() async {
    if (_currentActiveIndex < 0) return;
    final account = _currentAccounts[_currentActiveIndex];
    if (account.uid == '0') return;

    await ApiService().deleteAccountJar(account.username);
    _currentAccounts.removeAt(_currentActiveIndex);
    _currentActiveIndex = _currentAccounts.isEmpty ? -1 : 0;

    if (_currentAccounts.isNotEmpty &&
        _currentAccounts[_currentActiveIndex].uid == '0') {
      await ApiService().switchToGuest();
      await initGuestCookies();
    } else if (_currentAccounts.isNotEmpty) {
      await ApiService().switchToAccount(
        _currentAccounts[_currentActiveIndex].username,
      );
    }

    _saveState();
    notifyListeners();
  }

  // ==================== 持久化 ====================

  Future<void> _saveState() async {
    final db = DatabaseHelper.instance;
    await db.setAccountsRaw(
      _host,
      jsonEncode(_currentAccounts.map((a) => a.toJson()).toList()),
    );
    await _saveActive();
  }

  Future<void> _saveActive() async {
    final db = DatabaseHelper.instance;
    if (_currentActiveIndex >= 0) {
      await db.setLastAccount(
        _host,
        _currentAccounts[_currentActiveIndex].username,
      );
    } else {
      await db.deleteLastAccount(_host);
    }
  }
}

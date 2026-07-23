import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../../services/api_service.dart';
import '../../config/site_config.dart';
import '../../core/site_store.dart';
import '../../api/misc/userstatus/export.dart' as userstatus_api;

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

  Account({
    required this.username,
    this.uid = '',
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
    'avatarUrl': avatarUrl,
    'credits': credits,
    'userGroup': userGroup,
    'cookieString': cookieString,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    username: json['username']?.toString() ?? '',
    uid: json['uid']?.toString() ?? '',
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
      _currentActiveIndex >= 0 && uid != '0' && uid.isNotEmpty;

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
  /// 调用 userstatus API 获取用户名、uid、用户组、积分，
  /// 若返回 uid=0 则标记为登出。
  Future<void> refreshCurrentUserInfo() async {
    try {
      final result = await userstatus_api.fetch(ApiService().dio);
      if (result['success'] != true || result['uid'] == '0') {
        // 登录已过期
        if (_currentActiveIndex >= 0 &&
            _currentAccounts[_currentActiveIndex].uid != '0') {
          _currentAccounts[_currentActiveIndex].uid = '0';
          _currentAccounts[_currentActiveIndex].username = '游客(登录过期)';
          _saveState();
          notifyListeners();
        }
        return;
      }

      // 更新当前账号信息
      if (_currentActiveIndex >= 0) {
        final a = _currentAccounts[_currentActiveIndex];
        a.username = result['username']?.toString() ?? a.username;
        a.userGroup = result['userGroup']?.toString() ?? a.userGroup;
        a.credits = result['credits']?.toString() ?? a.credits;
      }
      _saveState();
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthProvider] refreshUserInfo error: $e');
    }
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

    final idx = uid.isNotEmpty
        ? _currentAccounts.indexWhere((a) => a.uid == uid)
        : _currentAccounts.indexWhere((a) => a.username == name);

    if (idx >= 0) {
      _currentAccounts[idx].uid = uid;
      _currentAccounts[idx].cookieString = cookieStr;
      _currentActiveIndex = idx;
    } else {
      _currentAccounts.add(
        Account(username: name, uid: uid, cookieString: cookieStr),
      );
      _currentActiveIndex = _currentAccounts.length - 1;
    }

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
    for (final pair in cookieStr.split('; ')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final c = Cookie(pair.substring(0, eq), pair.substring(eq + 1));
      c.domain = '.${Uri.parse(SiteStore.instance.baseUrl).host}';
      c.path = '/';
      c.maxAge = 86400 * 30;
      cookies.add(c);
    }
    return cookies;
  }

  // ==================== 初始化与恢复 ====================

  Future<void> tryRestore() async {
    final prefs = await SharedPreferences.getInstance();

    // 恢复当前站点的账号列表
    final jsonStr = prefs.getString('accounts_$_host');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _siteAccounts[_host] = list
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    _ensureGuestAccount();

    // 恢复活跃索引
    final lastAccount = prefs.getString('last_account_$_host');
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
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('accounts_$_host');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      _siteAccounts[_host] = list
          .map((j) => Account.fromJson(j as Map<String, dynamic>))
          .toList();
    } else {
      _siteAccounts[_host] = [];
    }
    _ensureGuestAccount();

    final lastAccount = prefs.getString('last_account_$_host');
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

  void _saveState() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
        'accounts_$_host',
        jsonEncode(_currentAccounts.map((a) => a.toJson()).toList()),
      );
      _saveActive();
    });
  }

  void _saveActive() {
    SharedPreferences.getInstance().then((prefs) {
      if (_currentActiveIndex >= 0) {
        prefs.setString(
          'last_account_$_host',
          _currentAccounts[_currentActiveIndex].username,
        );
      } else {
        prefs.remove('last_account_$_host');
      }
    });
  }
}

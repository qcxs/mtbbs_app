part of 'auth_provider.dart';

/// [AuthProvider] 的站点切换逻辑
extension AuthSite on AuthProvider {
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
    _notify();
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
}

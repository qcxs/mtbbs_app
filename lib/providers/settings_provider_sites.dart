part of 'settings_provider.dart';

/// [SettingsProvider] 的站点 / 版块 / 站点切换与积分公式相关写操作
extension SettingsSites on SettingsProvider {
  // ==================== 站点管理 ====================

  Future<void> addSite(Site site) async {
    _sites.add(site);
    await _persistSites();
  }

  Future<void> deleteSite(int index) async {
    if (index < 0 || index >= _sites.length) return;
    _sites.removeAt(index);
    if (_currentSiteIndex >= _sites.length) {
      _currentSiteIndex = _sites.length - 1;
    }
    await _persistSites();
  }

  Future<void> updateSite(int index, Site site) async {
    if (index < 0 || index >= _sites.length) return;
    _sites[index] = site;
    if (index == _currentSiteIndex) {
      final idx = SiteStore.instance.sites.indexWhere(
        (s) => s.host == site.host,
      );
      if (idx >= 0) SiteStore.instance.switchTo(idx);
    }
    await _persistSites();
    _notify();
  }

  Future<void> setSiteUA(String userAgent) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    _sites[idx] = old.copyWith(userAgent: userAgent);
    SiteStore.instance.switchTo(idx);
    await _persistSites();
    _notify();
  }

  /// 设置当前站点的头像 URL 模板，空字符串恢复默认 API 方案
  Future<void> setSiteAvatarTemplate(String template) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final t = template.trim();
    _sites[idx] = _sites[idx].copyWith(
      avatarTemplate: t,
      clearAvatarTemplate: t.isEmpty,
    );
    SiteStore.instance.switchTo(idx);
    await _persistSites();
    _notify();
  }

  Future<void> replaceSites(List<Site> newSites) async {
    _sites = List.from(newSites);
    await _persistSites();
  }

  /// 从默认配置（sites.json）同步站点列表。
  ///
  /// - 已存在（按 [Site.baseUrl] 匹配）的站点：覆盖为默认配置，保留 forums / defaultForumOrder
  /// - 缺失的内置站点：追加到列表末尾（例如应用更新后新增的默认站点）
  /// - 自定义添加的站点：不受影响
  /// 返回发生变化的站点数量。
  Future<int> restoreDefaultSites() async {
    final defaults = SiteConfig.defaultSites();
    if (defaults.isEmpty) return 0;
    var count = 0;
    // 覆盖已存在的内置站点
    for (var i = 0; i < _sites.length; i++) {
      final current = _sites[i];
      Site? def;
      for (final d in defaults) {
        if (d.baseUrl == current.baseUrl) {
          def = d;
          break;
        }
      }
      if (def == null) continue;
      _sites[i] = current.copyWith(
        name: def.name,
        cdn: def.cdn,
        loginPagePath: def.loginPagePath,
        userAgent: def.userAgent,
        avatarTemplate: def.avatarTemplate,
        clearAvatarTemplate: def.avatarTemplate == null,
      );
      count++;
    }
    // 追加缺失的内置站点
    final existing = _sites.map((s) => s.baseUrl).toSet();
    for (final d in defaults) {
      if (existing.contains(d.baseUrl)) continue;
      _sites.add(
        Site(
          name: d.name,
          baseUrl: d.baseUrl,
          cdn: d.cdn,
          loginPagePath: d.loginPagePath,
          forums: {},
          defaultForumOrder: [],
          userAgent: d.userAgent,
          avatarTemplate: d.avatarTemplate,
        ),
      );
      count++;
    }
    await _persistSites();
    _notify();
    return count;
  }

  // ==================== 版块管理 ====================

  Future<void> addForum(String fid, String name) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..[fid] = name;
    final newOrder = List<String>.from(old.defaultForumOrder)..add(fid);
    _sites[idx] = old.copyWith(forums: newForums, defaultForumOrder: newOrder);
    await _persistSites();
  }

  Future<void> removeForum(String fid) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..remove(fid);
    final newOrder = List<String>.from(old.defaultForumOrder)..remove(fid);
    _sites[idx] = old.copyWith(forums: newForums, defaultForumOrder: newOrder);
    await _persistSites();
    _notify();
  }

  Future<void> moveForum(int oldIndex, int newIndex) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final order = List<String>.from(_sites[idx].defaultForumOrder);
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex < 0 || newIndex >= order.length) return;
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    _sites[idx] = _sites[idx].copyWith(defaultForumOrder: order);
    await _persistSites();
    _notify();
  }

  Future<void> renameForum(String fid, String newName) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..[fid] = newName;
    _sites[idx] = old.copyWith(
      forums: newForums,
      defaultForumOrder: List.from(old.defaultForumOrder),
    );
    await _persistSites();
  }

  Future<void> replaceForums(Map<String, String> newForums) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newOrder = old.defaultForumOrder
        .where((fid) => newForums.containsKey(fid))
        .toList();
    for (final fid in newForums.keys) {
      if (!newOrder.contains(fid)) newOrder.add(fid);
    }
    _sites[idx] = old.copyWith(
      forums: Map.from(newForums),
      defaultForumOrder: newOrder,
    );
    await _persistSites();
  }

  Future<void> _persistSites() async {
    SiteStore.instance.replaceSites(_sites);
    SiteStore.instance.switchTo(_currentSiteIndex.clamp(0, _sites.length - 1));
    await _db.setSitesRaw(jsonEncode(_sites.map((s) => s.toJson()).toList()));
    _notify();
  }

  // ==================== 站点切换 ====================

  Future<void> switchSite(int index) async {
    if (index == _currentSiteIndex) return;
    _currentSiteIndex = index;
    await _db.setSettingInt('currentSiteIndex', index);
    _notify();
  }

  Future<void> reloadSiteConfig() async {
    _creditFormula = await _loadFormulaForHost(SiteStore.instance.host);
    _notify();
  }

  Future<void> setCreditFormula(String formula) async {
    _creditFormula = formula;
    await _db.setCreditFormula(SiteStore.instance.host, formula);
    _notify();
  }

  Future<String> _loadFormulaForHost(String host) async {
    return (await _db.getCreditFormula(host)) ??
        SettingsProvider.defaultFormula;
  }

  Future<String?> fetchAndUpdateFormula() async {
    try {
      final result = await credit_api.fetch(ApiService().dio);
      if (result['success'] == true && result['formula'] != null) {
        _creditFormula = result['formula'] as String;
        await _db.setCreditFormula(SiteStore.instance.host, _creditFormula);
        _notify();
        return _creditFormula;
      }
      return null;
    } catch (e) {
      AppLogger.w('SETTINGS', 'fetch formula error: $e');
      return null;
    }
  }
}

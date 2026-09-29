part of 'settings_provider.dart';

/// [SettingsProvider] 中可排序 / 可显隐配置项的写操作
/// （编辑器工具栏、快捷链接、导读 Tab、首页区块）
extension SettingsManagedLists on SettingsProvider {
  // ==================== 工具栏 ====================

  Future<List<ManagedItem>> _loadSyncedToolbar() async {
    final canonical = defaultToolbarItems();
    final canonicalIds = canonical.map((e) => e.id).toSet();

    final jsonStr = await _db.getToolbarItemsRaw();
    if (jsonStr == null || jsonStr.isEmpty) return canonical;

    try {
      final loaded = ManagedItem.decodeList(jsonStr);
      final loadedIds = loaded.map((e) => e.id).toSet();

      final synced = loaded.where((e) => canonicalIds.contains(e.id)).map((e) {
        final canonicalItem = canonical.firstWhere((c) => c.id == e.id);
        return e.copyWith(name: canonicalItem.name);
      }).toList();

      for (final item in canonical) {
        if (!loadedIds.contains(item.id)) {
          synced.add(item);
        }
      }
      return synced;
    } catch (_) {
      return canonical;
    }
  }

  Future<void> _persistToolbar() async {
    await _db.setToolbarItemsRaw(ManagedItem.encodeList(_toolbarItems));
    _notify();
  }

  Future<void> moveToolbarItem(int from, int to) async {
    reorderManagedItems(_toolbarItems, from, to);
    await _persistToolbar();
  }

  Future<void> toggleToolbarItem(String id) async {
    toggleManagedItem(_toolbarItems, id);
    await _persistToolbar();
  }

  Future<void> resetToolbarItems() async {
    _toolbarItems = defaultToolbarItems();
    _toolbarShortcuts = defaultToolbarShortcuts();
    await _db.setToolbarItemsRaw(ManagedItem.encodeList(_toolbarItems));
    await _db.setToolbarShortcutsRaw(jsonEncode(_toolbarShortcuts));
    _notify();
  }

  // ==================== 快捷链接 CRUD ====================

  List<ManagedItem> _linksForCurrent() =>
      _shortcutLinks.putIfAbsent(SiteStore.instance.host, () => []);

  Future<void> _persistLinks() async {
    await _db.setShortcutLinksRaw(
      SiteStore.instance.host,
      ManagedItem.encodeList(_linksForCurrent()),
    );
    _notify();
  }

  Future<void> addShortcutLink(ManagedItem item) async {
    _linksForCurrent().add(item);
    await _persistLinks();
  }

  Future<void> removeShortcutLink(String id) async {
    _linksForCurrent().removeWhere((e) => e.id == id);
    await _persistLinks();
  }

  Future<void> updateShortcutLink(String id, ManagedItem newValue) async {
    final idx = _linksForCurrent().indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _linksForCurrent()[idx] = newValue;
    await _persistLinks();
  }

  Future<void> moveShortcutLink(int from, int to) async {
    reorderManagedItems(_linksForCurrent(), from, to);
    await _persistLinks();
  }

  Future<void> toggleShortcutLink(String id) async {
    toggleManagedItem(_linksForCurrent(), id);
    await _persistLinks();
  }

  // ==================== 导读 Tab ====================

  Future<void> moveTab(int from, int to) async {
    reorderManagedItems(_guideTabs, from, to);
    await _persistGuideTabs();
  }

  Future<void> toggleTab(String id) async {
    toggleManagedItem(_guideTabs, id);
    await _persistGuideTabs();
  }

  Future<void> _persistGuideTabs() async {
    await _db.setSetting('guideTabs', ManagedItem.encodeList(_guideTabs));
    _notify();
  }

  // ==================== 首页区块 ====================

  Future<void> moveHomeSection(int from, int to) async {
    reorderManagedItems(_homeSections, from, to);
    await _persistHomeSections();
  }

  Future<void> toggleHomeSectionVisibility(String id) async {
    toggleManagedItem(_homeSections, id);
    await _persistHomeSections();
  }

  /// 设置区块展开状态。
  ///
  /// 首页里当场折叠与设置面板里改默认值走同一入口，因此用户折叠过的
  /// 区块下次启动仍是折叠的，不需要两套状态。
  Future<void> setHomeSectionExpanded(String id, bool expanded) async {
    final i = _homeSections.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final data = Map<String, dynamic>.from(_homeSections[i].data ?? {});
    data['expanded'] = expanded;
    _homeSections[i] = _homeSections[i].copyWith(data: data);
    await _persistHomeSections();
  }

  Future<void> _persistHomeSections() async {
    await _db.setSetting('homeSections', ManagedItem.encodeList(_homeSections));
    _notify();
  }
}

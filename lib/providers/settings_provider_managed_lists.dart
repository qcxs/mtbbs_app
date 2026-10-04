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

      final synced = <ManagedItem>[];
      for (final e in loaded) {
        if (canonicalIds.contains(e.id)) {
          final canonicalItem = canonical.firstWhere((c) => c.id == e.id);
          // 内置项：以 JSON 的模板/标签/分组为默认值（兼容旧版无 data 的持久化），
          // 用持久化里的同名字段覆盖（用户改过的模板得以保留）
          final merged = <String, dynamic>{
            ...?canonicalItem.data,
            ...?e.data,
          };
          synced.add(e.copyWith(name: canonicalItem.name, data: merged));
        } else if (isCustomToolbarItem(e)) {
          // 用户自定义模板项：原样保留
          synced.add(e);
        }
      }

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
    await _db.setToolbarShortcutsRaw(jsonEncode(_toolbarShortcuts));
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

  /// 新增用户自定义模板项
  Future<void> addToolbarItem(ManagedItem item) async {
    _toolbarItems.add(item);
    await _persistToolbar();
  }

  /// 更新工具栏项（自定义模板改名/改模板，或内置项改模板）
  Future<void> updateToolbarItem(String id, ManagedItem newValue) async {
    final i = _toolbarItems.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _toolbarItems[i] = newValue;
    await _persistToolbar();
  }

  /// 删除用户自定义模板项（内置项不允许删除，会被下次同步还原）
  Future<void> deleteToolbarItem(String id) async {
    _toolbarItems.removeWhere((e) => e.id == id);
    _toolbarShortcuts.remove(id);
    await _persistToolbar();
  }

  Future<void> resetToolbarItems() async {
    // 恢复内置项的默认顺序/显隐/模板/快捷键，但保留用户自定义模板项
    final custom = _toolbarItems.where(isCustomToolbarItem).toList();
    final customIds = custom.map((e) => e.id).toSet();
    final customShortcuts = Map<String, String>.fromEntries(
      _toolbarShortcuts.entries.where((e) => customIds.contains(e.key)),
    );
    _toolbarItems = [...defaultToolbarItems(), ...custom];
    _toolbarShortcuts = {...defaultToolbarShortcuts(), ...customShortcuts};
    await _persistToolbar();
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

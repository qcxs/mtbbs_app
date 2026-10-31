part of 'settings_provider.dart';

/// 把持久化的工具栏配置与当前内置默认值同步（供单测直接调用）。
///
/// 规则：
/// - 内置项：`data` 以持久化为准，缺失字段用默认补齐（用户改过的模板/标签保留）；
/// - **新引入的迷你上下文**（如新增的 `wall`）：老配置里"任何项都没出现过"的
///   ctx 视为新增，补进对应内置项的 `mini`，否则老用户的该上下文工具栏会是空的；
///   只补这类"从未出现过"的 ctx，不干扰用户已做的显隐选择；
/// - 用户自定义模板项：原样保留；
/// - 默认里有、持久化里没有的内置项：追加（新版本新增项自动补上）。
List<ManagedItem> syncToolbarWithDefaults(
  List<ManagedItem> loaded,
  List<ManagedItem> canonical,
) {
  final canonicalIds = canonical.map((e) => e.id).toSet();
  final loadedIds = loaded.map((e) => e.id).toSet();

  final knownMiniCtx = <String>{
    for (final e in loaded)
      if (e.data?['mini'] is List)
        ...(e.data!['mini'] as List).map((x) => x.toString()),
  };

  final synced = <ManagedItem>[];
  for (final e in loaded) {
    if (canonicalIds.contains(e.id)) {
      final canonicalItem = canonical.firstWhere((c) => c.id == e.id);
      final merged = <String, dynamic>{...?canonicalItem.data, ...?e.data};
      final cMini = canonicalItem.data?['mini'];
      if (cMini is List) {
        final cur = merged['mini'] is List
            ? (merged['mini'] as List).map((x) => x.toString()).toList()
            : <String>[];
        for (final ctx in cMini.map((x) => x.toString())) {
          if (!knownMiniCtx.contains(ctx) && !cur.contains(ctx)) {
            cur.add(ctx);
          }
        }
        merged['mini'] = cur;
      }
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
}

/// [SettingsProvider] 中可排序 / 可显隐配置项的写操作
/// （编辑器工具栏、快捷链接、导读 Tab、首页区块）
extension SettingsManagedLists on SettingsProvider {
  // ==================== 工具栏 ====================

  Future<void> _persistToolbar() async {
    await _persistApp();
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

  // ==================== 迷你编辑器：上下文可见性 ====================

  /// 设置某工具栏项在指定迷你上下文的可见性。
  ///
  /// 完整版与迷你版**共用同一份工具栏与顺序**；这里只改 `data['mini']` 的成员关系，
  /// 不新增/删除项，也不改顺序（顺序在「完整编辑器工具栏」里统一管理）。
  Future<void> setToolbarMiniVisible(
    MiniToolbarContext ctx,
    String id,
    bool visible,
  ) async {
    if (!miniToolbarSupportsItem(ctx, id)) return;
    final i = _toolbarItems.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final item = _toolbarItems[i];
    _toolbarItems[i] = item.copyWith(data: withMiniVisible(item, ctx, visible));
    await _persistToolbar();
  }

  /// 取反某工具栏项在指定迷你上下文的可见性
  Future<void> toggleToolbarMiniVisible(
    MiniToolbarContext ctx,
    String id,
  ) async {
    final i = _toolbarItems.indexWhere((e) => e.id == id);
    if (i < 0) return;
    await setToolbarMiniVisible(
      ctx,
      id,
      !toolbarMiniVisible(_toolbarItems[i], ctx),
    );
  }

  // ==================== 帖子迷你编辑器常用语 ====================

  Future<void> _persistQuickReplies() async {
    await _persistApp();
    _notify();
  }

  Future<void> addQuickReply(ManagedItem item) async {
    _quickReplies.add(item);
    await _persistQuickReplies();
  }

  Future<void> updateQuickReply(String id, ManagedItem newValue) async {
    final i = _quickReplies.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _quickReplies[i] = newValue;
    await _persistQuickReplies();
  }

  Future<void> deleteQuickReply(String id) async {
    _quickReplies.removeWhere((e) => e.id == id);
    await _persistQuickReplies();
  }

  Future<void> moveQuickReply(int from, int to) async {
    reorderManagedItems(_quickReplies, from, to);
    await _persistQuickReplies();
  }

  Future<void> toggleQuickReply(String id) async {
    toggleManagedItem(_quickReplies, id);
    await _persistQuickReplies();
  }

  /// 恢复默认常用语
  Future<void> resetQuickReplies() async {
    _quickReplies = settings_defaults.defaultQuickReplies();
    await _persistQuickReplies();
  }

  // ==================== 快捷链接 CRUD ====================

  List<ManagedItem> _linksForCurrent() =>
      List<ManagedItem>.from(_currentSite.shortcutLinks);

  Future<void> _persistLinks(List<ManagedItem> links) =>
      _updateCurrentSite((s) => s.copyWith(shortcutLinks: links));

  Future<void> addShortcutLink(ManagedItem item) async {
    final links = _linksForCurrent()..add(item);
    await _persistLinks(links);
  }

  Future<void> removeShortcutLink(String id) async {
    final links = _linksForCurrent()..removeWhere((e) => e.id == id);
    await _persistLinks(links);
  }

  Future<void> updateShortcutLink(String id, ManagedItem newValue) async {
    final links = _linksForCurrent();
    final idx = links.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    links[idx] = newValue;
    await _persistLinks(links);
  }

  Future<void> moveShortcutLink(int from, int to) async {
    final links = _linksForCurrent();
    reorderManagedItems(links, from, to);
    await _persistLinks(links);
  }

  Future<void> toggleShortcutLink(String id) async {
    final links = _linksForCurrent();
    toggleManagedItem(links, id);
    await _persistLinks(links);
  }

  // ==================== 导读 Tab ====================

  Future<void> moveTab(int from, int to) async {
    reorderManagedItems(_guideTabs, from, to);
    // 用户手排 = 以这份顺序为准 → 清空常用记录，之后重新累计
    _clearTabUsage(settings_defaults.kTabUsageGuide);
    await _persistGuideTabs();
  }

  Future<void> toggleTab(String id) async {
    toggleManagedItem(_guideTabs, id);
    await _persistGuideTabs();
  }

  Future<void> _persistGuideTabs() async {
    await _persistApp();
    _notify();
  }

  // ==================== 消息页 Tab ====================

  Future<void> moveNoticeTab(int from, int to) async {
    reorderManagedItems(_noticeTabs, from, to);
    // 同上：手排后清空常用记录
    _clearTabUsage(settings_defaults.kTabUsageNotice);
    await _persistNoticeTabs();
  }

  Future<void> toggleNoticeTab(String id) async {
    toggleManagedItem(_noticeTabs, id);
    await _persistNoticeTabs();
  }

  Future<void> _persistNoticeTabs() async {
    await _persistApp();
    _notify();
  }

  // ==================== Tab 使用次数（常用项自动前排） ====================

  /// 记录一次 Tab 使用（关掉「常用项自动前排」时不记，省一次写盘）
  Future<void> recordTabUsage(String scope, String id) async {
    if (!_autoFrequentTabs) return;
    final m = _tabUsage.putIfAbsent(scope, () => {});
    m[id] = (m[id] ?? 0) + 1;
    await _persistTabUsage();
  }

  void _clearTabUsage(String scope) => _tabUsage[scope] = {};

  Future<void> setAutoFrequentTabs(bool value) async {
    if (_autoFrequentTabs == value) return;
    _autoFrequentTabs = value;
    await _persistApp();
    _notify();
  }

  Future<void> _persistTabUsage() => _persistApp();

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
    await _persistApp();
    _notify();
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/site_config.dart';
import '../config/toolbar_config.dart';
import '../core/shortcut_helper.dart';
import '../api/home/credit/export.dart' as credit_api;
import '../services/api_service.dart';
import '../models/managed_item.dart';

/// 设置管理
class SettingsProvider extends ChangeNotifier {
  double _fontSize = 16;
  String _creditFormula = defaultFormula;
  List<String> _tabOrder = _defaultTabOrder;
  int _currentSiteIndex = 0;

  /// 默认启动 Tab (0=首页, 1=导读, 2=社区, 3=我的)
  int _defaultTabIndex = 0;

  /// 自定义快捷键（key = 动作ID, value = 按键字符串, 如 "Ctrl+T"）
  Map<String, String> _shortcuts = Map.from(ShortcutHelper.defaults);

  /// 全局禁用的 BBCode 样式标签
  Set<String> _disabledBbcodeTags = <String>{};

  /// 自动识别并链接 URL
  bool _autoDetectUrls = true;

  /// 用户自定义站点列表（持久化）
  List<Site> _sites = [];

  /// 快捷链接（按域名存储, key = host）
  final Map<String, List<ManagedItem>> _shortcutLinks = {};

  /// 工具栏项配置（全局，只排序+显隐）
  List<ManagedItem> _toolbarItems = defaultToolbarItems();

  /// 工具栏快捷键（与 toolbarItems 分离持久化，key = item id）
  Map<String, String> _toolbarShortcuts = defaultToolbarShortcuts();

  // ==================== 编辑器配置 ====================

  /// 快照最短字数（低于此不保存）
  int _minSnapshotWordCount = 10;

  /// 自动保存间隔（秒）
  int _autoSaveInterval = 30;

  /// 每会话自动快照上限
  int _maxAutoSnapshots = 10;

  // ==================== 浏览历史配置 ====================

  /// 帖子插入格式（占位符如 {title}、{author}、{time}）
  String _historyFormatThread = '{title}';

  /// 用户插入格式（占位符如 {nickname}、{uid}）
  String _historyFormatUser = '{nickname}';

  /// 最大记录数
  int _historyMaxCount = 200;

  /// 主题模式
  ThemeMode _themeMode = ThemeMode.system;

  /// 主题种子色
  Color _seedColor = const Color(0xFF9E9E9E);

  /// 预设主题色
  static const Map<String, Color> presetColors = {
    '纯白': Color(0xFF9E9E9E),
    '深紫': Colors.deepPurple,
    '亮蓝': Colors.blue,
    '青色': Colors.teal,
    '翠绿': Colors.green,
    '珊瑚': Color(0xFFFF6B6B),
  };

  static const String defaultFormula = '';

  static const _defaultTabOrder = ['newthread', 'hot', 'new', 'digest', 'sofa'];

  double get fontSize => _fontSize;
  List<String> get tabOrder => List.unmodifiable(_tabOrder);
  int get currentSiteIndex => _currentSiteIndex;
  int get defaultTabIndex => _defaultTabIndex;
  List<Site> get sites => _sites;

  /// 获取当前快捷键配置（Map<String, String>）
  Map<String, String> get shortcuts => Map.unmodifiable(_shortcuts);

  /// 获取指定动作的快捷键字符串
  String shortcut(String action) =>
      _shortcuts[action] ?? ShortcutHelper.defaults[action] ?? '';

  /// 全局禁用的 BBCode 样式标签集合
  Set<String> get disabledBbcodeTags => Set.unmodifiable(_disabledBbcodeTags);

  /// 自动识别纯文本 URL
  bool get autoDetectUrls => _autoDetectUrls;

  /// 主题模式
  ThemeMode get themeMode => _themeMode;

  /// 主题种子色
  Color get seedColor => _seedColor;

  /// 设置快捷键
  Future<void> setShortcut(String action, String keyString) async {
    _shortcuts[action] = keyString;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shortcuts', jsonEncode(_shortcuts));
    notifyListeners();
  }

  /// 设置全局禁用的 BBCode 样式标签
  Future<void> setDisabledBbcodeTags(Set<String> tags) async {
    _disabledBbcodeTags = Set.from(tags);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('disabledBbcodeTags', jsonEncode(tags.toList()));
    notifyListeners();
  }

  /// 设置自动识别 URL
  Future<void> setAutoDetectUrls(bool enabled) async {
    _autoDetectUrls = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoDetectUrls', enabled);
    notifyListeners();
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
    notifyListeners();
  }

  /// 设置主题种子色
  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('seedColor', color.toARGB32());
    notifyListeners();
  }

  static const tabLabels = {
    'newthread': '最新发表',
    'hot': '热门',
    'new': '最新回复',
    'digest': '精华',
    'sofa': '抢沙发',
    'my': '我的帖子',
  };

  /// 获取当前站点的积分公式
  String get creditFormula {
    // 需要从 prefs 实时获取
    return _creditFormula;
  }

  /// 当前站点的快捷链接
  List<ManagedItem> get shortcutLinks =>
      List.unmodifiable(_shortcutLinks[SiteConfig.current.host] ?? []);

  /// 工具栏项配置
  List<ManagedItem> get toolbarItems => List.unmodifiable(_toolbarItems);

  /// 获取工具栏项的快捷键字符串
  String toolbarShortcut(String id) =>
      _toolbarShortcuts[id] ?? defaultToolbarShortcuts()[id] ?? '';

  // ==================== 编辑器配置 ====================

  int get minSnapshotWordCount => _minSnapshotWordCount;
  int get autoSaveInterval => _autoSaveInterval;
  int get maxAutoSnapshots => _maxAutoSnapshots;

  Future<void> setMinSnapshotWordCount(int v) async {
    _minSnapshotWordCount = v.clamp(1, 100);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('minSnapshotWordCount', _minSnapshotWordCount);
    notifyListeners();
  }

  Future<void> setAutoSaveInterval(int seconds) async {
    _autoSaveInterval = seconds.clamp(5, 300);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('autoSaveInterval', _autoSaveInterval);
    notifyListeners();
  }

  Future<void> setMaxAutoSnapshots(int v) async {
    _maxAutoSnapshots = v.clamp(1, 50);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('maxAutoSnapshots', _maxAutoSnapshots);
    notifyListeners();
  }

  /// 帖子插入格式
  String get historyFormatThread => _historyFormatThread;

  /// 用户插入格式
  String get historyFormatUser => _historyFormatUser;

  /// 最大记录数
  int get historyMaxCount => _historyMaxCount;

  /// 设置当前站点积分公式
  Future<void> setCreditFormula(String formula) async {
    _creditFormula = formula;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('creditFormula_${SiteConfig.current.host}', formula);
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('fontSize') ?? 16;
    // 按站点加载积分公式
    _creditFormula =
        prefs.getString('creditFormula_${SiteConfig.current.host}') ??
        defaultFormula;
    _currentSiteIndex = prefs.getInt('currentSiteIndex') ?? 0;
    _defaultTabIndex = (prefs.getInt('defaultTabIndex') ?? 0).clamp(0, 3);

    // 恢复站点列表
    final sitesJson = prefs.getString('sites');
    if (sitesJson != null && sitesJson.isNotEmpty) {
      final list = jsonDecode(sitesJson) as List<dynamic>;
      _sites = list
          .map((j) => Site.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    // 如果没有持久化站点，用默认值
    if (_sites.isEmpty) {
      _sites = SiteConfig.defaultSites();
    }
    // 确保索引不越界（可能上次有更多站点）
    _currentSiteIndex = _currentSiteIndex.clamp(0, _sites.length - 1);
    // 同步到 SiteConfig
    SiteConfig.sites = _sites;
    _currentSiteIndex = _currentSiteIndex.clamp(0, _sites.length - 1);
    SiteConfig.switchTo(_currentSiteIndex);

    final saved = prefs.getString('tabOrder');
    if (saved != null && saved.isNotEmpty) {
      final parsed = saved
          .split(',')
          .where((v) => tabLabels.containsKey(v))
          .toList();
      if (parsed.isNotEmpty) _tabOrder = parsed;
    }

    // 恢复快捷键
    final shortcutsJson = prefs.getString('shortcuts');
    if (shortcutsJson != null && shortcutsJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(shortcutsJson) as Map<String, dynamic>;
        _shortcuts = parsed.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    // 恢复禁用的 BBCode 样式标签
    final disabledJson = prefs.getString('disabledBbcodeTags');
    if (disabledJson != null && disabledJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(disabledJson) as List<dynamic>;
        _disabledBbcodeTags = parsed.map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    // 恢复自动识别 URL
    _autoDetectUrls = prefs.getBool('autoDetectUrls') ?? true;

    // 恢复快捷链接（每个域名独立存储）
    for (final site in _sites) {
      final host = site.host;
      final linksJson = prefs.getString('shortcutLinks_$host');
      if (linksJson != null && linksJson.isNotEmpty) {
        try {
          _shortcutLinks[host] = ManagedItem.decodeList(linksJson);
        } catch (_) {}
      }
    }
    // 没有持久化快捷链接的站点，使用默认值
    for (final site in _sites) {
      final host = site.host;
      if (!_shortcutLinks.containsKey(host)) {
        _shortcutLinks[host] = _defaultShortcutLinks(host);
      }
    }

    // 恢复工具栏配置（自动适配新增/删除的项）
    _toolbarItems = _loadSyncedToolbar(prefs);

    // 恢复工具栏快捷键
    final tbShortcutsJson = prefs.getString('toolbarShortcuts');
    if (tbShortcutsJson != null && tbShortcutsJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(tbShortcutsJson) as Map<String, dynamic>;
        _toolbarShortcuts = parsed.map((k, v) => MapEntry(k, v.toString()));
        // 清理已被删除的项的残留 key（如 listA）
        _toolbarShortcuts.removeWhere((key, _) => !isValidToolbarItemId(key));
      } catch (_) {}
    }

    // 恢复编辑器配置
    _minSnapshotWordCount = prefs.getInt('minSnapshotWordCount') ?? 10;
    _autoSaveInterval = prefs.getInt('autoSaveInterval') ?? 30;
    _maxAutoSnapshots = prefs.getInt('maxAutoSnapshots') ?? 10;

    // 恢复历史记录设置
    _historyFormatThread = prefs.getString('historyFormat_thread') ?? '{title}';
    _historyFormatUser = prefs.getString('historyFormat_user') ?? '{nickname}';
    _historyMaxCount = prefs.getInt('historyMaxCount') ?? 200;

    // 恢复主题模式
    final themeModeStr = prefs.getString('themeMode');
    if (themeModeStr != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == themeModeStr,
        orElse: () => ThemeMode.system,
      );
    }

    // 恢复主题种子色
    final seedColorInt = prefs.getInt('seedColor');
    if (seedColorInt != null) {
      _seedColor = Color(seedColorInt);
    }

    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSize', size);
    notifyListeners();
  }

  Future<void> setTabOrder(List<String> order) async {
    _tabOrder = List.from(order);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tabOrder', order.join(','));
    notifyListeners();
  }

  /// 设置默认启动 Tab
  Future<void> setDefaultTabIndex(int index) async {
    _defaultTabIndex = index.clamp(0, 3);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('defaultTabIndex', _defaultTabIndex);
    notifyListeners();
  }

  /// 加载工具栏配置并自动适配（新增/删除的项自动同步）
  List<ManagedItem> _loadSyncedToolbar(SharedPreferences prefs) {
    final canonical = defaultToolbarItems();
    final canonicalIds = canonical.map((e) => e.id).toSet();

    final jsonStr = prefs.getString('toolbarItems');
    if (jsonStr == null || jsonStr.isEmpty) return canonical;

    try {
      final loaded = ManagedItem.decodeList(jsonStr);
      final loadedIds = loaded.map((e) => e.id).toSet();

      // 保留用户在 canonical 中的项（保留排序和显隐）
      final synced = loaded.where((e) => canonicalIds.contains(e.id)).map((e) {
        final canonicalItem = canonical.firstWhere((c) => c.id == e.id);
        return e.copyWith(name: canonicalItem.name);
      }).toList();

      // 追加新增的项（在 canonical 中有但 loaded 中没有的）
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

  // ==================== 浏览历史设置 ====================

  /// 设置帖子插入格式
  Future<void> setHistoryFormatThread(String format) async {
    _historyFormatThread = format;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('historyFormat_thread', format);
    notifyListeners();
  }

  /// 设置用户插入格式
  Future<void> setHistoryFormatUser(String format) async {
    _historyFormatUser = format;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('historyFormat_user', format);
    notifyListeners();
  }

  /// 设置最大记录数
  Future<void> setHistoryMaxCount(int count) async {
    _historyMaxCount = count.clamp(10, 1000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('historyMaxCount', _historyMaxCount);
    notifyListeners();
  }

  /// 切换站点
  Future<void> switchSite(int index) async {
    if (index == _currentSiteIndex) return;
    _currentSiteIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('currentSiteIndex', index);
    // 在 SiteConfig 切换后调用 reloadSiteConfig 加载 per-site 配置
    notifyListeners();
  }

  /// 在 SiteConfig 切换后调用，加载当前站点的所有独立配置
  Future<void> reloadSiteConfig() async {
    _creditFormula = await _loadFormulaForHost(SiteConfig.current.host);
    notifyListeners();
  }

  /// 按站点加载积分公式
  Future<String> _loadFormulaForHost(String host) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('creditFormula_$host') ?? defaultFormula;
  }

  // ==================== 快捷链接 CRUD ====================

  List<ManagedItem> _linksForCurrent() =>
      _shortcutLinks.putIfAbsent(SiteConfig.current.host, () => []);

  Future<void> _persistLinks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'shortcutLinks_${SiteConfig.current.host}',
      ManagedItem.encodeList(_linksForCurrent()),
    );
    notifyListeners();
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
    final list = _linksForCurrent();
    final item = list.removeAt(from);
    final idx = to > from ? to - 1 : to;
    list.insert(idx.clamp(0, list.length), item);
    await _persistLinks();
  }

  Future<void> toggleShortcutLink(String id) async {
    final idx = _linksForCurrent().indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _linksForCurrent()[idx] = _linksForCurrent()[idx].copyWith(
      visible: !_linksForCurrent()[idx].visible,
    );
    await _persistLinks();
  }

  // ==================== 工具栏项管理（只排序+显隐） ====================

  Future<void> _persistToolbar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'toolbarItems',
      ManagedItem.encodeList(_toolbarItems),
    );
    notifyListeners();
  }

  Future<void> moveToolbarItem(int from, int to) async {
    final item = _toolbarItems.removeAt(from);
    final idx = to > from ? to - 1 : to;
    _toolbarItems.insert(idx.clamp(0, _toolbarItems.length), item);
    await _persistToolbar();
  }

  Future<void> toggleToolbarItem(String id) async {
    final idx = _toolbarItems.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _toolbarItems[idx] = _toolbarItems[idx].copyWith(
      visible: !_toolbarItems[idx].visible,
    );
    await _persistToolbar();
  }

  /// 设置工具栏项的快捷键
  Future<void> setToolbarShortcut(String id, String keyString) async {
    _toolbarShortcuts[id] = keyString;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('toolbarShortcuts', jsonEncode(_toolbarShortcuts));
    notifyListeners();
  }

  /// 重置工具栏排序和显隐为默认值
  Future<void> resetToolbarItems() async {
    _toolbarItems = defaultToolbarItems();
    _toolbarShortcuts = defaultToolbarShortcuts();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'toolbarItems',
      ManagedItem.encodeList(_toolbarItems),
    );
    await prefs.setString('toolbarShortcuts', jsonEncode(_toolbarShortcuts));
    notifyListeners();
  }

  // ==================== Tab 排序统一方法 ====================

  /// 移动 Tab 位置
  Future<void> moveTab(int from, int to) async {
    final item = _tabOrder.removeAt(from);
    final idx = to > from ? to - 1 : to;
    _tabOrder.insert(idx.clamp(0, _tabOrder.length), item);
    await _persistTabOrder();
  }

  /// 切换 Tab 可见性（在 tabOrder 中添加或移除）
  Future<void> toggleTab(String view) async {
    if (_tabOrder.contains(view)) {
      _tabOrder.remove(view);
    } else {
      _tabOrder.add(view);
    }
    await _persistTabOrder();
  }

  Future<void> _persistTabOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tabOrder', _tabOrder.join(','));
    notifyListeners();
  }

  /// 新增站点
  Future<void> addSite(Site site) async {
    _sites.add(site);
    await _persistSites();
  }

  /// 删除站点
  Future<void> deleteSite(int index) async {
    if (index < 0 || index >= _sites.length) return;
    _sites.removeAt(index);
    if (_currentSiteIndex >= _sites.length) {
      _currentSiteIndex = _sites.length - 1;
    }
    await _persistSites();
  }

  /// 更新指定索引的站点
  Future<void> updateSite(int index, Site site) async {
    if (index < 0 || index >= _sites.length) return;
    _sites[index] = site;
    if (index == _currentSiteIndex) {
      SiteConfig.current = site;
    }
    await _persistSites();
    notifyListeners();
  }

  /// 用新的完整列表替换
  Future<void> replaceSites(List<Site> newSites) async {
    _sites = List.from(newSites);
    await _persistSites();
  }

  /// 获取当前站点的论坛列表
  List<MapEntry<String, String>> get forumEntries {
    final f = SiteConfig.forums;
    return SiteConfig.defaultForumOrder
        .where((fid) => f.containsKey(fid))
        .map((fid) => MapEntry(fid, f[fid]!))
        .toList();
  }

  /// 新增论坛
  Future<void> addForum(String fid, String name) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..[fid] = name;
    final newOrder = List<String>.from(old.defaultForumOrder)..add(fid);
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      loginPagePath: old.loginPagePath,
      forums: newForums,
      defaultForumOrder: newOrder,
    );
    await _persistSites();
  }

  /// 删除论坛
  Future<void> removeForum(String fid) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..remove(fid);
    final newOrder = List<String>.from(old.defaultForumOrder)..remove(fid);
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      loginPagePath: old.loginPagePath,
      forums: newForums,
      defaultForumOrder: newOrder,
    );
    await _persistSites();
    notifyListeners();
  }

  /// 移动论坛（重新排序）
  Future<void> moveForum(int oldIndex, int newIndex) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final order = List<String>.from(_sites[idx].defaultForumOrder);
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex < 0 || newIndex >= order.length) return;
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    _sites[idx] = Site(
      name: _sites[idx].name,
      baseUrl: _sites[idx].baseUrl,
      cdn: _sites[idx].cdn,
      loginPagePath: _sites[idx].loginPagePath,
      forums: _sites[idx].forums,
      defaultForumOrder: order,
    );
    await _persistSites();
    notifyListeners();
  }

  /// 重命名论坛
  Future<void> renameForum(String fid, String newName) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    final newForums = Map<String, String>.from(old.forums)..[fid] = newName;
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      loginPagePath: old.loginPagePath,
      forums: newForums,
      defaultForumOrder: List.from(old.defaultForumOrder),
    );
    await _persistSites();
  }

  /// 用 API 返回的数据替换当前站点的论坛列表（保留顺序）
  Future<void> replaceForums(Map<String, String> newForums) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    // 只保留 newForums 中存在的 fid，不存在的从列表中移除
    final newOrder = old.defaultForumOrder
        .where((fid) => newForums.containsKey(fid))
        .toList();
    // 补充新 fid 到末尾
    for (final fid in newForums.keys) {
      if (!newOrder.contains(fid)) newOrder.add(fid);
    }
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      loginPagePath: old.loginPagePath,
      forums: Map.from(newForums),
      defaultForumOrder: newOrder,
    );
    await _persistSites();
  }

  Future<void> _persistSites() async {
    // 同步到 SiteConfig
    SiteConfig.sites = _sites;
    SiteConfig.switchTo(_currentSiteIndex.clamp(0, _sites.length - 1));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sites',
      jsonEncode(_sites.map((s) => s.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<String?> fetchAndUpdateFormula() async {
    try {
      final result = await credit_api.fetch(ApiService().dio);
      if (result['success'] == true && result['formula'] != null) {
        _creditFormula = result['formula'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'creditFormula_${SiteConfig.current.host}',
          _creditFormula,
        );
        notifyListeners();
        return _creditFormula;
      }
      return null;
    } catch (e) {
      debugPrint('[SettingsProvider] fetch formula error: $e');
      return null;
    }
  }

  /// 返回指定站点的默认快捷链接。
  /// 无持久化数据时使用，首次设置后用户可自行增删改。
  static List<ManagedItem> _defaultShortcutLinks(String host) {
    if (host == 'bbs.binmt.cc') {
      return [
        ManagedItem(
          id: 'sign',
          name: '签到',
          data: {'url': 'https://bbs.binmt.cc/k_misign-sign.html'},
        ),
        ManagedItem(
          id: 'shop',
          name: '积分商城',
          data: {
            'url':
                'https://bbs.binmt.cc/keke_integralmall-keke_integralmall.html',
          },
        ),
        ManagedItem(
          id: 'apply_essence',
          name: '申请精华',
          data: {'url': 'https://bbs.binmt.cc/thread-86543-1-1.html'},
        ),
        ManagedItem(
          id: 'rules',
          name: '总版规',
          data: {'url': 'https://bbs.binmt.cc/thread-85763-1-1.html'},
        ),
        ManagedItem(
          id: 'image_bed',
          name: 'MT图床',
          data: {'url': 'https://bbs.binmt.cc/thread-98890-1-1.html'},
        ),
        ManagedItem(
          id: 'cloud_drive',
          name: '网盘清单',
          data: {'url': 'https://bbs.binmt.cc/thread-156696-1-1.html'},
        ),
        ManagedItem(
          id: 'my_threads',
          name: '我的帖子',
          data: {
            'url': 'https://bbs.binmt.cc/home.php?mod=space&do=thread&view=me',
          },
        ),
        ManagedItem(
          id: 'my_favorites',
          name: '我的收藏',
          data: {
            'url':
                'https://bbs.binmt.cc/home.php?mod=space&do=favorite&view=me&type=all',
          },
        ),
        ManagedItem(
          id: 'my_friends',
          name: '我的好友',
          data: {'url': 'https://bbs.binmt.cc/home.php?mod=space&do=friend'},
        ),
        ManagedItem(
          id: 'notices',
          name: '消息提醒',
          data: {'url': 'https://bbs.binmt.cc/home.php?mod=space&do=notice'},
        ),
      ];
    }
    return [];
  }
}

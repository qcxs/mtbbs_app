import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/core/utils/database_helper.dart';

/// 设置管理 — 统一通过 [DatabaseHelper] 持久化
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

  /// 通用错峰间隔（毫秒），头像/预览等批量请求逐个放行
  int _staggerInterval = 40;

  /// 头像缓存天数（-1 表示永不过期）
  int _avatarCacheDays = 7;

  /// 表情缓存天数（-1 表示永不过期）
  int _emojiCacheDays = -1;

  /// 帖子图片缓存天数（-1 表示永不过期）
  int _imageCacheDays = 3;

  /// 勋章图片缓存天数（-1 表示永不过期）
  int _medalCacheDays = -1;

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

  /// 历史记录标题格式 — 帖子
  String _historyTitleFormatThread = '{title} by:{author} {time}';

  /// 历史记录标题格式 — 用户
  String _historyTitleFormatUser = '{nickname}(UID={uid})';

  /// 历史记录标题格式 — 我的帖子
  String _historyTitleFormatMythread = '{typeLabel}(UID={uid}, 第{page}页)';

  /// 历史记录标题格式 — 回复
  String _historyTitleFormatReply = '{typeLabel}(UID={uid}, 第{page}页)';

  /// 主题模式
  ThemeMode _themeMode = ThemeMode.system;

  /// 主题种子色
  Color _seedColor = const Color(0xFF9E9E9E);

  /// 纯黑主题（仅深色模式下生效）
  bool _isPureBlackTheme = false;

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

  // ==================== 数据库快捷引用 ====================

  DatabaseHelper get _db => DatabaseHelper.instance;

  // ==================== Getter ====================

  double get fontSize => _fontSize;
  List<String> get tabOrder => List.unmodifiable(_tabOrder);
  int get currentSiteIndex => _currentSiteIndex;
  int get defaultTabIndex => _defaultTabIndex;
  List<Site> get sites => _sites;

  Map<String, String> get shortcuts => Map.unmodifiable(_shortcuts);

  String shortcut(String action) =>
      _shortcuts[action] ?? ShortcutHelper.defaults[action] ?? '';

  Set<String> get disabledBbcodeTags => Set.unmodifiable(_disabledBbcodeTags);
  bool get autoDetectUrls => _autoDetectUrls;
  int get staggerInterval => _staggerInterval;
  int get avatarCacheDays => _avatarCacheDays;
  int get emojiCacheDays => _emojiCacheDays;
  int get imageCacheDays => _imageCacheDays;
  int get medalCacheDays => _medalCacheDays;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get isPureBlackTheme => _isPureBlackTheme;
  bool _showAvatars = true;
  bool get showAvatars => _showAvatars;

  String get creditFormula => _creditFormula;

  List<ManagedItem> get shortcutLinks =>
      List.unmodifiable(_shortcutLinks[SiteStore.instance.host] ?? []);

  List<ManagedItem> get toolbarItems => List.unmodifiable(_toolbarItems);

  String toolbarShortcut(String id) =>
      _toolbarShortcuts[id] ?? defaultToolbarShortcuts()[id] ?? '';

  int get minSnapshotWordCount => _minSnapshotWordCount;
  int get autoSaveInterval => _autoSaveInterval;
  int get maxAutoSnapshots => _maxAutoSnapshots;
  String get historyFormatThread => _historyFormatThread;
  String get historyFormatUser => _historyFormatUser;
  int get historyMaxCount => _historyMaxCount;
  String get historyTitleFormatThread => _historyTitleFormatThread;
  String get historyTitleFormatUser => _historyTitleFormatUser;
  String get historyTitleFormatMythread => _historyTitleFormatMythread;
  String get historyTitleFormatReply => _historyTitleFormatReply;

  static const tabLabels = {
    'newthread': '最新发表',
    'hot': '热门',
    'new': '最新回复',
    'digest': '精华',
    'sofa': '抢沙发',
    'my': '我的帖子',
  };

  // ==================== 加载 ====================

  Future<void> load() async {
    // 基本数值设置
    _fontSize = (await _db.getSettingDouble('fontSize')) ?? 16;
    _currentSiteIndex = (await _db.getSettingInt('currentSiteIndex')) ?? 0;
    _defaultTabIndex = ((await _db.getSettingInt('defaultTabIndex')) ?? 0)
        .clamp(0, 3);

    _autoDetectUrls = (await _db.getSettingBool('autoDetectUrls')) ?? true;
    _staggerInterval = (await _db.getSettingInt('staggerInterval')) ?? 40;
    _avatarCacheDays = (await _db.getSettingInt('avatarCacheDays')) ?? 7;
    _emojiCacheDays = (await _db.getSettingInt('emojiCacheDays')) ?? -1;
    _imageCacheDays = (await _db.getSettingInt('imageCacheDays')) ?? 3;
    _medalCacheDays = (await _db.getSettingInt('medalCacheDays')) ?? -1;
    _minSnapshotWordCount =
        (await _db.getSettingInt('minSnapshotWordCount')) ?? 10;
    _autoSaveInterval = (await _db.getSettingInt('autoSaveInterval')) ?? 30;
    _maxAutoSnapshots = (await _db.getSettingInt('maxAutoSnapshots')) ?? 10;
    _historyMaxCount = (await _db.getSettingInt('historyMaxCount')) ?? 200;

    _historyFormatThread =
        (await _db.getSetting('historyFormat_thread')) ?? '{title}';
    _historyFormatUser =
        (await _db.getSetting('historyFormat_user')) ?? '{nickname}';
    _historyTitleFormatThread =
        (await _db.getSetting('historyTitleFormat_thread')) ?? '{title}';
    _historyTitleFormatUser =
        (await _db.getSetting('historyTitleFormat_user')) ?? '{nickname}';
    _historyTitleFormatMythread =
        (await _db.getSetting('historyTitleFormat_mythread')) ??
        '{typeLabel}(UID={uid}, 第{page}页)';
    _historyTitleFormatReply =
        (await _db.getSetting('historyTitleFormat_reply')) ??
        '{typeLabel}(UID={uid}, 第{page}页)';

    // 积分公式（按站点）
    _creditFormula =
        (await _db.getCreditFormula(SiteStore.instance.host)) ?? defaultFormula;

    // 恢复站点列表
    final sitesJson = await _db.getSitesRaw();
    if (sitesJson != null && sitesJson.isNotEmpty) {
      final list = jsonDecode(sitesJson) as List<dynamic>;
      _sites = list
          .map((j) => Site.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    if (_sites.isEmpty) {
      _sites = SiteConfig.defaultSites();
    }
    _currentSiteIndex = _currentSiteIndex.clamp(0, _sites.length - 1);
    SiteStore.instance.replaceSites(_sites);
    _currentSiteIndex = _currentSiteIndex.clamp(0, _sites.length - 1);
    SiteStore.instance.switchTo(_currentSiteIndex);

    // Tab 排序
    final saved = await _db.getSetting('tabOrder');
    if (saved != null && saved.isNotEmpty) {
      final parsed = saved
          .split(',')
          .where((v) => tabLabels.containsKey(v))
          .toList();
      if (parsed.isNotEmpty) _tabOrder = parsed;
    }

    // 快捷键映射
    final shortcutsJson = await _db.getShortcutsRaw();
    if (shortcutsJson != null && shortcutsJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(shortcutsJson) as Map<String, dynamic>;
        _shortcuts = parsed.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    // 禁用的 BBCode 标签
    final disabledJson = await _db.getDisabledBbcodeRaw();
    if (disabledJson != null && disabledJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(disabledJson) as List<dynamic>;
        _disabledBbcodeTags = parsed.map((e) => e.toString()).toSet();
      } catch (_) {}
    }

    // 快捷链接（每个站点独立存储）
    for (final site in _sites) {
      final host = site.host;
      final linksJson = await _db.getShortcutLinksRaw(host);
      if (linksJson != null && linksJson.isNotEmpty) {
        try {
          _shortcutLinks[host] = ManagedItem.decodeList(linksJson);
        } catch (_) {}
      }
    }
    for (final site in _sites) {
      final host = site.host;
      if (!_shortcutLinks.containsKey(host)) {
        _shortcutLinks[host] = DefaultConfig.instance.shortcutLinksFor(host);
      }
    }

    // 工具栏配置
    _toolbarItems = await _loadSyncedToolbar();

    // 工具栏快捷键
    final tbShortcutsJson = await _db.getToolbarShortcutsRaw();
    if (tbShortcutsJson != null && tbShortcutsJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(tbShortcutsJson) as Map<String, dynamic>;
        _toolbarShortcuts = parsed.map((k, v) => MapEntry(k, v.toString()));
        _toolbarShortcuts.removeWhere((key, _) => !isValidToolbarItemId(key));
      } catch (_) {}
    }

    // 主题模式
    final themeModeStr = await _db.getSetting('themeMode');
    if (themeModeStr != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == themeModeStr,
        orElse: () => ThemeMode.system,
      );
    }

    // 主题种子色
    final seedColorInt = await _db.getSettingInt('seedColor');
    if (seedColorInt != null) {
      _seedColor = Color(seedColorInt);
    }

    // 纯黑主题
    _isPureBlackTheme = (await _db.getSettingBool('pureBlackTheme')) ?? false;

    // 头像设置
    _showAvatars = (await _db.getSettingBool('showAvatars')) ?? true;

    notifyListeners();
  }

  // ==================== 写入方法 ====================

  Future<void> setShortcut(String action, String keyString) async {
    _shortcuts[action] = keyString;
    await _db.setShortcutsRaw(jsonEncode(_shortcuts));
    notifyListeners();
  }

  Future<void> setDisabledBbcodeTags(Set<String> tags) async {
    _disabledBbcodeTags = Set.from(tags);
    await _db.setDisabledBbcodeRaw(jsonEncode(tags.toList()));
    notifyListeners();
  }

  Future<void> setAutoDetectUrls(bool enabled) async {
    _autoDetectUrls = enabled;
    await _db.setSettingBool('autoDetectUrls', enabled);
    notifyListeners();
  }

  Future<void> setStaggerInterval(int ms) async {
    _staggerInterval = ms.clamp(20, 300);
    await _db.setSettingInt('staggerInterval', _staggerInterval);
    notifyListeners();
  }

  Future<void> setAvatarCacheDays(int days) async {
    _avatarCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('avatarCacheDays', _avatarCacheDays);
    notifyListeners();
  }

  Future<void> setEmojiCacheDays(int days) async {
    _emojiCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('emojiCacheDays', _emojiCacheDays);
    notifyListeners();
  }

  Future<void> setImageCacheDays(int days) async {
    _imageCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('imageCacheDays', _imageCacheDays);
    notifyListeners();
  }

  Future<void> setMedalCacheDays(int days) async {
    _medalCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('medalCacheDays', _medalCacheDays);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _db.setSetting('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    await _db.setSettingInt('seedColor', color.toARGB32());
    notifyListeners();
  }

  Future<void> setPureBlackTheme(bool value) async {
    _isPureBlackTheme = value;
    await _db.setSettingBool('pureBlackTheme', value);
    notifyListeners();
  }

  Future<void> setShowAvatars(bool value) async {
    _showAvatars = value;
    await _db.setSettingBool('showAvatars', value);
    notifyListeners();
  }

  Future<void> setMinSnapshotWordCount(int v) async {
    _minSnapshotWordCount = v.clamp(1, 100);
    await _db.setSettingInt('minSnapshotWordCount', _minSnapshotWordCount);
    notifyListeners();
  }

  Future<void> setAutoSaveInterval(int seconds) async {
    _autoSaveInterval = seconds.clamp(5, 300);
    await _db.setSettingInt('autoSaveInterval', _autoSaveInterval);
    notifyListeners();
  }

  Future<void> setMaxAutoSnapshots(int v) async {
    _maxAutoSnapshots = v.clamp(1, 50);
    await _db.setSettingInt('maxAutoSnapshots', _maxAutoSnapshots);
    notifyListeners();
  }

  Future<void> setCreditFormula(String formula) async {
    _creditFormula = formula;
    await _db.setCreditFormula(SiteStore.instance.host, formula);
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _db.setSettingDouble('fontSize', size);
    notifyListeners();
  }

  Future<void> setTabOrder(List<String> order) async {
    _tabOrder = List.from(order);
    await _db.setSetting('tabOrder', order.join(','));
    notifyListeners();
  }

  Future<void> setDefaultTabIndex(int index) async {
    _defaultTabIndex = index.clamp(0, 3);
    await _db.setSettingInt('defaultTabIndex', _defaultTabIndex);
    notifyListeners();
  }

  Future<void> setHistoryFormatThread(String format) async {
    _historyFormatThread = format;
    await _db.setSetting('historyFormat_thread', format);
    notifyListeners();
  }

  Future<void> setHistoryFormatUser(String format) async {
    _historyFormatUser = format;
    await _db.setSetting('historyFormat_user', format);
    notifyListeners();
  }

  Future<void> setHistoryMaxCount(int count) async {
    _historyMaxCount = count.clamp(10, 1000);
    await _db.setSettingInt('historyMaxCount', _historyMaxCount);
    notifyListeners();
  }

  Future<void> setHistoryTitleFormatThread(String format) async {
    _historyTitleFormatThread = format;
    await _db.setSetting('historyTitleFormat_thread', format);
    notifyListeners();
  }

  Future<void> setHistoryTitleFormatUser(String format) async {
    _historyTitleFormatUser = format;
    await _db.setSetting('historyTitleFormat_user', format);
    notifyListeners();
  }

  Future<void> setHistoryTitleFormatMythread(String format) async {
    _historyTitleFormatMythread = format;
    await _db.setSetting('historyTitleFormat_mythread', format);
    notifyListeners();
  }

  Future<void> setHistoryTitleFormatReply(String format) async {
    _historyTitleFormatReply = format;
    await _db.setSetting('historyTitleFormat_reply', format);
    notifyListeners();
  }

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

  Future<void> setToolbarShortcut(String id, String keyString) async {
    _toolbarShortcuts[id] = keyString;
    await _db.setToolbarShortcutsRaw(jsonEncode(_toolbarShortcuts));
    notifyListeners();
  }

  Future<void> resetToolbarItems() async {
    _toolbarItems = defaultToolbarItems();
    _toolbarShortcuts = defaultToolbarShortcuts();
    await _db.setToolbarItemsRaw(ManagedItem.encodeList(_toolbarItems));
    await _db.setToolbarShortcutsRaw(jsonEncode(_toolbarShortcuts));
    notifyListeners();
  }

  // ==================== 快捷链接 CRUD ====================

  List<ManagedItem> _linksForCurrent() =>
      _shortcutLinks.putIfAbsent(SiteStore.instance.host, () => []);

  Future<void> _persistLinks() async {
    await _db.setShortcutLinksRaw(
      SiteStore.instance.host,
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
    list.insert(to.clamp(0, list.length), item);
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

  // ==================== Tab 排序 ====================

  Future<void> moveTab(int from, int to) async {
    final item = _tabOrder.removeAt(from);
    final idx = to > from ? to - 1 : to;
    _tabOrder.insert(idx.clamp(0, _tabOrder.length), item);
    await _persistTabOrder();
  }

  Future<void> toggleTab(String view) async {
    if (_tabOrder.contains(view)) {
      _tabOrder.remove(view);
    } else {
      _tabOrder.add(view);
    }
    await _persistTabOrder();
  }

  Future<void> _persistTabOrder() async {
    await _db.setSetting('tabOrder', _tabOrder.join(','));
    notifyListeners();
  }

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
    notifyListeners();
  }

  Future<void> setSiteUA(String userAgent) async {
    final idx = _currentSiteIndex;
    if (idx < 0 || idx >= _sites.length) return;
    final old = _sites[idx];
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      cdn: old.cdn,
      loginPagePath: old.loginPagePath,
      forums: old.forums,
      defaultForumOrder: old.defaultForumOrder,
      userAgent: userAgent,
    );
    SiteStore.instance.switchTo(idx);
    await _persistSites();
    notifyListeners();
  }

  Future<void> replaceSites(List<Site> newSites) async {
    _sites = List.from(newSites);
    await _persistSites();
  }

  List<MapEntry<String, String>> get forumEntries {
    final f = SiteStore.instance.forums;
    return SiteStore.instance.defaultForumOrder
        .where((fid) => f.containsKey(fid))
        .map((fid) => MapEntry(fid, f[fid]!))
        .toList();
  }

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
    _sites[idx] = Site(
      name: old.name,
      baseUrl: old.baseUrl,
      cdn: old.cdn,
      loginPagePath: old.loginPagePath,
      forums: Map.from(newForums),
      defaultForumOrder: newOrder,
    );
    await _persistSites();
  }

  Future<void> _persistSites() async {
    SiteStore.instance.replaceSites(_sites);
    SiteStore.instance.switchTo(_currentSiteIndex.clamp(0, _sites.length - 1));
    await _db.setSitesRaw(jsonEncode(_sites.map((s) => s.toJson()).toList()));
    notifyListeners();
  }

  // ==================== 站点切换 ====================

  Future<void> switchSite(int index) async {
    if (index == _currentSiteIndex) return;
    _currentSiteIndex = index;
    await _db.setSettingInt('currentSiteIndex', index);
    notifyListeners();
  }

  Future<void> reloadSiteConfig() async {
    _creditFormula = await _loadFormulaForHost(SiteStore.instance.host);
    notifyListeners();
  }

  Future<String> _loadFormulaForHost(String host) async {
    return (await _db.getCreditFormula(host)) ?? defaultFormula;
  }

  Future<String?> fetchAndUpdateFormula() async {
    try {
      final result = await credit_api.fetch(ApiService().dio);
      if (result['success'] == true && result['formula'] != null) {
        _creditFormula = result['formula'] as String;
        await _db.setCreditFormula(SiteStore.instance.host, _creditFormula);
        notifyListeners();
        return _creditFormula;
      }
      return null;
    } catch (e) {
      debugPrint('[SettingsProvider] fetch formula error: $e');
      return null;
    }
  }
}

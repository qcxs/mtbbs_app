part of 'settings_provider.dart';

/// [SettingsProvider] 的只读访问器
extension SettingsAccessors on SettingsProvider {
  /// 完整导读 Tab 列表（含隐藏项，供排序弹窗使用）
  List<ManagedItem> get guideTabs => List.unmodifiable(_guideTabs);

  /// 可见导读 Tab id（按当前顺序）
  List<String> get tabOrder => [
    for (final t in _guideTabs)
      if (t.visible) t.id,
  ];

  /// 完整首页区块列表（含隐藏项，供设置面板使用）
  List<ManagedItem> get homeSections => List.unmodifiable(_homeSections);

  /// 首页当前显示的区块（按用户排序）
  List<ManagedItem> get visibleHomeSections => [
    for (final s in _homeSections)
      if (s.visible) s,
  ];
  int get currentSiteIndex => _currentSiteIndex;
  int get defaultTabIndex => _defaultTabIndex;
  List<Site> get sites => _sites;

  Map<String, String> get shortcuts => Map.unmodifiable(_shortcuts);

  bool get simulateBrowserHeaders => _simulateBrowserHeaders;
  int get staggerInterval => _staggerInterval;
  int get avatarCacheDays => _avatarCacheDays;
  int get emojiCacheDays => _emojiCacheDays;
  int get imageCacheDays => _imageCacheDays;
  int get medalCacheDays => _medalCacheDays;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get isPureBlackTheme => _isPureBlackTheme;
  bool get showAvatars => _showAvatars;
  AvatarSizeMode get avatarSizeMode => _avatarSizeMode;
  int get maxImageWidth => _maxImageWidth;

  String get creditFormula => _creditFormula;

  List<ManagedItem> get shortcutLinks =>
      List.unmodifiable(_shortcutLinks[SiteStore.instance.host] ?? []);

  int get minSnapshotWordCount => _minSnapshotWordCount;
  int get autoSaveInterval => _autoSaveInterval;
  int get maxAutoSnapshots => _maxAutoSnapshots;
  String get historyFormatThread => _historyFormatThread;
  String get historyFormatUser => _historyFormatUser;
  String get historyTitleFormatThread => _historyTitleFormatThread;
  String get historyTitleFormatUser => _historyTitleFormatUser;
  String get historyTitleFormatMythread => _historyTitleFormatMythread;
  String get historyTitleFormatReply => _historyTitleFormatReply;

  List<MapEntry<String, String>> get forumEntries {
    final f = SiteStore.instance.forums;
    return SiteStore.instance.defaultForumOrder
        .where((fid) => f.containsKey(fid))
        .map((fid) => MapEntry(fid, f[fid]!))
        .toList();
  }
}

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
  bool get interstitialAutoVerify => _interstitialAutoVerify;

  /// 跳过本地自解，强制走内置浏览器完成人机验证
  bool get acwForceWebview => _acwForceWebview;

  /// 开发者选项是否已解锁
  bool get developerMode => _developerMode;

  /// 该页面是否仍由 App 接管（false = 已改为走内置浏览器）
  bool isAppPageEnabled(String id) => appPageEnabled(id);

  /// 是否处于"整体退化为内置浏览器"模式（逃生阀）
  bool get browserOnlyMode => _browserOnlyMode;
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

  /// 某上下文的迷你编辑器工具栏项。
  ///
  /// 与完整版**共用同一套工具栏**（同一份 `_toolbarItems`，顺序统一），
  /// 只按该上下文的可见性（`data['mini']`）与该上下文能力过滤。
  List<ManagedItem> miniToolbarItems(MiniToolbarContext ctx) =>
      List.unmodifiable([
        for (final e in _toolbarItems)
          if (toolbarMiniVisible(e, ctx) && miniToolbarSupportsItem(ctx, e.id))
            e,
      ]);

  /// 工具栏项被隐藏时其快捷键是否仍然生效
  bool get toolbarShortcutWhenHidden => _toolbarShortcutWhenHidden;

  /// 帖子页是否使用内嵌迷你编辑器（false = 退回原全屏编辑器）
  bool get threadMiniEditorEnabled => _threadMiniEditor;

  /// 帖子迷你编辑器「常用语」（仅可见项按顺序）
  List<ManagedItem> get quickReplies => List.unmodifiable(_quickReplies);

  /// 启动时是否自动检查更新（仅正式版生效）
  bool get autoCheckUpdate => _autoCheckUpdate;

  /// 用户已跳过的新版本 tag（'' = 未跳过）
  String get skippedUpdateVersion => _skippedUpdateVersion;

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

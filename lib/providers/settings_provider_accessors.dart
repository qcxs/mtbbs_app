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

  /// 完整消息页 Tab 列表（含隐藏项，供排序弹窗使用）
  List<ManagedItem> get noticeTabs => List.unmodifiable(_noticeTabs);

  /// 可见消息页 Tab id（按用户排序）
  List<String> get noticeTabOrder => [
    for (final t in _noticeTabs)
      if (t.visible) t.id,
  ];

  /// 「常用项自动前排」开关
  bool get autoFrequentTabs => _autoFrequentTabs;

  /// 某作用域的 Tab 使用次数
  Map<String, int> tabUsage(String scope) =>
      Map.unmodifiable(_tabUsage[scope] ?? const {});

  /// 按设置给出最终顺序：开启「常用项自动前排」时把**第 1 项之后的**项按使用次数重排
  /// （第 1 项固定 = 默认进入项，只由手动排序决定；次数相同保持 [base] 顺序）
  List<String> orderedTabIds(String scope, List<String> base) =>
      _autoFrequentTabs
      ? orderByFrequency(base, _tabUsage[scope] ?? const {})
      : base;

  /// 首页当前显示的区块（按用户排序）
  List<ManagedItem> get visibleHomeSections => [
    for (final s in _homeSections)
      if (s.visible) s,
  ];
  int get currentSiteIndex => _currentSiteIndex;
  int get defaultTabIndex => _defaultTabIndex;

  /// 「返回键双击退出」开关（仅 Android 返回键生效）
  bool get doubleBackExit => _doubleBackExit;
  List<Site> get sites => _sites;

  Map<String, String> get shortcuts => Map.unmodifiable(_shortcuts);

  bool get simulateBrowserHeaders =>
      _currentSite.network.simulateBrowserHeaders;
  bool get interstitialAutoVerify =>
      _currentSite.network.interstitialAutoVerify;

  /// 消息未读标记样式（隐藏 / 红点 / 数字）
  NoticeBadgeMode get noticeBadgeMode => _noticeBadgeMode;

  /// 是否检查新提醒
  bool get noticeCheckEnabled => _noticeCheckEnabled;

  /// 计入底栏未读的分组 id
  Set<String> get noticeBadgeGroups => Set.unmodifiable(_noticeBadgeGroups);

  /// 跳过本地自解，强制走内置浏览器完成人机验证（当前站点）
  bool get acwForceWebview => _currentSite.network.acwForceWebview;

  /// 开发者选项是否已解锁
  bool get developerMode => _developerMode;

  /// 该页面是否仍由 App 接管（当前站点；false = 已改为走内置浏览器）
  bool isAppPageEnabled(String id) =>
      !_currentSite.pages.disabledPageIds.contains(id);

  /// 当前站点是否整体退化为内置浏览器
  bool get browserOnlyMode => _currentSite.pages.browserOnly;
  int get staggerInterval => _staggerInterval;

  /// 站点正文字数上限（当前站点）
  int get postMaxLength => _currentSite.content.postMaxLength;

  /// 当前站点的个人空间数据源覆盖
  String get spaceSource => _currentSite.content.spaceSource;
  int get avatarCacheDays => _avatarCacheDays;
  int get emojiCacheDays => _emojiCacheDays;
  int get imageCacheDays => _imageCacheDays;
  int get medalCacheDays => _medalCacheDays;

  /// 帖子自动缓存过期天数（下限 1）
  int get threadCacheDays => _threadCacheDays;

  /// 帖子自动缓存总开关（默认开启）
  bool get threadCacheEnabled => _threadCacheEnabled;

  /// 每帖保留的自动缓存正文版本数
  int get threadCacheMaxVersions => _threadCacheMaxVersions;

  /// 单帖最大缓存大小（KB）
  int get threadCacheMaxKB => _threadCacheMaxKB;
  ThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get isPureBlackTheme => _isPureBlackTheme;
  bool get showAvatars => _showAvatars;
  AvatarSizeMode get avatarSizeMode => _avatarSizeMode;
  int get maxImageWidth => _maxImageWidth;

  /// 分享图正文最大高度（逻辑像素）：生成页勾选「截断」时生效
  int get shareImageMaxHeight => _shareImageMaxHeight;

  /// 分享图是否只输出正文（不含作者信息 / 评分、页脚与定位信息）
  bool get shareImageContentOnly => _shareImageContentOnly;

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

  /// 上次检查更新的时间（Unix 秒，0 = 从未检查）
  int get lastUpdateCheckAt => _lastUpdateCheckAt;

  String get creditFormula => _currentSite.creditFormula;

  List<ManagedItem> get shortcutLinks =>
      List.unmodifiable(_currentSite.shortcutLinks);

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

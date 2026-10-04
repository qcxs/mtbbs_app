part of 'settings_provider.dart';

/// [SettingsProvider] 的整体加载与通用设置写操作
extension SettingsPersistence on SettingsProvider {
  // ==================== 加载 ====================

  Future<void> load() async {
    // 基本数值设置
    _fontSize = (await _db.getSettingDouble('fontSize')) ?? 16;
    _currentSiteIndex = (await _db.getSettingInt('currentSiteIndex')) ?? 0;
    _defaultTabIndex = ((await _db.getSettingInt('defaultTabIndex')) ?? 0)
        .clamp(0, 3);

    _autoDetectUrls = (await _db.getSettingBool('autoDetectUrls')) ?? true;
    // 浏览器仿真头：此处在 ApiService.init 之前，只登记开关值，init 会读它
    _simulateBrowserHeaders =
        (await _db.getSettingBool('simulateBrowserHeaders')) ?? true;
    applyBrowserHeaders(_simulateBrowserHeaders);
    _interstitialAutoVerify =
        (await _db.getSettingBool('interstitialAutoVerify')) ?? true;
    // 页面接管：被关闭的页面 id（JSON 数组），默认空 = 全部走 App 页
    final fallbackJson = await _db.getSetting('browserFallbackPages');
    if (fallbackJson != null && fallbackJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(fallbackJson) as List<dynamic>;
        _browserFallbackPages = parsed.map((e) => e.toString()).toSet();
      } catch (_) {}
    }
    applyDisabledAppPages(_browserFallbackPages);
    // 终极降级开关（逃生阀）：默认关
    _browserOnlyMode = (await _db.getSettingBool('browserOnlyMode')) ?? false;
    applyBrowserOnlyMode(_browserOnlyMode);
    // 个人空间页数据源覆盖（'' = 跟随浏览模式），请求发起前登记
    _spaceSource = (await _db.getSetting('spaceSource')) ?? '';
    space_api.applySpaceSourceOverride(_spaceSource);
    _staggerInterval = (await _db.getSettingInt('staggerInterval')) ?? 40;
    // 缓存过期天数（默认取自 cache.json，无配置或 JSON 错误时为 1 天）
    final cacheDefaults = DefaultConfig.instance.cacheExpireDays;
    _avatarCacheDays =
        (await _db.getSettingInt('avatarCacheDays')) ?? cacheDefaults.avatar;
    _emojiCacheDays =
        (await _db.getSettingInt('emojiCacheDays')) ?? cacheDefaults.emoji;
    _imageCacheDays =
        (await _db.getSettingInt('imageCacheDays')) ?? cacheDefaults.image;
    _medalCacheDays =
        (await _db.getSettingInt('medalCacheDays')) ?? cacheDefaults.medal;
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
        (await _db.getCreditFormula(SiteStore.instance.host)) ??
        SettingsProvider.defaultFormula;

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

    // 导读 Tab（完整列表含可见性；兼容旧版 tabOrder 逗号字符串迁移）
    final guideJson = await _db.getSetting('guideTabs');
    if (guideJson != null && guideJson.isNotEmpty) {
      try {
        final loaded = ManagedItem.decodeList(
          guideJson,
        ).where((e) => SettingsProvider.tabLabels.containsKey(e.id)).toList();
        if (loaded.isNotEmpty) _guideTabs = loaded;
      } catch (_) {}
    } else {
      final legacy = await _db.getSetting('tabOrder');
      if (legacy != null && legacy.isNotEmpty) {
        final visible = legacy.split(',').toSet();
        _guideTabs = [
          for (final id in _defaultTabIds)
            ManagedItem(
              id: id,
              name: SettingsProvider.tabLabels[id] ?? id,
              visible: visible.contains(id),
            ),
        ];
      }
    }

    // 首页区块（顺序/显隐/默认展开；缺失或损坏时回退默认）
    final homeJson = await _db.getSetting('homeSections');
    if (homeJson != null && homeJson.isNotEmpty) {
      try {
        final loaded = ManagedItem.decodeList(
          homeJson,
        ).where((e) => _homeSectionIds.contains(e.id)).toList();
        if (loaded.isNotEmpty) _homeSections = loaded;
      } catch (_) {}
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
        // 只保留仍可配置的项：老版本可能存过已被移出清单的标签
        // （如 strikethrough —— 删除线带语义，已不再允许禁用），
        // 否则它会留在集合里继续生效，而用户在 UI 上已无处取消。
        _disabledBbcodeTags = parsed
            .map((e) => e.toString())
            .where(bbcodeStyleTagIds.contains)
            .toSet();
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
        // 剪掉无效 id 的快捷键；用户自定义模板项的 id 也保留
        _toolbarShortcuts.removeWhere(
          (key, _) =>
              !isValidToolbarItemId(key) &&
              !_toolbarItems.any((e) => e.id == key),
        );
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

    // 头像尺寸策略（默认 middle，未知值回退 middle）
    _avatarSizeMode = AvatarSizeMode.fromValue(
      await _db.getSetting('avatarSizeMode'),
    );

    // 宽屏时帖子图片最大宽度（默认 600）
    _maxImageWidth = (await _db.getSettingInt('maxImageWidth')) ?? 600;

    // 编辑器启动自检
    _editorStartupCheck =
        (await _db.getSettingBool('editorStartupCheck')) ?? true;

    // 启动时自动检查更新
    _autoCheckUpdate = (await _db.getSettingBool('autoCheckUpdate')) ?? true;
    _skippedUpdateVersion =
        (await _db.getSetting('skippedUpdateVersion')) ?? '';

    _notify();
  }

  // ==================== 通用设置写入 ====================

  /// 开关浏览器仿真头（Referer / Accept），立即作用于后续请求
  Future<void> setSimulateBrowserHeaders(bool enabled) async {
    _simulateBrowserHeaders = enabled;
    applyBrowserHeaders(enabled);
    await _db.setSettingBool('simulateBrowserHeaders', enabled);
    _notify();
  }

  /// 开关"非论坛页自动弹浏览器验证"（人机验证 / 防火墙）
  Future<void> setInterstitialAutoVerify(bool enabled) async {
    _interstitialAutoVerify = enabled;
    await _db.setSettingBool('interstitialAutoVerify', enabled);
    _notify();
  }

  /// 开关"启动时自动检查更新"（仅正式版生效）
  Future<void> setAutoCheckUpdate(bool enabled) async {
    _autoCheckUpdate = enabled;
    await _db.setSettingBool('autoCheckUpdate', enabled);
    _notify();
  }

  /// 设置跳过的版本 tag（'' = 取消跳过）
  Future<void> setSkippedUpdateVersion(String tag) async {
    _skippedUpdateVersion = tag;
    await _db.setSetting('skippedUpdateVersion', tag);
    _notify();
  }

  /// 开启 / 关闭某页的 App 接管（关闭后该页无论从哪进入都走内置浏览器）
  Future<void> setAppPageEnabled(String id, bool enabled) async {
    if (enabled) {
      _browserFallbackPages.remove(id);
    } else {
      _browserFallbackPages.add(id);
    }
    applyDisabledAppPages(_browserFallbackPages);
    await _db.setSetting(
      'browserFallbackPages',
      jsonEncode(_browserFallbackPages.toList()),
    );
    _notify();
  }

  /// 开关"整体退化为内置浏览器"（逃生阀）。
  ///
  /// 开启后所有路由（除内置浏览器与设置）都改走 WebView；设置必须保持可达，
  /// 否则用户无法自行关闭（浏览器页内另有设置入口）。
  Future<void> setBrowserOnlyMode(bool enabled) async {
    _browserOnlyMode = enabled;
    applyBrowserOnlyMode(enabled);
    await _db.setSettingBool('browserOnlyMode', enabled);
    _notify();
  }

  /// 设置个人空间页数据源：'' 跟随浏览模式 / 'mobile' / 'desktop'
  Future<void> setSpaceSource(String value) async {
    _spaceSource = value;
    space_api.applySpaceSourceOverride(value);
    await _db.setSetting('spaceSource', value);
    _notify();
  }

  Future<void> setStaggerInterval(int ms) async {
    _staggerInterval = ms.clamp(20, 300);
    await _db.setSettingInt('staggerInterval', _staggerInterval);
    _notify();
  }

  Future<void> setAvatarCacheDays(int days) async {
    _avatarCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('avatarCacheDays', _avatarCacheDays);
    _notify();
  }

  Future<void> setEmojiCacheDays(int days) async {
    _emojiCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('emojiCacheDays', _emojiCacheDays);
    _notify();
  }

  Future<void> setImageCacheDays(int days) async {
    _imageCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('imageCacheDays', _imageCacheDays);
    _notify();
  }

  Future<void> setMedalCacheDays(int days) async {
    _medalCacheDays = days.clamp(-1, 365);
    await _db.setSettingInt('medalCacheDays', _medalCacheDays);
    _notify();
  }

  Future<void> setMinSnapshotWordCount(int v) async {
    _minSnapshotWordCount = v.clamp(1, 100);
    await _db.setSettingInt('minSnapshotWordCount', _minSnapshotWordCount);
    _notify();
  }

  Future<void> setAutoSaveInterval(int seconds) async {
    _autoSaveInterval = seconds.clamp(5, 300);
    await _db.setSettingInt('autoSaveInterval', _autoSaveInterval);
    _notify();
  }

  Future<void> setMaxAutoSnapshots(int v) async {
    _maxAutoSnapshots = v.clamp(1, 50);
    await _db.setSettingInt('maxAutoSnapshots', _maxAutoSnapshots);
    _notify();
  }

  Future<void> setDefaultTabIndex(int index) async {
    _defaultTabIndex = index.clamp(0, 3);
    await _db.setSettingInt('defaultTabIndex', _defaultTabIndex);
    _notify();
  }

  Future<void> setHistoryFormatThread(String format) async {
    _historyFormatThread = format;
    await _db.setSetting('historyFormat_thread', format);
    _notify();
  }

  Future<void> setHistoryFormatUser(String format) async {
    _historyFormatUser = format;
    await _db.setSetting('historyFormat_user', format);
    _notify();
  }

  Future<void> setHistoryTitleFormatThread(String format) async {
    _historyTitleFormatThread = format;
    await _db.setSetting('historyTitleFormat_thread', format);
    _notify();
  }

  Future<void> setHistoryTitleFormatUser(String format) async {
    _historyTitleFormatUser = format;
    await _db.setSetting('historyTitleFormat_user', format);
    _notify();
  }

  Future<void> setHistoryTitleFormatMythread(String format) async {
    _historyTitleFormatMythread = format;
    await _db.setSetting('historyTitleFormat_mythread', format);
    _notify();
  }

  Future<void> setHistoryTitleFormatReply(String format) async {
    _historyTitleFormatReply = format;
    await _db.setSetting('historyTitleFormat_reply', format);
    _notify();
  }
}

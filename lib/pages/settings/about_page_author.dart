part of 'about_page.dart';

/// 作者资料与开发者选项解锁 —— 加载开发者资料、图标旋转与连点解锁。
extension on _AboutPageState {
  /// 开发者空间地址（固定指向作者所属站点）
  String get _authorSpaceUrl =>
      '${SessionRegistry.instance.baseUrlForHost(AboutPage.authorSiteHost) ?? AboutPage.authorBaseUrl}'
      '/home.php?mod=space&uid=${AboutPage.authorUid}&do=profile';

  /// 等级展示文本：优先「等级 + 头衔」，都为空时退回用户组
  String get _authorLevelText {
    final a = _author;
    if (a == null) return '';
    final parts = [
      a.level,
      a.customTitle,
    ].where((s) => s.trim().isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : a.userGroup;
  }

  /// 签名展示文本：签名是 BBCode，这里去掉标记只留纯文本（卡片仅两行）
  String get _authorSignatureText {
    final a = _author;
    if (a == null) return '';
    return a.signature.replaceAll(RegExp(r'\[[^\[\]]*\]'), '').trim();
  }

  /// 加载开发者资料：先读持久化缓存，缺失时按 UID 抓取一次并写回
  Future<void> _loadAuthor() async {
    // 固定本次加载所用的站点与 UID，避免加载途中切换站点导致串号
    final host = AboutPage.authorSiteHost;
    final uid = AboutPage.authorUid;
    _authorLoadedHost = host;
    final cached = await SettingsRepository.instance.getSiteState(
      host,
      'about_author',
    );
    if (cached != null && cached.isNotEmpty) {
      try {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        if (mounted) _setState(() => _author = UserProfile.fromMap(map));
        return;
      } catch (_) {
        // 缓存损坏则走网络重新获取
      }
    }
    try {
      // 作者资料固定在作者所属站点获取，携带的 Cookie/Referer 不会跟着当前站点漂移。
      // 当前站点必须用全局 Dio（带当前登录账号）：scopedDio 默认是游客罐，
      // 而个人空间页对游客可能直接返回拦截页（见 docs/27 的"当前站点不建作用域会话"）。
      final isCurrentSite = host == SiteStore.instance.host;
      final dio = isCurrentSite
          ? ApiService().dio
          : await ApiService().scopedDio(
              host: host,
              baseUrl:
                  SessionRegistry.instance.baseUrlForHost(host) ??
                  AboutPage.authorBaseUrl,
              account: SessionRegistry.instance.defaultAccountFor(host),
            );
      final raw = await space_api.getUserProfile(
        dio,
        uid: uid,
        // 作者资料是「进入关于页」附带的非关键请求：命中人机验证 / 防火墙时
        // 不能弹全局验证页（会盖在关于页上、且此请求并非用户主动发起）。
        // 打上「已处理」标记，让拦截器直接返回原响应，静默失败保留占位即可。
        options: Options(extra: {kInterstitialHandledFlag: true}),
      );
      if (raw['success'] != true || raw['profile'] == null) return;
      final profile = UserProfile.fromMap(
        (raw['profile'] as Map).cast<String, dynamic>(),
      );
      await SettingsRepository.instance.setSiteState(
        host,
        'about_author',
        jsonEncode(profile.toMap()),
      );
      if (mounted) _setState(() => _author = profile);
    } catch (e) {
      AppLogger.w('ABOUT', '作者信息获取失败: $e');
    }
  }

  /// 随机方向转 0.5~1.5 圈
  void _spinIcon() {
    final delta = 0.5 + _random.nextDouble();
    _setState(() => _turns += _random.nextBool() ? delta : -delta);
  }

  /// 图标点击：已解锁开发者选项 → 直接进入；未解锁 → 转个圈并累计次数，满
  /// [_unlockNeedTaps] 次解锁（相邻两次超过 2 秒则重新计数）。
  void _onIconTap() {
    final settings = context.read<SettingsProvider>();
    if (settings.developerMode) {
      context.push('/settings/developer');
      return;
    }
    _spinIcon();
    final now = DateTime.now();
    if (_lastUnlockTapAt == null ||
        now.difference(_lastUnlockTapAt!) > const Duration(seconds: 2)) {
      _unlockTaps = 0;
    }
    _lastUnlockTapAt = now;
    _unlockTaps++;
    final left = _AboutPageState._unlockNeedTaps - _unlockTaps;
    if (left > 0) {
      showToast('再点击 $left 次进入开发者选项');
    } else {
      _unlockTaps = 0;
      settings.setDeveloperMode(true);
      showToast('已解锁开发者选项，再次点击图标即可进入');
    }
  }
}

part of 'browser_page.dart';

/// [BrowserPage] 的交互/回调逻辑。
///
/// 方法无法跨文件拆，故以 extension 承载：扩展可访问宿主私有成员，
/// 宿主类体内也可无前缀直接调用。受保护的 setState 改用宿主预留的 _setState。
extension _BrowserPageActions on _BrowserPageState {
  // ==================== 关闭 / 逃生 ====================

  /// 关闭浏览器：能退则退；**无路可退时去设置**。
  ///
  /// "全局降级为浏览器"模式下浏览器就是首屏，此时 pop 会把唯一路由弹掉（黑屏 /
  /// 卡死），且用户也无法改回开关——因此退化到设置页，保证永远出得来。
  void _closeBrowser() {
    if (context.canPop()) {
      Navigator.of(context).pop();
    } else {
      context.push('/settings');
    }
  }

  // ==================== Cookie 同步（按浏览的站点） ====================
  //
  // 内置浏览器不再"永远使用全局当前站点"的 Cookie：它按**当前页面的宿主**选择
  // 身份 —— 当前站点用 `AuthProvider` 的活跃账号，其它已添加站点用该站默认账号
  // （`SessionRegistry`）。WebView 的 CookieManager 是平台级单例，所以注入/回流
  // 都必须显式限定在目标站点（`clearCookiesForHost` 只清该 host）。

  /// 某宿主对应的站点 baseUrl（未添加的站点返回 null）
  String? _baseUrlForHost(String? host) {
    if (host == null || host.isEmpty) return null;
    if (host == SiteStore.instance.host) return SiteStore.instance.baseUrl;
    return SessionRegistry.instance.baseUrlForHost(host);
  }

  /// 某宿主"当前应该用的账号"的 Cookie 串（未登录 / 游客返回空串）
  Future<String> _cookieStringForHost(String host) async {
    if (!mounted) return '';
    if (host == SiteStore.instance.host) {
      return context.read<AuthProvider>().currentCookieString ?? '';
    }
    final session = SessionRegistry.instance.resolve(host);
    if (session == null) return '';
    final jar = ApiService().scopedJar(
      host: host,
      account: session.accountName,
    );
    if (jar == null) return '';
    final cookies = await jar.loadForRequest(Uri.parse(session.baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  /// 把某站点的账号 Cookie 注入 WebView（先清该站点旧 Cookie）。
  ///
  /// 清理与注入必须互相独立：清理失败绝不能连累注入，否则浏览器会显示成"未登录"
  /// （见 docs/07 #67）。
  Future<void> _syncCookiesToWebView(String? host) async {
    final baseUrl = _baseUrlForHost(host);
    if (host == null || baseUrl == null) return;

    String cookieStr = '';
    try {
      cookieStr = await _cookieStringForHost(host);
    } catch (e) {
      AppLogger.w('PAGE', '读取 $host 账号 cookie 失败: $e');
    }
    try {
      await clearCookiesForHost(baseUrl);
    } catch (e) {
      AppLogger.w('PAGE', 'clear webview cookies failed: $e');
    }
    if (cookieStr.isEmpty) return;
    try {
      await syncCookieStringToWebView(cookieStr, baseUrl);
    } catch (e) {
      AppLogger.w('PAGE', 'inject webview cookies failed: $e');
    }
  }

  /// WebView → 对应站点的 CookieJar：把浏览器里新增/刷新的 Cookie 回流给 App。
  ///
  /// 场景：在内置浏览器里过了验证码、重新登录，或站点刷新了会话 Cookie——
  /// 这些 Cookie 只落在 WebView，不回流的话 App 后续请求仍带旧 Cookie，
  /// 表现为「浏览器里验证通过了，App 里还是失败」。
  ///
  /// 当前站点写全局活跃罐；其它已添加站点写它自己的作用域罐（该站默认账号）。
  /// 只在离开该 host 时调用（换站点 / 跳回 App / 关闭浏览器），不做逐页同步。
  Future<void> _syncCookiesBackForHost(String? host) async {
    final baseUrl = _baseUrlForHost(host);
    if (host == null || baseUrl == null) return;
    try {
      final jar = host == SiteStore.instance.host
          ? ApiService().activeCookieJar
          : ApiService().scopedJar(
              host: host,
              account: SessionRegistry.instance.resolve(host)?.accountName,
            );
      if (jar == null) return;
      await syncWebViewCookiesToJar(jar: jar, baseUrl: baseUrl);
    } catch (e) {
      AppLogger.w('PAGE', 'cookie 回流失败: $e');
    }
  }

  /// 浏览的宿主发生变化：先把上一个站点的 Cookie 回流，再给新站点注入身份。
  ///
  /// 只对**已添加站点**生效；跳到未添加的站点时（`_syncedHost = null`）保持
  /// WebView 原有 Cookie，不做任何注入/清理。
  Future<void> _onHostChanged(String newHost) async {
    if (newHost.isEmpty || newHost == _syncedHost) return;
    final previous = _syncedHost;
    // 先占位：`onLoadStop` 与 `onUpdateVisitedHistory` 可能同时触发，
    // 不能让两次调用都走一遍"清空 + 注入"。
    _syncedHost = SessionRegistry.instance.siteForHost(newHost) == null
        ? null
        : newHost;
    if (previous != null) await _syncCookiesBackForHost(previous);
    if (_syncedHost != null) await _syncCookiesToWebView(newHost);
  }

  /// 通过 URL 编辑框导航：先换好目标站点的 Cookie，再加载。
  Future<void> _navigateTo(String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host != _syncedHost) await _onHostChanged(host);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ==================== 账号切换 ====================

  /// 切换账号 —— **按当前浏览页所属的站点**列出该站账号，不再绑定全局当前站点。
  ///
  /// - 浏览当前站点：走 `AuthProvider`（切换后全局活跃账号随之改变）；
  /// - 浏览其它已添加站点：走 `SessionRegistry`，选中项写回该站「默认用户」，
  ///   浏览器与 App 内的跨站页面（`site=` 会话）因此保持一致；
  /// - 未添加的站点：不展示入口（调用方已隐藏），这里再兜一层。
  Future<void> _showAccountSwitch() async {
    final host = _host;
    if (SessionRegistry.instance.siteForHost(host) == null) return;
    final isCurrent = host == SiteStore.instance.host;

    final options = <_AccountOption>[];
    var activeIndex = -1;
    if (isCurrent) {
      final auth = context.read<AuthProvider>();
      for (final a in auth.accounts) {
        options.add(_AccountOption(a.username, a.uid, a.uid == '0'));
      }
      activeIndex = auth.activeIndex;
    } else {
      options.add(const _AccountOption('游客', '0', true));
      for (final a in SessionRegistry.instance.accountsFor(host)) {
        options.add(_AccountOption(a.username, a.uid, false));
      }
      final defaultAccount = SessionRegistry.instance.defaultAccountFor(host);
      activeIndex = defaultAccount == null || defaultAccount.isEmpty
          ? 0
          : options.indexWhere(
              (o) => !o.isGuest && o.username == defaultAccount,
            );
      if (activeIndex < 0) activeIndex = 0;
    }

    if (options.isEmpty) {
      if (!mounted) return;
      showToast('当前站点无可用账号');
      return;
    }

    final siteName = SessionRegistry.instance.siteNameForHost(host);
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          // 账号数量不定：整体可滚动，避免账号一多就溢出（默认弹层高度上限为 9/16 屏高）
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '切换账号',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          siteName,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ...List.generate(options.length, (i) {
                  final o = options[i];
                  final isActive = i == activeIndex;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: o.isGuest
                        ? CircleAvatar(
                            radius: 18,
                            backgroundColor: cs.surfaceContainerHigh,
                            child: Icon(
                              Icons.person_outline,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : UserAvatar(
                            uid: o.uid,
                            nickname: o.username,
                            radius: 18,
                            siteHost: host,
                            tapAction: AvatarTapAction.none,
                          ),
                    title: Text(
                      o.isGuest ? '游客' : o.username,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: o.isGuest
                        ? null
                        : Text(
                            'UID ${o.uid}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                    trailing: isActive
                        ? Icon(Icons.check, size: 18, color: cs.primary)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(i),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || result == activeIndex || !mounted) return;
    final picked = options[result];

    if (isCurrent) {
      final auth = context.read<AuthProvider>();
      final index = auth.accounts.indexWhere((a) => a.uid == picked.uid);
      if (index < 0) return;
      await auth.switchTo(index);
    } else {
      // 选中项成为该站「默认用户」：浏览器与 App 的跨站页面共用同一个身份
      await SessionRegistry.instance.setDefaultAccount(
        host,
        picked.isGuest ? null : picked.username,
      );
    }
    if (!mounted) return;
    _syncedHost = host;
    await _syncCookiesToWebView(host);
    if (!mounted) return;
    _setState(() {}); // 底栏登录态图标跟着变
    _controller?.reload();
  }

  // ==================== URL 编辑弹窗 ====================

  Future<void> _showUrlEditor() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _UrlEditorDialog(initialUrl: _currentUrl),
    );

    if (result != null && result != _currentUrl && result.isNotEmpty) {
      final uri = Uri.tryParse(result);
      final finalUrl = (uri != null && uri.hasScheme)
          ? result
          : 'https://$result';
      // 走统一入口：跨站跳转前先换好目标站点的 Cookie
      await _navigateTo(finalUrl);
    }
  }

  // ==================== 更多菜单操作 ====================

  Future<void> _copyUrl() async {
    final ok = await ClipboardHelper.write(_currentUrl);
    if (mounted) {
      showToast(
        ok ? '链接已复制' : '复制到剪切板失败',
        duration: const Duration(seconds: 1),
      );
    }
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '确认清空',
      message: '确定要清除浏览器缓存吗？\n将清空网页资源缓存与本地存储（所有站点），以及当前站点的 Cookie。',
      confirmText: '清空',
    );
    if (confirmed != true || !mounted) return;
    // 资源缓存 / WebStorage 是 WebView 配置级的，无法按站点隔离；Cookie 可以。
    // 因此这里不再用 clearAllCache + deleteAllCookies 的"全清"组合，避免把
    // 其它站点在 WebView 的登录态一起清掉。
    try {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
    } catch (e) {
      AppLogger.w('PAGE', 'clear webview cache failed: $e');
    }
    try {
      await WebStorageManager.instance().deleteAllData();
    } catch (e) {
      AppLogger.w('PAGE', 'clear web storage failed: $e');
    }
    final baseUrl = _baseUrlForHost(_host);
    if (baseUrl != null) await clearCookiesForHost(baseUrl);
    if (mounted) {
      showToast('浏览器缓存已清空');
    }
  }

  /// 切换桌面模式：改 UA 之外，还要删掉 Discuz 的「浏览方式」Cookie。
  ///
  /// 站点模板的优先级是 `?mobile=` / `*_mobile` Cookie **高于** UA（docs/07 #72）：
  /// 只改 UA 时页面仍按旧模板渲染，表现为"切了桌面模式还是移动版"。
  Future<void> _toggleDesktopMode() async {
    final next = !_desktopMode;
    _setState(() => _desktopMode = next);
    final baseUrl = _baseUrlForHost(_syncedHost ?? _host);
    if (baseUrl != null) {
      try {
        await clearBrowseModeCookiesForHost(baseUrl);
      } catch (e) {
        AppLogger.w('PAGE', 'clear browse-mode cookie failed: $e');
      }
    }
    await _controller?.setSettings(
      settings: InAppWebViewSettings(
        userAgent: next ? Site.uaPc : Site.uaAndroid,
      ),
    );
    _controller?.reload();
  }

  /// 用 App 本地页面打开当前 URL（如果支持）
  ///
  /// 落地决策统一交给 [UrlRouter.resolveTarget]：属于当前站点的页面直接进 App；
  /// 属于其它**已配置且已迁移**的站点（如 52pojie）时自动带上 `site=`，以该站
  /// 默认账号/游客身份只读打开；解析不出才落到内置浏览器兜底。
  Future<void> _openInApp() async {
    if (!mounted) return;
    final target = UrlRouter.resolveTarget(_currentUrl);
    if (target == null) return;
    // 落到内置浏览器兜底 = 解析不出 App 页面；此时已经在内置浏览器里，给出提示即可
    if (target.startsWith('/browser?')) {
      showToast('不支持在当前页面打开：${UrlRouter.parse(_currentUrl).label}');
      return;
    }
    // 与 URL 拦截一致：先把浏览器里刚拿到的 Cookie 回流给 App，再进 App 页。
    // 否则会出现「浏览器里登录了 / 过了验证，App 页里还是未登录」。
    await _syncCookiesBackForHost(_syncedHost);
    if (!mounted) return;
    context.push(target);
  }

  // ==================== WebView 回调 ====================

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    // 新的一次主框架加载开始：先把上一次的错误覆盖层收掉。
    // 不能放在 onLoadStop —— 加载失败时它同样会触发，会把错误又清掉。
    if (_loadError != null) _setState(() => _loadError = null);
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    final urlStr = url?.toString() ?? '';
    _setState(() {
      _currentUrl = urlStr;
    });
    _refreshNavState(controller);
    _syncForUrl(urlStr);
  }

  /// 历史项变化（重定向 / hash / SPA 路由）时同步标题栏与前进后退状态。
  ///
  /// 只靠 `onLoadStop` 会在上述场景滞后：地址栏显示旧地址、返回键状态不更新。
  void _onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) {
    if (!mounted || url == null) return;
    final urlStr = url.toString();
    if (urlStr != _currentUrl) {
      _setState(() => _currentUrl = urlStr);
    }
    _refreshNavState(controller);
    _syncForUrl(urlStr);
  }

  /// 地址变化后按站点换 Cookie（同 host 内跳转会被 `_onHostChanged` 直接跳过）
  void _syncForUrl(String urlStr) {
    final host = Uri.tryParse(urlStr)?.host ?? '';
    if (host.isNotEmpty) unawaited(_onHostChanged(host));
  }

  void _refreshNavState(InAppWebViewController controller) {
    controller.canGoBack().then((v) {
      if (mounted) _setState(() => _canGoBack = v);
    });
    controller.canGoForward().then((v) {
      if (mounted) _setState(() => _canGoForward = v);
    });
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    _setState(() => _progress = progress / 100);
  }

  /// 主框架加载失败：覆盖错误视图 + 重试（不销毁 WebView，保留前进/后退历史）
  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (!mounted || request.isForMainFrame != true) return;
    // 被我们主动取消的导航（如"拦截到 App"）会以 CANCELLED 形式回传，
    // 那不是加载失败，不能盖错误页。
    if (error.type == WebResourceErrorType.CANCELLED) return;
    _setState(() => _loadError = error.description);
  }

  void _onReceivedHttpError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceResponse errorResponse,
  ) {
    if (!mounted || request.isForMainFrame != true) return;
    final code = errorResponse.statusCode ?? 0;
    // 只在 5xx 覆盖：403/404 等页面本身可能就是站点给的提示（如人机验证挑战页），
    // 盖掉它反而让用户没法在浏览器里完成验证。
    if (code < 500) return;
    _setState(() => _loadError = 'HTTP $code');
  }

  void _retry() {
    _setState(() => _loadError = null);
    _controller?.reload();
  }
}

/// 账号切换弹层里的一个选项（当前站点 / 其它站点统一成同一种展示模型）
class _AccountOption {
  final String username;
  final String uid;
  final bool isGuest;

  const _AccountOption(this.username, this.uid, this.isGuest);
}

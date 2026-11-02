part of 'browser_page.dart';

/// [BrowserPage] 的构建逻辑。
///
/// `build` 是接口成员不能整体搬走：宿主保留 `build => _buildPage(context)`，
/// 原体改名 `_buildPage` 承载于此。
extension _BrowserPageBuild on _BrowserPageState {
  // ==================== UI ====================

  Widget _buildPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!AppCapabilities.isAvailable(AppCapability.webView)) {
      return Scaffold(
        appBar: AppBar(title: const Text('内置浏览器')),
        body: const PageErrorWidget(
          message: '当前平台不支持内置浏览器。\n请在系统浏览器中打开该链接。',
        ),
      );
    }

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _controller?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          surfaceTintColor: cs.surface,
          // 退出浏览器（后退/前进在底栏，故此处固定为退出，不再兼作后退）
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '退出浏览器',
            onPressed: _closeBrowser,
          ),
          title: GestureDetector(
            onTap: _showUrlEditor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _host.isNotEmpty ? _host : '浏览器',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          actions: [
            // 刷新
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '刷新',
              onPressed: () => _controller?.reload(),
            ),
            // URL 拦截 — 可点击切换，通过图标状态了解当前是否启用
            IconButton(
              icon: Icon(
                _urlInterceptEnabled ? Icons.shield : Icons.shield_outlined,
                size: 20,
              ),
              tooltip: _urlInterceptEnabled ? 'URL 拦截已启用' : 'URL 拦截已禁用',
              onPressed: () =>
                  _setState(() => _urlInterceptEnabled = !_urlInterceptEnabled),
            ),
            // 更多菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                switch (v) {
                  case 'settings':
                    context.push('/settings');
                  case 'desktopMode':
                    _toggleDesktopMode();
                  case 'clearCache':
                    _clearCache();
                  case 'copyUrl':
                    _copyUrl();
                  case 'openExternal':
                    _openInExternalBrowser();
                  case 'exit':
                    _closeBrowser();
                }
              },
              itemBuilder: (_) => [
                // —— 当前页视图 ——
                PopupMenuItem(
                  value: 'desktopMode',
                  child: Row(
                    children: [
                      const Icon(Icons.desktop_windows, size: 18),
                      const SizedBox(width: 8),
                      const Text('桌面模式'),
                      const Spacer(),
                      if (_desktopMode)
                        Icon(Icons.check, size: 16, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                // —— 当前页操作 ——
                const PopupMenuItem(
                  value: 'copyUrl',
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 18),
                      SizedBox(width: 8),
                      Text('复制链接'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'openExternal',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_new, size: 18),
                      SizedBox(width: 8),
                      Text('外部浏览器打开'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                // —— 数据 ——
                const PopupMenuItem(
                  value: 'clearCache',
                  child: Row(
                    children: [
                      Icon(Icons.cached, size: 18),
                      SizedBox(width: 8),
                      Text('清除缓存'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                // —— 应用 ——
                // 设置入口必须常驻菜单：开启「全部改用内置浏览器」后浏览器即首屏，
                // 没有这个入口用户会被锁死在浏览器里，无法关回开关。
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('设置'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'exit',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, size: 18),
                      SizedBox(width: 8),
                      Text('退出浏览器'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: _progress > 0 && _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress,
                    color: cs.onSurfaceVariant,
                  ),
                )
              : null,
        ),
        body: _buildWebView(),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  // ==================== WebView ====================

  Widget _buildWebView() {
    if (!_cookiesReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        InAppWebView(
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            // 默认移动 UA；PC 专属页（在线用户/小黑屋）由调用方以 ?ua=pc 传入桌面模式
            userAgent: _desktopMode ? Site.uaPc : Site.uaAndroid,
            supportZoom: true,
          ),
          initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
          onWebViewCreated: (controller) {
            _controller = controller;
          },
          onLoadStart: _onLoadStart,
          onLoadStop: _onLoadStop,
          onUpdateVisitedHistory: _onUpdateVisitedHistory,
          onProgressChanged: _onProgressChanged,
          onReceivedError: _onReceivedError,
          onReceivedHttpError: _onReceivedHttpError,
          // 附件 / 图片下载交给外部浏览器（WebView 自身不处理下载，点了会毫无反应）
          onDownloadStartRequest: (controller, request) async {
            try {
              await launchUrl(
                request.url,
                mode: LaunchMode.externalApplication,
              );
            } catch (e) {
              AppLogger.w('PAGE', 'download open failed: $e');
            }
          },
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final url = navigationAction.request.url?.toString() ?? '';
            if (url.isEmpty) return NavigationActionPolicy.ALLOW;

            final uri = Uri.tryParse(url);
            if (uri == null) return NavigationActionPolicy.ALLOW;

            // 非 http(s) 链接（intent:// / mailto: / tg:// / weixin:// …）交给系统，
            // 否则 WebView 只会显示一个打不开的错误页。
            const webSchemes = {
              'http',
              'https',
              'about',
              'data',
              'blob',
              'file',
            };
            final scheme = uri.scheme.toLowerCase();
            if (!webSchemes.contains(scheme)) {
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                AppLogger.w('PAGE', 'open external scheme $scheme failed: $e');
              }
              return NavigationActionPolicy.CANCEL;
            }

            // 跳到另一个「已添加站点」时，先换成该站账号的 Cookie 再放行，
            // 否则页面会带着上一个站点的身份去请求。
            if (uri.host != _syncedHost &&
                SessionRegistry.instance.siteForHost(uri.host) != null) {
              await _onHostChanged(uri.host);
            }

            // 降级模式下不再拦截：否则"回退到浏览器 → 又被 App 接管"会来回推页面
            if (!_urlInterceptEnabled || browserOnlyMode) {
              return NavigationActionPolicy.ALLOW;
            }

            // 非当前站点的链接放行：跨站页面留在浏览器里，
            // 需要进 App 时用底栏「在 App 中打开」。
            final baseHost = Uri.tryParse(SiteStore.instance.baseUrl)?.host;
            if (baseHost != null && uri.host != baseHost) {
              return NavigationActionPolicy.ALLOW;
            }

            // 匹配 App 路由成功则拦截并在 App 中打开
            final result = UrlRouter.parse(url);
            if (result.appPath != null && mounted) {
              // 浏览器容器还留在栈上、不会走 dispose，这里先回流一次
              await _syncCookiesBackForHost(_syncedHost);
              if (!mounted) return NavigationActionPolicy.ALLOW;
              showToast('拦截：已在 App 中打开', duration: const Duration(seconds: 1));
              context.push(result.appPath!);
              return NavigationActionPolicy.CANCEL;
            }

            return NavigationActionPolicy.ALLOW;
          },
        ),
        // 加载失败覆盖层：不销毁 WebView（销毁会丢掉前进/后退历史）
        if (_loadError != null)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: PageErrorWidget(
                message: _loadError!,
                onRetry: _retry,
                showBack: false,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    // 账号切换按「浏览器当前页所属站点」工作：只要该站点已添加就展示入口，
    // 列出的是**该站自己**的账号（当前站点走 AuthProvider，其它站点走 SessionRegistry）。
    final browsedSite = SessionRegistry.instance.siteForHost(_host);
    final isCurrentSite = _host == SiteStore.instance.host;
    final isLoggedIn = isCurrentSite
        ? auth.isLoggedIn
        : SessionRegistry.instance.defaultAccountFor(_host) != null;
    // 「在 App 中打开」：唯一决策点仍是 resolveTarget（跨站点已迁移页面自动带 site=）；
    // 再走一次 appPageRedirect —— 页面接管被关闭 / 站点已降级时按钮不该出现，
    // 否则点下去只会被 redirect 原样送回浏览器。
    final target = UrlRouter.resolveTarget(_currentUrl);
    final canOpenInApp =
        !browserOnlyMode &&
        target != null &&
        !target.startsWith('/browser?') &&
        appPageRedirect(target) == null;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
        color: cs.surface,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 22),
              tooltip: '后退',
              onPressed: _canGoBack ? () => _controller?.goBack() : null,
              color: _canGoBack ? null : cs.outlineVariant,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 22),
              tooltip: '前进',
              onPressed: _canGoForward ? () => _controller?.goForward() : null,
              color: _canGoForward ? null : cs.outlineVariant,
            ),
            const Spacer(),
            if (canOpenInApp)
              IconButton(
                icon: const Icon(Icons.open_in_new, size: 20),
                tooltip: '在 App 中打开',
                onPressed: _openInApp,
              ),
            if (browsedSite != null)
              IconButton(
                icon: Icon(
                  isLoggedIn ? Icons.person_pin : Icons.person_outline,
                  size: 20,
                ),
                tooltip: '切换账号',
                onPressed: _showAccountSwitch,
              ),
          ],
        ),
      ),
    );
  }
}

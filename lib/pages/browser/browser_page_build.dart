part of 'browser_page.dart';

/// [BrowserPage] 的构建逻辑。
///
/// `build` 是接口成员不能整体搬走：宿主保留 `build => _buildPage(context)`，
/// 原体改名 `_buildPage` 承载于此。
extension _BrowserPageBuild on _BrowserPageState {
  // ==================== UI ====================

  Widget _buildPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                    _setState(() => _desktopMode = !_desktopMode);
                    _controller?.setSettings(
                      settings: InAppWebViewSettings(
                        userAgent: _desktopMode ? Site.uaPc : Site.uaAndroid,
                      ),
                    );
                    _controller?.reload();
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

    return InAppWebView(
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
      onProgressChanged: _onProgressChanged,
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        // 降级模式下不再拦截：否则"回退到浏览器 → 又被 App 接管"会来回推页面
        if (!_urlInterceptEnabled || browserOnlyMode) {
          return NavigationActionPolicy.ALLOW;
        }

        final url = navigationAction.request.url?.toString() ?? '';
        if (url.isEmpty) return NavigationActionPolicy.ALLOW;

        final uri = Uri.tryParse(url);
        if (uri == null) return NavigationActionPolicy.ALLOW;

        // 如果要加载的域名不是 baseUrl，立即放行
        final baseHost = Uri.tryParse(SiteStore.instance.baseUrl)?.host;
        if (baseHost != null && uri.host != baseHost) {
          return NavigationActionPolicy.ALLOW;
        }

        // 匹配 App 路由成功则拦截并在 App 中打开
        final result = UrlRouter.parse(url);
        if (result.appPath != null && mounted) {
          // 浏览器容器还留在栈上、不会走 dispose，这里先回流一次
          await _syncCookiesBack();
          if (!mounted) return NavigationActionPolicy.ALLOW;
          showToast('拦截：已在 App 中打开', duration: const Duration(seconds: 1));
          context.push(result.appPath!);
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  Widget _buildBottomBar() {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;
    final routeResult = UrlRouter.parse(_currentUrl);
    // 降级模式下隐藏「在 App 中打开」：点它只会被 redirect 又送回浏览器，无意义
    final canOpenInApp =
        !browserOnlyMode &&
        routeResult.appPath != null &&
        !routeResult.isOtherSite;

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

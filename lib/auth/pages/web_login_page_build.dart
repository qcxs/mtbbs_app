part of 'web_login_page.dart';

/// WebView 登录页面 — 构建。
///
/// 通过 `part of` 与 web_login_page.dart 共享库内私有成员。
extension on _WebLoginPageState {
  // ==================== UI ====================

  Widget _buildPage(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: cs.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: GestureDetector(
          onTap: _showUrlDialog,
          child: Text(
            _loginUrl.host,
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          SizedBox(
            height: 32,
            child: TextButton.icon(
              onPressed: _showCookieInputDialog,
              icon: const Icon(Icons.cookie, size: 16),
              label: const Text('Cookie', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
        bottom: _progress > 0 && _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final cs = Theme.of(context).colorScheme;
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.outlineVariant),
              const SizedBox(height: 12),
              Text(
                '页面加载失败',
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                _errorMessage ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildWebView();
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: Site.uaAndroid,
        // 禁用下拉刷新等干扰
        supportZoom: false,
      ),
      initialUrlRequest: URLRequest(url: _loginUrl),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStart: _onLoadStart,
      onLoadStop: (controller, url) {
        // 页面加载完成，检测登录 Cookie
        _checkLoginOnLoadStop(controller, url);
        _setState(() {});
      },
      onProgressChanged: (controller, progress) {
        // progress: int 0-100
        _setState(() => _progress = progress / 100);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
      onReceivedError: (controller, request, error) {
        AppLogger.w('AUTH', 'webview load error: $error');
        if (!mounted) return;
        final errorHost = Uri.tryParse(request.url.toString())?.host;
        if (errorHost == Uri.parse(SiteStore.instance.baseUrl).host) {
          _setState(() {
            _hasError = true;
            _errorMessage = error.description;
          });
        }
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../auth/providers/auth_provider.dart';
import '../../config/site_config.dart';
import '../../core/clipboard_helper.dart';
import '../../core/cookie_sync.dart';
import '../../core/url_router.dart';

/// 内置浏览器页面
///
/// 自动携带当前用户的 Cookie，支持多站点多账号切换。
/// 与 WebLoginPage 职责分离：本页不做登录检测、不清除 Cookie。
class BrowserPage extends StatefulWidget {
  final String initialUrl;
  const BrowserPage({super.key, this.initialUrl = ''});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _controller;
  String _currentUrl = '';
  bool _desktopMode = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  double _progress = 0;
  bool _hasError = false;
  String? _errorMessage;
  bool _cookiesSynced = false;
  bool _cookiesReady = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.initialUrl.isNotEmpty
        ? widget.initialUrl
        : SiteConfig.baseUrl;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cookiesSynced) {
      _cookiesSynced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCookies().then((_) {
          if (mounted) setState(() => _cookiesReady = true);
        });
      });
    }
  }

  String get _host => Uri.tryParse(_currentUrl)?.host ?? '';

  // ==================== Cookie 同步 ====================

  Future<void> _syncCookies() async {
    try {
      final auth = context.read<AuthProvider>();
      // 先清除旧 Cookie，避免残留
      await CookieManager.instance().deleteAllCookies();
      // 再设置当前账号的 Cookie
      await syncCookieStringToWebView(
        auth.currentCookieString,
        SiteConfig.baseUrl,
      );
    } catch (_) {
      // Cookie 同步失败不应阻塞页面加载
    }
  }

  // ==================== 账号切换 ====================

  Future<void> _showAccountSwitch() async {
    final auth = context.read<AuthProvider>();
    final accounts = auth.accounts;
    final activeIdx = auth.activeIndex;

    if (accounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前站点无可用账号')));
      return;
    }

    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '切换账号',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            ...List.generate(accounts.length, (i) {
              final a = accounts[i];
              final isActive = i == activeIdx;
              final isGuest = a.uid == '0';
              return ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  child: Text(
                    isGuest
                        ? '?'
                        : (a.username.isNotEmpty
                              ? a.username[0].toUpperCase()
                              : '?'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                title: Text(
                  isGuest ? '游客' : a.username,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                subtitle: isGuest ? null : Text('UID: ${a.uid}'),
                trailing: isActive ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.of(ctx).pop(i),
              );
            }),
          ],
        ),
      ),
    );

    if (result == null || result == activeIdx || !mounted) return;

    await auth.switchTo(result);
    await _syncCookies();
    _controller?.reload();
  }

  // ==================== URL 编辑弹窗 ====================

  Future<void> _showUrlEditor() async {
    final controller = TextEditingController(text: _currentUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入网址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('前往'),
          ),
        ],
      ),
    );

    if (result != null && result != _currentUrl && result.isNotEmpty) {
      final uri = Uri.tryParse(result);
      final finalUrl = (uri != null && uri.hasScheme)
          ? result
          : 'https://$result';
      _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(finalUrl)));
    }
  }

  // ==================== 更多菜单操作 ====================

  void _copyUrl() {
    ClipboardHelper.write(_currentUrl);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('链接已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _openInExternalBrowser() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _toggleDesktopMode() {
    setState(() => _desktopMode = !_desktopMode);
    _controller?.setSettings(
      settings: InAppWebViewSettings(
        userAgent: _desktopMode ? SiteConfig.uaPc : SiteConfig.uaAndroid,
      ),
    );
    _controller?.reload();
  }

  /// 用 App 本地页面打开当前 URL（如果支持）
  void _openInApp() {
    final result = UrlRouter.parse(_currentUrl);

    // 检查是否属于其他站点
    if (result.isOtherSite && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请切换站点${result.siteName ?? ""}后再打开'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (result.appPath != null && mounted) {
      context.push(result.appPath!);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('不支持在当前页面打开：${result.label}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ==================== WebView 回调 ====================

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = null;
    });
  }

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    final urlStr = url?.toString() ?? '';
    setState(() {
      _currentUrl = urlStr;
    });
    controller.canGoBack().then((v) {
      if (mounted) setState(() => _canGoBack = v);
    });
    controller.canGoForward().then((v) {
      if (mounted) setState(() => _canGoForward = v);
    });
  }

  void _onProgressChanged(InAppWebViewController controller, int progress) {
    if (mounted) setState(() => _progress = progress / 100);
  }

  void _onReceivedError(
    InAppWebViewController controller,
    WebResourceRequest request,
    WebResourceError error,
  ) {
    if (!mounted) return;
    setState(() {
      _hasError = true;
      _errorMessage = error.description;
    });
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoggedIn = auth.isLoggedIn;

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _controller?.goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            icon: Icon(_canGoBack ? Icons.arrow_back : Icons.close),
            tooltip: _canGoBack ? '后退' : '关闭',
            onPressed: () {
              if (_canGoBack) {
                _controller?.goBack();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          title: GestureDetector(
            onTap: _showUrlEditor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _host.isNotEmpty ? _host : '浏览器',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          actions: [
            // 始终关闭按钮
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 刷新
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '刷新',
              onPressed: () => _controller?.reload(),
            ),
            // 账号切换
            IconButton(
              icon: Icon(
                isLoggedIn ? Icons.person_pin : Icons.person_outline,
                size: 20,
              ),
              tooltip: '切换账号',
              onPressed: _showAccountSwitch,
            ),
            // 更多菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                switch (v) {
                  case 'copyUrl':
                    _copyUrl();
                  case 'openExternal':
                    _openInExternalBrowser();
                  case 'openInApp':
                    _openInApp();
                  case 'desktopMode':
                    _toggleDesktopMode();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'openInApp',
                  child: Text('在 App 中打开'),
                ),
                const PopupMenuItem(value: 'copyUrl', child: Text('复制链接')),
                const PopupMenuItem(
                  value: 'openExternal',
                  child: Text('浏览器打开'),
                ),
                PopupMenuItem(
                  value: 'desktopMode',
                  child: Row(
                    children: [
                      Text(_desktopMode ? '手机模式' : '桌面模式'),
                      const Spacer(),
                      if (_desktopMode)
                        const Icon(Icons.check, size: 16, color: Colors.green),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: _progress > 0 && _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress),
                )
              : null,
        ),
        body: _hasError ? _buildError() : _buildWebView(),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              '页面加载失败',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = null;
                });
                _controller?.reload();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    if (!_cookiesReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: SiteConfig.uaAndroid,
        supportZoom: true,
      ),
      initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
      onWebViewCreated: (controller) {
        _controller = controller;
      },
      onLoadStart: _onLoadStart,
      onLoadStop: _onLoadStop,
      onProgressChanged: _onProgressChanged,
      onReceivedError: _onReceivedError,
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        color: Colors.white,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 22),
              onPressed: _canGoBack ? () => _controller?.goBack() : null,
              color: _canGoBack ? null : Colors.grey.shade300,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 22),
              onPressed: _canGoForward ? () => _controller?.goForward() : null,
              color: _canGoForward ? null : Colors.grey.shade300,
            ),
          ],
        ),
      ),
    );
  }
}

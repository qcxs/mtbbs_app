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
///
/// [enableUrlIntercept] 为 true 时，URL 发生变化会尝试匹配 App 路由，
/// 匹配成功则拦截并在 App 内打开。从 App 内打开浏览器时应传入 false 避免循环。
class BrowserPage extends StatefulWidget {
  final String initialUrl;
  final bool enableUrlIntercept;

  const BrowserPage({
    super.key,
    this.initialUrl = '',
    this.enableUrlIntercept = true,
  });

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
  bool _cookiesSynced = false;
  bool _cookiesReady = false;
  bool _urlInterceptEnabled = true;

  @override
  void initState() {
    super.initState();
    _urlInterceptEnabled = widget.enableUrlIntercept;
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

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {}

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

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
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
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          actions: [
            // 关闭
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
            // URL 拦截 — 可点击切换，通过图标状态了解当前是否启用
            IconButton(
              icon: Icon(
                _urlInterceptEnabled ? Icons.shield : Icons.shield_outlined,
                size: 20,
              ),
              tooltip: _urlInterceptEnabled ? 'URL 拦截已启用' : 'URL 拦截已禁用',
              onPressed: () =>
                  setState(() => _urlInterceptEnabled = !_urlInterceptEnabled),
            ),
            // 更多菜单
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              padding: EdgeInsets.zero,
              onSelected: (v) {
                switch (v) {
                  case 'desktopMode':
                    setState(() => _desktopMode = !_desktopMode);
                    _controller?.setSettings(
                      settings: InAppWebViewSettings(
                        userAgent: _desktopMode
                            ? SiteConfig.uaPc
                            : SiteConfig.uaAndroid,
                      ),
                    );
                    _controller?.reload();
                  case 'copyUrl':
                    _copyUrl();
                  case 'openExternal':
                    _openInExternalBrowser();
                }
              },
              itemBuilder: (_) => [
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
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        if (!_urlInterceptEnabled) return NavigationActionPolicy.ALLOW;

        final url = navigationAction.request.url?.toString() ?? '';
        if (url.isEmpty) return NavigationActionPolicy.ALLOW;

        final uri = Uri.tryParse(url);
        if (uri == null) return NavigationActionPolicy.ALLOW;

        // 如果要加载的域名不是 baseUrl，立即放行
        final baseHost = Uri.tryParse(SiteConfig.baseUrl)?.host;
        if (baseHost != null && uri.host != baseHost) {
          return NavigationActionPolicy.ALLOW;
        }

        // 匹配 App 路由成功则拦截并在 App 中打开
        final result = UrlRouter.parse(url);
        if (result.appPath != null && mounted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('拦截：已在 App 中打开'),
                duration: Duration(seconds: 1),
              ),
            );
          }
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
    final canOpenInApp =
        routeResult.appPath != null && !routeResult.isOtherSite;

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

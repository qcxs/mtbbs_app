part of 'browser_page.dart';

/// [BrowserPage] 的交互/回调逻辑。
///
/// 方法无法跨文件拆，故以 extension 承载：扩展可访问宿主私有成员，
/// 宿主类体内也可无前缀直接调用。受保护的 setState 改用宿主预留的 _setState。
extension _BrowserPageActions on _BrowserPageState {
  // ==================== Cookie 同步 ====================

  Future<void> _syncCookies() async {
    final auth = context.read<AuthProvider>();
    // 两步必须互相独立：清理失败绝不能连累注入，否则浏览器会显示成"未登录"。
    // （这里以前是一个大 try 包住两步 + `catch (_)` 静默吞掉，
    //  清理步骤一旦抛异常，注入就被整体跳过——见 docs/07 静默失败）
    try {
      // 先清除本站点旧 Cookie，避免残留
      // （只清当前站点：打开浏览器不能把其他站点的 WebView 登录态一起清掉）
      await clearCookiesForHost(SiteStore.instance.baseUrl);
    } catch (e) {
      AppLogger.w('PAGE', 'clear webview cookies failed: $e');
    }
    try {
      // 再设置当前账号的 Cookie
      await syncCookieStringToWebView(
        auth.currentCookieString,
        SiteStore.instance.baseUrl,
      );
    } catch (e) {
      AppLogger.w('PAGE', 'inject webview cookies failed: $e');
    }
  }

  /// WebView → Dio：把浏览器里新增/刷新的 Cookie 回流给 App。
  ///
  /// 场景：在内置浏览器里过了验证码、重新登录，或站点刷新了会话 Cookie——
  /// 这些 Cookie 只落在 WebView，不回流的话 App 后续请求仍带旧 Cookie，
  /// 表现为「浏览器里验证通过了，App 里还是失败」。
  ///
  /// 只在离开浏览器时调用（关闭页面 / 跳回 App 内页面），不做逐页同步。
  Future<void> _syncCookiesBack() async {
    try {
      final jar = ApiService().activeCookieJar;
      if (jar == null) return;
      await syncWebViewCookiesToJar(
        jar: jar,
        baseUrl: SiteStore.instance.baseUrl,
      );
    } catch (e) {
      AppLogger.w('PAGE', 'cookie 回流失败: $e');
    }
  }

  // ==================== 账号切换 ====================

  Future<void> _showAccountSwitch() async {
    final auth = context.read<AuthProvider>();
    final accounts = auth.accounts;
    final activeIdx = auth.activeIndex;

    if (accounts.isEmpty) {
      if (!mounted) return;
      showToast('当前站点无可用账号');
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
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _UrlEditorDialog(initialUrl: _currentUrl),
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
      showToast('链接已复制', duration: const Duration(seconds: 1));
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
      message: '确定要清除浏览器缓存吗？此操作将清空网页资源缓存、Cookie 和本地存储数据。',
      confirmText: '清空',
    );
    if (confirmed != true || !mounted) return;
    await clearWebViewCache();
    if (mounted) {
      showToast('浏览器缓存已清空');
    }
  }

  /// 用 App 本地页面打开当前 URL（如果支持）
  void _openInApp() {
    final result = UrlRouter.parse(_currentUrl);

    // 检查是否属于其他站点
    if (result.isOtherSite && mounted) {
      showToast(
        '请切换站点${result.siteName ?? ""}后再打开',
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (result.appPath != null && mounted) {
      context.push(result.appPath!);
    } else if (mounted) {
      showToast('不支持在当前页面打开：${result.label}');
    }
  }

  // ==================== WebView 回调 ====================

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {}

  void _onLoadStop(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    final urlStr = url?.toString() ?? '';
    _setState(() {
      _currentUrl = urlStr;
    });
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
}

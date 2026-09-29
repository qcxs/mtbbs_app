part of 'web_login_page.dart';

/// WebView 登录页面 — 交互与登录检测。
///
/// 通过 `part of` 与 web_login_page.dart 共享库内私有成员。
extension on _WebLoginPageState {
  /// 显示 URL 输入对话框，点击标题触发
  void _showUrlDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => _UrlInputDialog(
        initialUrl: _urlController.text,
        cs: cs,
        onNavigate: _navigateFromController,
      ),
    );
  }

  /// 从对话框文本提取 URL 并导航
  void _navigateFromController(String text) {
    var url = text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _urlController.text = url;
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ==================== 登录检测 ====================

  /// 页面加载完成后检测 Cookie 中是否包含 Discuz _auth 字段
  Future<void> _checkLoginOnLoadStop(
    InAppWebViewController controller,
    WebUri? url,
  ) async {
    if (_loginDone || url == null) return;

    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(SiteStore.instance.baseUrl),
    );

    // Discuz 登录成功后会写入 {tablepre}_auth cookie
    if (!cookies.any((c) => c.name.endsWith('_auth'))) return;

    await _onLoginSuccess(controller, url, cookies);
  }

  // ==================== 提取 Cookie + 验证 ====================

  /// 读取全部 Cookie → 调 userstatus API 验证 → 保存账号 → pop 结果
  Future<void> _onLoginSuccess(
    InAppWebViewController controller,
    WebUri url,
    List<dynamic> baseCookies,
  ) async {
    if (_loginDone) return;
    _loginDone = true;

    try {
      final forumCookies = await CookieManager.instance().getCookies(url: url);
      final allCookies = [
        ...baseCookies,
        ...forumCookies,
      ].map((c) => '${c.name}=${c.value}').join('; ');

      // 用临时 Dio 调用 userstatus API 验证登录
      final tempDio = Dio(
        BaseOptions(
          baseUrl: SiteStore.instance.baseUrl,
          headers: {'User-Agent': Site.uaAndroid, 'Cookie': allCookies},
        ),
      );
      final result = await userstatus_api.fetch(tempDio);

      if (!mounted) return;

      if (result['success'] == true && result['uid'] != '0') {
        // 页面内部直接保存账号，调用方只需知道成功/失败
        final auth = context.read<AuthProvider>();
        final uid = result['uid']?.toString() ?? '';
        final username = result['username']?.toString() ?? '';
        final saved = await auth.saveWebLogin(
          username.isNotEmpty ? username : uid,
          uid,
          allCookies,
        );
        if (!mounted) return;
        if (!saved) {
          _loginDone = false;
          showToast('账号保存失败，请重试');
          return;
        }
        Navigator.of(context).pop(true);
        showToast('登录成功');
      } else {
        _loginDone = false;
        if (mounted) {
          showToast('登录验证失败，请重试');
        }
      }
    } catch (e) {
      AppLogger.w('AUTH', 'web login error: $e');
      _loginDone = false;
      if (mounted) {
        Navigator.of(context).pop(false);
      }
    }
  }

  // ==================== Cookie 登录 ====================

  /// 校验 Cookie 字符串格式（name=value; ...）
  bool _isValidCookieFormat(String cookieStr) {
    final trimmed = cookieStr.trim();
    if (trimmed.isEmpty) return false;
    final parts = trimmed.split(';');
    var hasValidPair = false;
    for (final part in parts) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq <= 0) return false; // 无 = 或 name 为空
      hasValidPair = true;
    }
    return hasValidPair;
  }

  /// 检测 Cookie 中是否包含 Discuz _auth 字段
  bool _hasAuthCookie(String cookieStr) {
    for (final part in cookieStr.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq > 0 && trimmed.substring(0, eq).endsWith('_auth')) return true;
    }
    return false;
  }

  /// 显示 Cookie 输入对话框
  void _showCookieInputDialog() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => _CookieInputDialog(cs: cs, onSubmit: _handleCookieLogin),
    );
  }

  /// 处理 Cookie 登录
  Future<void> _handleCookieLogin(String rawCookie) async {
    final cookieStr = rawCookie.trim();
    if (cookieStr.isEmpty) return;

    // 1. 校验格式
    if (!_isValidCookieFormat(cookieStr)) {
      if (!mounted) return;
      showToast('Cookie 格式错误，请检查后重试');
      return;
    }

    // 2. 检测 _auth 凭证（格式校验通过后的内容校验）
    if (!_hasAuthCookie(cookieStr)) {
      if (!mounted) return;
      showToast('Cookie 中未包含有效的登录凭证');
      return;
    }

    // 3. 清除本站点旧 Cookie → 注入新 Cookie（与内置浏览器相同模式）
    await clearCookiesForHost(SiteStore.instance.baseUrl);
    await syncCookieStringToWebView(cookieStr, SiteStore.instance.baseUrl);

    // 4. 跳转到站点首页，原 _checkLoginOnLoadStop 会自动检测 _auth 并完成登录
    _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(SiteStore.instance.baseUrl)),
    );
  }

  // ==================== URL 变化检测 ====================

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    _setState(() {
      _hasError = false;
      _errorMessage = null;
    });
  }

  // ==================== 重试 ====================

  void _retry() {
    _setState(() {
      _hasError = false;
      _errorMessage = null;
      _progress = 0;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: _loginUrl));
  }
}

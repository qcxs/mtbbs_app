import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// WebView 登录页面
///
/// 顶栏：标题 + URL 编辑栏 + Cookie 登录按钮
/// 中间：WebView 浏览器控件（基于 flutter_inappwebview）
/// 加载状态：进度条（无遮罩层）
/// 登录检测：URL 不包含 action=login 即为成功
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key});

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  InAppWebViewController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  bool _loginDone = false;
  double _progress = 0;
  late final TextEditingController _urlController;

  WebUri get _loginUrl {
    final path = SiteStore.instance.loginPagePath;
    if (path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        return WebUri(path);
      }
      return WebUri('${SiteStore.instance.baseUrl}$path');
    }
    return WebUri(
      '${SiteStore.instance.baseUrl}/member.php?mod=logging&action=login&mobile=2',
    );
  }

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _loginUrl.toString());
    // 清除 WebView Cookie，避免已登录状态跳过登录页
    CookieManager.instance().deleteAllCookies();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 显示 URL 输入对话框，点击标题触发
  void _showUrlDialog() {
    final cs = Theme.of(context).colorScheme;
    final ctl = TextEditingController(text: _urlController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入网址'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: 'https://...',
            border: const OutlineInputBorder(),
            isDense: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            filled: true,
          ),
          onSubmitted: (value) {
            Navigator.of(ctx).pop();
            _navigateFromController(ctl);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _navigateFromController(ctl);
            },
            child: const Text('前往'),
          ),
        ],
      ),
    );
  }

  /// 从对话框控制器提取 URL 并导航
  void _navigateFromController(TextEditingController ctl) {
    var url = ctl.text.trim();
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
      debugPrint('[WebLogin] error: $e');
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
    final cookieController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420),
        title: const Row(
          children: [
            Expanded(child: Text('Cookie 登录', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '从浏览器开发者工具复制完整的 Cookie 字符串后粘贴到下方：',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cookieController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'name1=value1; name2=value2; ...',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleCookieLogin(cookieController.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
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

    // 3. 清除旧 Cookie → 注入新 Cookie（与内置浏览器相同模式）
    await CookieManager.instance().deleteAllCookies();
    await syncCookieStringToWebView(cookieStr, SiteStore.instance.baseUrl);

    // 4. 跳转到站点首页，原 _checkLoginOnLoadStop 会自动检测 _auth 并完成登录
    _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(SiteStore.instance.baseUrl)),
    );
  }

  // ==================== URL 变化检测 ====================

  void _onLoadStart(InAppWebViewController controller, WebUri? url) {
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorMessage = null;
    });
  }

  // ==================== 重试 ====================

  void _retry() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _progress = 0;
    });
    _controller?.loadUrl(urlRequest: URLRequest(url: _loginUrl));
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
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
        if (mounted) setState(() {});
      },
      onProgressChanged: (controller, progress) {
        // progress: int 0-100
        if (mounted) setState(() => _progress = progress / 100);
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        return NavigationActionPolicy.ALLOW;
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[WebLogin] error: $error');
        if (!mounted) return;
        final errorHost = Uri.tryParse(request.url.toString())?.host;
        if (errorHost == Uri.parse(SiteStore.instance.baseUrl).host) {
          setState(() {
            _hasError = true;
            _errorMessage = error.description;
          });
        }
      },
    );
  }
}

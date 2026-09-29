import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/confirm_dialog.dart';

part 'browser_page_actions.dart';
part 'browser_page_build.dart';
part 'browser_page_widgets.dart';

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
        : SiteStore.instance.baseUrl;
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

  @override
  void dispose() {
    // 离开浏览器时把 WebView 里新增的 Cookie 回流给 App。
    // dispose 是同步的，这里不能 await；失败只记日志，不影响关闭。
    unawaited(_syncCookiesBack());
    super.dispose();
  }

  String get _host => Uri.tryParse(_currentUrl)?.host ?? '';

  /// 供 part 内的 extension 调用：扩展无法访问 State 受保护的 setState。
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}

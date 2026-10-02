import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;
import 'package:mtbbs/core/app/cookie_sync.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

part 'web_login_page_actions.dart';
part 'web_login_page_build.dart';
part 'web_login_page_widgets.dart';

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

  /// 本站点旧 Cookie 是否已清空 —— 没清完不创建 WebView
  bool _cookiesCleared = false;

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
    _clearSiteCookiesThenLoad();
  }

  /// 先清空本站点的 WebView Cookie，清完才让 WebView 开始加载
  ///
  /// 顺序不能反：登录页必须是"干净"的，否则站点看到上一账号的登录态，
  /// 用户没法登录其他账号。原先是 initState 里 fire-and-forget 地清，
  /// 而 WebView 在同一帧就带着旧 Cookie 发起了请求 —— 清完也晚了，
  /// 首屏（乃至重定向结果）已经是"已登录"的样子。
  ///
  /// 只清当前站点，不影响其他站点的 WebView 登录态。
  /// [clearCookiesForHost] 内部吞掉异常、不会抛，因此这里不会卡在加载态。
  Future<void> _clearSiteCookiesThenLoad() async {
    await clearCookiesForHost(SiteStore.instance.baseUrl);
    if (!mounted) return;
    _setState(() => _cookiesCleared = true);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 供 part 扩展使用（扩展无法直接访问受保护的 setState）
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);
}

/// Cookie 输入弹窗内容
///
/// 控制器由本 State 持有，理由同 [_UrlInputDialog]。
class _CookieInputDialog extends StatefulWidget {
  const _CookieInputDialog({required this.cs, required this.onSubmit});

  final ColorScheme cs;
  final void Function(String rawCookie) onSubmit;

  @override
  State<_CookieInputDialog> createState() => _CookieInputDialogState();
}

class _CookieInputDialogState extends State<_CookieInputDialog> {
  final _cookieController = TextEditingController();

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            style: TextStyle(fontSize: 13, color: widget.cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cookieController,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSubmit(_cookieController.text);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

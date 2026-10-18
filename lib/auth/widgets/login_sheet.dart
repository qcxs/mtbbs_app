import 'package:flutter/material.dart';
import 'package:mtbbs/auth/pages/web_login_page.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 直接打开 WebView 登录页
///
/// Cookie 输入功能已集成到 WebView 页面内的「Cookie」按钮中，
/// 用户可在 WebView 容器内自行选择是否使用 Cookie 登录。
Future<void> showLoginSheet(BuildContext context) {
  if (!AppCapabilities.isAvailable(AppCapability.webView)) {
    showToast('当前平台不支持内置浏览器登录');
    return Future.value();
  }
  return Navigator.of(context)
      .push<bool>(MaterialPageRoute(builder: (_) => const WebLoginPage()))
      .then((ok) {
        if (ok != true || !context.mounted) return;
        showToast('登录成功');
      });
}

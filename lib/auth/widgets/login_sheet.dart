import 'package:flutter/material.dart';
import '../pages/web_login_page.dart';

/// 直接打开 WebView 登录页
///
/// Cookie 输入功能已集成到 WebView 页面内的「Cookie」按钮中，
/// 用户可在 WebView 容器内自行选择是否使用 Cookie 登录。
Future<void> showLoginSheet(BuildContext context) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const WebLoginPage()),
  ).then((ok) {
    if (ok != true || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('登录成功')));
  });
}

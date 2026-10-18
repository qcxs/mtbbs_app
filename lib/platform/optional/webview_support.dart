import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 内置 WebView 的平台适配。
///
/// **唯一** import `flutter_inappwebview` 的非 UI 文件（页面组件本身仍需要它）。
/// 平台没有实现时直接 no-op，避免清缓存等辅助功能把整个页面拖崩。
abstract final class WebViewSupport {
  WebViewSupport._();

  static bool get available => AppCapabilities.isAvailable(AppCapability.webView);

  static void disable() => AppCapabilities.disable(AppCapability.webView);
}

/// 清除内置浏览器的所有缓存数据（资源缓存、Web 存储、Cookie）。
///
/// 使用 [flutter_inappwebview] 的静态 API，无需活动 WebView 实例。
Future<void> clearWebViewCache() async {
  if (!WebViewSupport.available) return;
  try {
    await InAppWebViewController.clearAllCache(includeDiskFiles: true);
  } on MissingPluginException {
    WebViewSupport.disable();
    return;
  } on UnimplementedError {
    WebViewSupport.disable();
    return;
  } catch (e) {
    AppLogger.w('CACHE', 'clearAllCache error: $e');
  }
  try {
    await WebStorageManager.instance().deleteAllData();
  } catch (e) {
    AppLogger.w('CACHE', 'deleteAllData error: $e');
  }
  try {
    await CookieManager.instance().deleteAllCookies();
  } catch (e) {
    AppLogger.w('CACHE', 'deleteAllCookies error: $e');
  }
}

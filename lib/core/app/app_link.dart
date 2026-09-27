import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';

/// 系统「打开方式」传入的论坛链接（Android）。
///
/// 注册见 `AndroidManifest.xml` 里的 VIEW/BROWSABLE intent-filter：
/// 在浏览器或其他应用里点论坛链接时，可以选择用 MTBBS 打开，链接由这里
/// 转成 App 内路由（复用内置浏览器那套 `UrlRouter`，不再写第二份映射）。
class AppLink {
  AppLink._();

  static const MethodChannel _channel = MethodChannel('mtbbs/intent');

  /// 处理入站链接。
  ///
  /// [onOpen] 收到的是**最终落地路由**：命中 App 内页面就是该页面路径，
  /// 否则是内置浏览器的兜底路径（由 `UrlRouter.resolveTarget` 决定）。
  static Future<void> init({
    required void Function(String target) onOpen,
  }) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openedUrl') return;
      final url = call.arguments;
      if (url is String) dispatch(url, onOpen: onOpen);
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialUrl');
      if (initial != null && initial.isNotEmpty) {
        dispatch(initial, onOpen: onOpen);
      }
    } catch (e) {
      AppLogger.w('PAGE', '读取启动链接失败: $e');
    }
  }

  /// 解析并分发（独立出来便于单测）
  ///
  /// 决策统一交给 [UrlRouter.resolveTarget]：与首页链接点击、帖子正文里的链接
  /// 共用同一套"App 内路由优先、兜底内置浏览器"的逻辑，不另写一份。
  static void dispatch(
    String url, {
    required void Function(String target) onOpen,
  }) {
    final target = UrlRouter.resolveTarget(url);
    if (target == null) return;
    AppLogger.i('PAGE', '入站链接 → $target');
    onOpen(target);
  }
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_router.dart';

/// Android 桌面「长按应用图标 → 快捷方式」（App Shortcuts）。
///
/// 为什么用**动态注册**而不是静态 `res/xml/shortcuts.xml`：静态 `<intent>` 必须写死
/// `targetPackage`，而本 App 有三个 applicationId（`com.github.qcxs.discuz` /
/// `.debug` / `.beta`），静态 XML 只能命中其中一个。动态注册在运行时用
/// `Intent(context, MainActivity::class.java)` 构造组件，**天然跟随当前变体的包名**。
///
/// 点击后走既有的「入站链接」链路（与系统「打开方式」共用）：
/// `Intent.data`（`mtbbs://settings/cache`）→ 原生 `mtbbs/intent` 通道 →
/// [UrlRouter.resolveTarget] → App 内路由（见 `core/app/app_link.dart`）。
///
/// 平台/版本：仅 Android 7.1（API 25）及以上；旧版本或注册失败都静默跳过，不影响启动。
class AppShortcuts {
  AppShortcuts._();

  static const MethodChannel _channel = MethodChannel('mtbbs/shortcuts');

  /// 「缓存管理」快捷方式 id（稳定标识，勿改）
  static const String cacheSettingsId = 'cache_settings';

  /// 注册（幂等）桌面快捷方式；重复调用只是覆盖同 id 项。
  static Future<void> install() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('install', {
        'id': cacheSettingsId,
        'shortLabel': '缓存管理',
        'longLabel': '清理与设置图片缓存',
        'uri': '${UrlRouter.appScheme}://settings/cache',
      });
    } catch (e) {
      AppLogger.w('PAGE', '注册桌面快捷方式失败: $e');
    }
  }
}

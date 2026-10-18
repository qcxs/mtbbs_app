import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// App 的可选能力。
///
/// 这些能力依赖的插件并非所有平台都有原生实现（典型：鸿蒙）。业务入口在
/// 使用前先问 [AppCapabilities]，不可用时隐藏入口或降级，而不是让调用直接
/// 抛 `MissingPluginException`。
enum AppCapability {
  /// 内置 WebView：网页登录、内置浏览器、人机验证页。
  webView,

  /// 文件选择：编辑器选图 / 附件 / 导入 Markdown。
  filePicker,

  /// 保存生成的分享图（相册或“另存为”）。
  saveImage,

  /// 本地 JS 引擎：执行站点挑战脚本（ACW 自解的第一条路径）。
  localJsSolver,

  /// MCP 只读服务端。
  mcpServer,
}

/// 模块级能力注册表。
///
/// 与 `app_page_gate.dart`、`api_service._simulateBrowserHeaders` 同一套做法：
/// 启动早期就要生效，调用点不一定有 context，因此不放进 Provider。
///
/// 判定分两层：
/// 1. 编译期无法感知依赖是否存在于 pubspec——插件缺失时此处按平台策略给默认值；
/// 2. 运行时调用失败（`MissingPluginException` / `UnimplementedError`）时由
///    适配器调用 [disable]，本次进程内后续入口自动降级。
abstract final class AppCapabilities {
  AppCapabilities._();

  static final Map<AppCapability, bool> _available = {};
  static bool _initialized = false;

  /// 当前是否鸿蒙。
  ///
  /// **不要引用 `TargetPlatform.ohos`**：主线用官方 Flutter 编译时不存在该枚举，
  /// 引用会直接编译失败。这里用字符串比较，两套 SDK 都能通过。
  static bool get isOhos =>
      defaultTargetPlatform.name == 'ohos' ||
      Platform.operatingSystem == 'ohos';

  static void init() {
    if (_initialized) return;
    _initialized = true;
    for (final capability in AppCapability.values) {
      _available[capability] = _defaultAvailable(capability);
    }
  }

  static bool isAvailable(AppCapability capability) {
    init();
    return _available[capability] ?? false;
  }

  /// 运行时探测失败时调用：只关闭当前进程内的入口，不落盘。
  static void disable(AppCapability capability) {
    init();
    if (_available[capability] == false) return;
    _available[capability] = false;
    AppLogger.w('CAP', '能力已关闭：${capability.name}');
  }

  /// 测试用：重置并写入指定覆盖。
  @visibleForTesting
  static void resetForTest({Map<AppCapability, bool>? overrides}) {
    _initialized = false;
    _available.clear();
    init();
    if (overrides != null) _available.addAll(overrides);
  }

  static bool _defaultAvailable(AppCapability capability) {
    switch (capability) {
      case AppCapability.webView:
        // 鸿蒙使用社区 fork；其他平台官方实现。
        return true;
      case AppCapability.filePicker:
        return true;
      case AppCapability.saveImage:
        // 鸿蒙没有 gal，但 file_picker 的“另存为”可用；
        // 真正保存失败时由适配器 disable。
        return true;
      case AppCapability.localJsSolver:
        // flutter_qjs_next 没有鸿蒙实现；鸿蒙走纯 Dart ACW 算法兜底。
        return !isOhos;
      case AppCapability.mcpServer:
        // mcp_dart 是纯 Dart，鸿蒙可运行；启动失败时由控制器 disable。
        return true;
    }
  }
}

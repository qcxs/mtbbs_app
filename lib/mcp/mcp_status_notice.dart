import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// MCP 运行状态常驻通知（**仅 Android**，其他平台 no-op）。
///
/// 用普通"正在进行"通知而不是前台服务：MCP 只在本进程存活时才可用，
/// 进程结束通知本身也没意义，不值得为此引入前台服务、服务类型声明与额外权限。
///
/// Android 13+ 需要通知权限，未授予时原生侧会发起一次系统授权弹窗；
/// 授权被拒则静默跳过（不影响 MCP 服务本身）。
class McpStatusNotice {
  McpStatusNotice._();

  static const MethodChannel _channel = MethodChannel('mtbbs/mcp_status');

  static VoidCallback? _onTap;

  /// 注册"用户点开了常驻通知"的回调，并补取冷启动时暂存的那一次点击。
  ///
  /// 两个时机都要覆盖：App 在后台/前台时点通知走 [onNewIntent]（原生直接回调
  /// `onNotificationTap`）；App 未运行时点通知是冷启动，Dart 还没注册回调，
  /// 原生先暂存、这里用 `getPendingTap` 补取。
  ///
  /// 补取刻意等**首帧之后**再做：冷启动时根 Navigator 尚未挂载，
  /// 那时弹窗会因为没有 Overlay 而静默失败（见 `showMcpQuickDialog`）。
  static Future<void> init({required VoidCallback onNotificationTap}) async {
    if (!Platform.isAndroid) return;
    _onTap = onNotificationTap;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap') _onTap?.call();
    });
    // 注意：这里到 addPostFrameCallback 之间不能有 await——
    // 必须在调用方（main）交出事件循环前完成注册，才能挂上首帧回调
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pending = await _channel.invokeMethod<bool>('getPendingTap');
        if (pending == true) _onTap?.call();
      } catch (e) {
        AppLogger.w('MCP', '读取通知点击失败: $e');
      }
    });
  }

  static Future<void> show(String endpoint) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('show', {'endpoint': endpoint});
    } catch (e) {
      AppLogger.w('MCP', '显示状态通知失败: $e');
    }
  }

  static Future<void> hide() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('hide');
    } catch (e) {
      AppLogger.w('MCP', '取消状态通知失败: $e');
    }
  }
}

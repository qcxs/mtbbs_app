import 'dart:io';

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

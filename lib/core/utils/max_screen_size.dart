import 'dart:io';

import 'package:flutter/services.dart';

/// 折叠屏/自由窗口/分屏（小窗）检测（参考 PiliPlus max_screen_size 机制）
///
/// 判定逻辑：当前窗口宽高与物理最大屏幕（含旋转 90° 情形）不完全一致，
/// 即认为处于分屏/自由窗口/折叠小窗等"非全屏窗口模式"。
/// 仅 Android 生效，其他平台恒返回 false。
class MaxScreenSize {
  static const MethodChannel _channel = MethodChannel('mtbbs/max_screen_size');

  static int? _maxWidth;
  static int? _maxHeight;

  /// 启动时调用一次；折叠屏设备在形态变化时由原生侧主动刷新缓存
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'maxScreenSizeChanged') await _load();
      });
      await _load();
    } catch (_) {
      // 非 Android / 原生桥异常时静默降级，不影响使用
    }
  }

  static Future<void> _load() async {
    try {
      final list = await _channel.invokeListMethod<int>('getMaxScreenSize');
      if (list != null && list.length >= 2) {
        _maxWidth = list[0];
        _maxHeight = list[1];
      }
    } catch (_) {}
  }

  /// 当前窗口是否处于"非全屏窗口模式"（分屏/自由窗口/折叠小窗）
  static bool isWindowMode({required num width, required num height}) {
    final mw = _maxWidth;
    final mh = _maxHeight;
    if (mw == null || mh == null) return false;
    final w = width.round();
    final h = height.round();
    // 兼容旋转后宽高互换
    final hasWidthMatch = w == mw || w == mh;
    final hasHeightMatch = h == mw || h == mh;
    return !(hasWidthMatch && hasHeightMatch);
  }
}

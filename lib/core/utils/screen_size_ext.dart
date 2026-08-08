import 'package:flutter/widgets.dart';

/// 屏幕方向与尺寸判断扩展（参考 PiliPlus 的 600dp 手机/平板分界）
extension ScreenSizeExt on Size {
  /// 竖屏：宽度 < 600 或高度 >= 宽度
  bool get isPortrait => width < 600 || height >= width;

  /// 横屏（宽屏）
  bool get isLandscape => !isPortrait;

  /// 宽屏双栏布局判定：横屏且足够宽（>= 900），
  /// 避免横屏手机/窄窗口双栏过挤
  bool get isWide => isLandscape && width >= 900;
}

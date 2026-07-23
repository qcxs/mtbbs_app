import 'package:flutter/material.dart';

/// 显示顶部 Toast（Overlay 方式，不受底部面板遮挡影响）
///
/// 与 ScaffoldMessenger.showSnackBar 的 API 保持一致，
/// 可通过 [position] 参数切换显示位置：
///   - [ToastPosition.top]（默认）：屏幕顶部，用于面板展开时不被遮挡
///   - [ToastPosition.bottom]：底部，行为类似 SnackBar
void showToast(
  BuildContext context,
  String message, {
  ToastPosition position = ToastPosition.top,
  Duration duration = const Duration(seconds: 2),
  Color? backgroundColor,
}) {
  if (position == ToastPosition.bottom) {
    // 回退到标准 SnackBar
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: duration));
    return;
  }

  // 顶部 Overlay Toast
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (_) {
      return StatefulBuilder(
        builder: (context, setInnerState) {
          return Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              color: backgroundColor ?? Colors.grey[800],
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      );
    },
  );
  Overlay.of(context).insert(entry);
  Future.delayed(duration, () => entry?.remove());
}

enum ToastPosition { top, bottom }

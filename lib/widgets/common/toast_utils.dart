import 'package:flutter/material.dart';

/// 显示 Android 风格 Toast（Overlay 方式）
///
/// 不受 Scaffold 底部栏遮挡，紧凑胶囊形，半透明黑底。
void showToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (_) {
      final bottom = MediaQuery.of(context).padding.bottom + 80;
      return Positioned(
        bottom: bottom,
        left: 0,
        right: 0,
        child: Center(
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xBB000000),
                borderRadius: BorderRadius.circular(100),
              ),
              child: SelectionContainer.disabled(
                // 禁用文本选择
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.none, // 禁用下划线
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  Overlay.of(context).insert(entry);
  Future.delayed(duration, () => entry?.remove());
}

import 'dart:async';

import 'package:flutter/material.dart';

/// 全局根导航 Key。
///
/// 在 main.dart 中传给 GoRouter 作为根 Navigator，
/// 供 showToast 等全局组件在任意时刻获取根 Overlay，
/// 不依赖具体页面，页面销毁后仍可安全调用。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 单个待显示任务
class _ToastTask {
  final String message;
  final Duration duration;
  _ToastTask(this.message, this.duration);
}

/// 等待显示的队列（FIFO）
final List<_ToastTask> _queue = [];

/// 当前正在显示的任务
_ToastTask? _current;

/// 当前 OverlayEntry
OverlayEntry? _currentEntry;

/// 当前显示计时器
Timer? _timer;

/// 显示 Android 风格 Toast（Overlay 方式，顺序队列）
///
/// - 通过全局根 Overlay 展示，页面 pop 后仍可调用，不依赖页面 context
/// - 同一时间只显示一条，其余排队按序播放（Android 原生行为）
/// - 正在显示的同文案 Toast 会重置计时延长展示，已排队的同文案跳过
/// - 根 Overlay 未就绪时（应用启动早期）静默丢弃
void showToast(
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  if (_current?.message == message) {
    // 同文案正在显示：重置计时，延长展示
    _timer?.cancel();
    _timer = Timer(duration, _finish);
    return;
  }
  if (_queue.any((t) => t.message == message)) return; // 已排队，跳过重复
  _queue.add(_ToastTask(message, duration));
  _pump();
}

/// 从队列取一条开始显示
void _pump() {
  if (_current != null || _queue.isEmpty) return;
  _current = _queue.removeAt(0);
  if (_current == null) return;

  final navState = rootNavigatorKey.currentState;
  // Navigator 的 Overlay 是其内部子节点，无法通过 Overlay.of(navCtx) 向上查找，
  // 必须用公开的 overlay getter 获取（navigator.dart: OverlayState? get overlay）
  final overlay = navState?.overlay;
  if (overlay == null) {
    _finish(); // 根未就绪，跳过本条
    return;
  }
  final mq = MediaQuery.maybeOf(navState!.context);
  final message = _current!.message;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) {
      final bottom = (mq?.padding.bottom ?? 0) + 80;
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
  _currentEntry = entry;
  overlay.insert(entry);
  _timer?.cancel();
  _timer = Timer(_current!.duration, _finish);
}

/// 结束当前 Toast，播放下一条
void _finish() {
  _timer?.cancel();
  _timer = null;
  _currentEntry?.remove();
  _currentEntry = null;
  _current = null;
  _pump();
}

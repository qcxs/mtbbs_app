import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/window_state_store.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口初始化（仅 Windows；window_manager 0.5.2 支持 Win/macOS/Linux，
/// 当前按项目目标平台限定 Windows）
///
/// - 最小尺寸 400x720（参考 PiliPlus）
/// - 恢复上次窗口尺寸/位置/最大化状态
/// - 标题栏样式跟随设置（需重启生效）
Future<void> initDesktopWindow({required bool showTitleBar}) async {
  if (!Platform.isWindows) return;
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    minimumSize: const Size(400, 720),
    center: true,
    title: 'MTBBS',
    titleBarStyle: showTitleBar ? TitleBarStyle.normal : TitleBarStyle.hidden,
    backgroundColor: const Color(0xFF121212),
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    final saved = await WindowStateStore.load();
    if (saved != null) {
      if (!saved.maximized) {
        await windowManager.setBounds(
          Rect.fromLTWH(
            saved.position.dx,
            saved.position.dy,
            saved.size.width,
            saved.size.height,
          ),
        );
      } else {
        await windowManager.maximize();
      }
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 窗口状态监听器：挂在 widget 树外层，resize/移动/最大化时自动记忆。
/// 仅 Windows 生效；其他平台不创建。
class WindowStateSaver extends StatefulWidget {
  const WindowStateSaver({super.key, required this.child});

  final Widget child;

  @override
  State<WindowStateSaver> createState() => _WindowStateSaverState();
}

class _WindowStateSaverState extends State<WindowStateSaver>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResized() {
    // 无参回调，需主动查询尺寸
    _saveSize();
  }

  @override
  void onWindowMoved() {
    _savePosition();
  }

  @override
  void onWindowMaximize() {
    WindowStateStore.save(maximized: true);
  }

  @override
  void onWindowUnmaximize() {
    WindowStateStore.save(maximized: false);
  }

  Future<void> _saveSize() async {
    try {
      final size = await windowManager.getSize();
      await WindowStateStore.save(size: size);
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      final pos = await windowManager.getPosition();
      await WindowStateStore.save(position: pos);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

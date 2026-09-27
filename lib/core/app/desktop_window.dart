import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/window_state_store.dart';
import 'package:window_manager/window_manager.dart';

/// 窗口基础标题（MCP 状态作为后缀追加）
const String kBaseWindowTitle = 'MTBBS';

/// 由主题模式推导窗口亮度（system 时取系统当前值）
Brightness windowBrightnessFor(ThemeMode mode) => switch (mode) {
  ThemeMode.light => Brightness.light,
  ThemeMode.dark => Brightness.dark,
  ThemeMode.system => PlatformDispatcher.instance.platformBrightness,
};

/// 桌面窗口初始化（仅 Windows；window_manager 0.5.2 支持 Win/macOS/Linux，
/// 当前按项目目标平台限定 Windows）
///
/// - 最小尺寸 400x720（参考 PiliPlus）
/// - 恢复上次窗口尺寸/位置/最大化状态
/// - **不使用原生标题栏**：标题文字与最小化/最大化/关闭按钮全部由 Flutter
///   自绘（见 `WindowChrome` / `WindowTitleBar`）
/// - [brightness] 决定窗口底色，必须与当前主题一致
///
/// 为什么彻底放弃原生标题栏：Windows 标题栏的底色/字色由 DWM 按
/// 「系统主题 + 应用主题 + 注册表 AppsUseLightTheme」共同决定，
/// `window_manager` 的 `setBrightness` 只在「系统深色 **且** 应用深色」时
/// 才切深色，其余情况一律回落到系统默认值，且该 DWM 属性需窗口重绘才生效。
/// 结果是 App 无法保证标题栏可读（实测出现白底白字、按钮"消失"）。
/// 自绘后颜色完全取自 Flutter 主题，与深浅模式必然一致。
Future<void> initDesktopWindow({required Brightness brightness}) async {
  if (!Platform.isWindows) return;
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    minimumSize: const Size(400, 720),
    center: true,
    title: kBaseWindowTitle,
    titleBarStyle: TitleBarStyle.hidden,
    // 同时关掉系统按钮：系统按钮由 DWM 绘制、颜色不受应用主题控制，
    // 会叠在自绘标题栏上（白底白按钮）
    windowButtonVisibility: false,
    // 与主题一致，避免启动瞬间深底闪一下再变白
    backgroundColor: windowBackgroundColor(brightness),
    skipTaskbar: false,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await syncWindowBackground(brightness);
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

/// 让窗口底色跟随主题。
///
/// 自绘标题栏下无需再调 `setBrightness`（对无原生标题栏的窗口无意义）；
/// 这里只同步窗口底色，避免首帧渲染前露出发白/发黑的背景。
Future<void> syncWindowBackground(Brightness brightness) async {
  if (!Platform.isWindows) return;
  try {
    await windowManager.setBackgroundColor(windowBackgroundColor(brightness));
  } catch (_) {}
}

/// 窗口底色：与主题一致，避免出现与标题栏反色的白底/黑底
Color windowBackgroundColor(Brightness brightness) =>
    brightness == Brightness.dark
    ? const Color(0xFF121212)
    : const Color(0xFFFFFFFF);

/// 在窗口标题上标注 MCP 状态，便于一眼确认服务是否在跑
Future<void> syncMcpWindowTitle({required bool mcpRunning}) async {
  if (!Platform.isWindows) return;
  try {
    await windowManager.setTitle(
      mcpRunning ? '$kBaseWindowTitle（已开启 MCP）' : kBaseWindowTitle,
    );
  } catch (_) {}
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

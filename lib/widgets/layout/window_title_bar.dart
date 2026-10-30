import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/desktop_window.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/widgets/dialog/mcp_quick_dialog.dart';
import 'package:window_manager/window_manager.dart';

/// 给整棵树套上自绘标题栏（仅 Windows）。
///
/// **必须放在 MaterialApp 内部的壳路由里**：标题栏用到 Theme、Navigator 的
/// Overlay（Tooltip）与 Material（InkWell 水波纹）。放在 `MaterialApp.builder`
/// 里会因为缺这三位祖先直接抛 "No Overlay widget found" 把整屏变红。
///
/// **为什么 Windows 一律自绘、不再提供原生标题栏开关**：原生标题栏的底色与
/// 字色由 DWM 按「系统主题 + 应用主题 + 注册表 AppsUseLightTheme」共同决定
/// （`window_manager` 只在系统深色且应用深色时才切深色），App 无法保证可读，
/// 实测会出现白底白字、按钮"看不见"。自绘后颜色一律取自 Flutter 主题，
/// 深浅模式必然可读，因此取消该开关，避免又切回不可控的原生栏。
class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return child;
    return WindowTitleBar(child: child);
  }
}

/// 自绘窗口标题栏 —— 仅 Windows。
///
/// `TitleBarStyle.hidden` 只是让系统**不画标题栏**，标题文字没人画、
/// 三个窗口按钮仍由系统绘制；两者的颜色都不受应用主题控制，于是顶部会变成
/// 一条"白条"——白底白字，看着像什么都没有。
/// 这里把标题、MCP 状态和最小化/最大化/关闭全部自己画，颜色一律取自主题。
///
/// 注意：`initDesktopWindow` 必须同时关掉系统按钮
/// （`windowButtonVisibility: false`），否则系统按钮会叠在我们的按钮上。
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key, required this.child});

  /// 标题栏高度（与常见原生标题栏一致）
  static const double height = 32;

  final Widget child;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _maximized = false;

  /// 窗口几何变化（最大化/还原/拖拽缩放）期间是否禁用 Tooltip。
  ///
  /// Flutter 的 Tooltip 走 OverlayPortal：窗口尺寸在同一帧内变化时，
  /// overlay 子树的旧约束与新 theater 尺寸会短暂不一致，框架
  /// `overlay.dart` 的 `assert(size == theater.size)` 随之触发
  /// （实测 Windows 最大化后鼠标落回首页，悬浮到 IconButton 即复现）。
  /// 这里在几何变化时关闭 TooltipVisibility 并延迟恢复，避开这一窗口期。
  bool _suppressTooltips = false;
  Timer? _tooltipSuppressTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
    AppLogger.i('PAGE', '使用自绘窗口标题栏');
  }

  @override
  void dispose() {
    _tooltipSuppressTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted && value != _maximized) setState(() => _maximized = value);
    } catch (_) {}
  }

  /// 窗口几何变化时，先关掉正在显示的 tooltip，并在随后一小段时间内
  /// 禁止新建 tooltip（`Tooltip` 在 `TooltipVisibility` 不可见时根本不创建
  /// 会走 OverlayPortal 的那层 UI）。
  void _suppressTooltipsTemporarily() {
    Tooltip.dismissAllToolTips();
    _tooltipSuppressTimer?.cancel();
    _tooltipSuppressTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _suppressTooltips) {
        setState(() => _suppressTooltips = false);
      }
    });
    if (!_suppressTooltips) {
      setState(() => _suppressTooltips = true);
    }
  }

  @override
  void onWindowResized() => _suppressTooltipsTemporarily();

  @override
  void onWindowMaximize() {
    _suppressTooltipsTemporarily();
    _syncMaximized();
  }

  @override
  void onWindowUnmaximize() {
    _suppressTooltipsTemporarily();
    _syncMaximized();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 外面套 Material：InkWell 需要有 Material 祖先。
    // TooltipVisibility 覆盖整棵子树（含首页内容里的 IconButton tooltip）。
    return TooltipVisibility(
      visible: !_suppressTooltips,
      child: Material(
        color: cs.surfaceContainer,
        child: Column(
          children: [
            SizedBox(
              height: WindowTitleBar.height,
              child: Row(
                children: [
                  // 左侧：可拖拽的标题区（DragToMoveArea 自带双击最大化）
                  Expanded(
                    child: DragToMoveArea(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              kBaseWindowTitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const _McpBadge(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _WindowButton(
                    icon: Icons.remove,
                    tooltip: '最小化',
                    onPressed: windowManager.minimize,
                  ),
                  _WindowButton(
                    icon: _maximized ? Icons.filter_none : Icons.crop_square,
                    tooltip: _maximized ? '向下还原' : '最大化',
                    onPressed: () async {
                      // 点击瞬间先收掉 tooltip 并进入抑制期：按钮的
                      // tooltip 此时往往正显示，最大化会让它跨窗口尺寸重排。
                      _suppressTooltipsTemporarily();
                      if (await windowManager.isMaximized()) {
                        await windowManager.unmaximize();
                      } else {
                        await windowManager.maximize();
                      }
                    },
                  ),
                  _WindowButton(
                    icon: Icons.close,
                    tooltip: '关闭',
                    danger: true,
                    onPressed: windowManager.close,
                  ),
                ],
              ),
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}

/// MCP 运行状态徽章 —— 常驻显示，开启/关闭两态都可见
///
/// 可点击：打开 MCP 快捷开关弹窗（与 Android 常驻通知、 「我的」页快捷开关
/// 共用同一实现，见 `showMcpQuickDialog`）——开启态用于快速关闭，关闭态用于
/// 快速开启，因此关闭时不能隐藏，否则无处点击开启。
class _McpBadge extends StatelessWidget {
  const _McpBadge();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: McpServerController.instance,
      builder: (context, _) {
        final running = McpServerController.instance.isRunning;
        final bg = running
            ? cs.secondaryContainer
            : cs.surfaceContainerHighest;
        final fg = running ? cs.onSecondaryContainer : cs.onSurfaceVariant;
        return Tooltip(
          message: running ? 'MCP 服务运行中，点击查看 / 快捷关闭' : 'MCP 服务已关闭，点击开启',
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            onTap: showMcpQuickDialog,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                running ? 'MCP 已开启' : 'MCP 已关闭',
                style: TextStyle(fontSize: 11, color: fg),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 窗口按钮（最小化/最大化/关闭）
class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => onPressed(),
        child: SizedBox(
          width: 44,
          height: WindowTitleBar.height,
          child: Icon(
            icon,
            size: 15,
            color: danger ? cs.error : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// 底部面板统一最大宽度（宽屏下不拉满全宽）
const double appSheetMaxWidth = 560;

/// 底部面板统一顶部圆角
const BorderRadius appSheetBorderRadius = BorderRadius.vertical(
  top: Radius.circular(12),
);

/// 打开统一样式的底部面板。
///
/// 固定了圆角、宽屏最大宽度与安全区；[maxHeight] 必须给（列表类内容用
/// `Expanded` 时无上界会直接崩，见 docs/07 #92）。
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeight = 560,
  bool isScrollControlled = true,
  bool useSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    constraints: BoxConstraints(
      maxWidth: appSheetMaxWidth,
      maxHeight: maxHeight,
    ),
    shape: const RoundedRectangleBorder(borderRadius: appSheetBorderRadius),
    builder: builder,
  );
}

/// 底部面板顶部拖拽手柄（小横条）。
///
/// 手柄只是视觉提示，拖拽能力由 `showModalBottomSheet` 的 `enableDrag` 提供。
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key, this.bottom = 4});

  /// 手柄下方留白（个别面板标题栏自带间距时可调小）
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom),
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: cs.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// 标准底部面板骨架：拖拽手柄 + 标题栏（可带右侧操作）+ 分隔线 + 内容。
///
/// 内容区由 [child] 填充并包在 `Expanded` 中，因此调用方必须给面板
/// `maxHeight`（[showAppSheet] 已默认提供）。
class AppSheetScaffold extends StatelessWidget {
  const AppSheetScaffold({
    super.key,
    required this.title,
    this.actions = const [],
    required this.child,
  });

  /// 标题文本
  final String title;

  /// 标题栏右侧、关闭按钮之前的操作按钮（刷新、筛选、新增等）
  final List<Widget> actions;

  /// 内容区（通常为 `ListView` / `SingleChildScrollView`）
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SheetDragHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...actions,
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(child: child),
      ],
    );
  }
}

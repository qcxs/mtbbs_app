import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';

/// 移动端文本选择菜单的避让逻辑。
///
/// Flutter 默认把选择菜单放在选区**上方**；编辑器的 BBCode 工具栏也在输入框
/// 上方，选中第一行时菜单会压住工具栏。这里在「上方会与工具栏重叠」时把菜单
/// 翻到选区下方，保留全部系统菜单项，也不改变布局。
///
/// - iOS 16+ 仍使用系统菜单（位置无法控制，替换会丢系统项）
/// - 仅 Android / 鸿蒙（都由 Flutter 自绘菜单）执行避让，其余平台保持默认
Widget buildEditorSelectionToolbar({
  required EditableTextState editableTextState,
  required GlobalKey toolbarKey,
}) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }

  final anchors = editableTextState.contextMenuAnchors;
  final items = editableTextState.contextMenuButtonItems;

  // 鸿蒙的 AdaptiveTextSelectionToolbar 也走 Android 分支（TextSelectionToolbar），
  // 同样受 anchorAbove/anchorBelow 控制。用 AppCapabilities 判定，避免引用
  // 官方 Flutter 不存在的 TargetPlatform.ohos。
  if (Platform.isAndroid || AppCapabilities.isOhos) {
    final toolbarBox =
        toolbarKey.currentContext?.findRenderObject() as RenderBox?;
    if (toolbarBox != null && toolbarBox.hasSize) {
      final toolbarBottom = toolbarBox
          .localToGlobal(Offset(0, toolbarBox.size.height))
          .dy;
      if (selectionMenuWouldOverlapToolbar(
        selectionTop: anchors.primaryAnchor.dy,
        toolbarBottom: toolbarBottom,
      )) {
        // 把「上方锚点」推到窗口顶部 → 布局器判定上方放不下，
        // 自动改用 secondaryAnchor（选区底部）放到下方
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: TextSelectionToolbarAnchors(
            primaryAnchor: Offset(anchors.primaryAnchor.dx, 0),
            secondaryAnchor: anchors.secondaryAnchor ?? anchors.primaryAnchor,
          ),
          buttonItems: items,
        );
      }
    }
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: anchors,
    buttonItems: items,
  );
}

/// 菜单放在选区上方时是否会压住工具栏。
///
/// [menuClearance] = 菜单高度（Material 44）+ 与选区之间的间距。
@visibleForTesting
bool selectionMenuWouldOverlapToolbar({
  required double selectionTop,
  required double toolbarBottom,
  double menuClearance = 56.0,
}) => selectionTop - toolbarBottom < menuClearance;

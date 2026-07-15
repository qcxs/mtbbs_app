import 'package:flutter/material.dart';
import 'package:mtbbs/config/toolbar_config.dart';

/// 通用工具栏快捷键 Intent — 携带具体 [ToolbarAction]
class EditorToolbarIntent extends Intent {
  final ToolbarAction action;
  const EditorToolbarIntent(this.action);
}

/// 编辑器 Esc 拦截 Intent — 有未保存内容时先确认再退出
class EditorEscapeIntent extends Intent {}

/// Ctrl+V 粘贴 Intent — 拦截并检测剪贴板图片
class PasteIntent extends Intent {}

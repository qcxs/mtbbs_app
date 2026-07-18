/// 工具栏项配置 — 单一数据源
///
/// 所有工具栏项的枚举定义、默认名称、默认快捷键集中在此处。
/// BBCodeToolbar 的渲染、EditorPage 的快捷键绑定、设置页的排序/显隐
/// 全部从此文件的配置衍生，三者不再各自独立定义。
library;

import '../models/managed_item.dart';

/// 工具栏操作枚举
///
/// 注意：移除某值前确认 BBCode 解析侧（bbcode_parser / html2bbcode）
/// 不依赖它。例如 [listA] 已从工具栏移除，但 `[list=a]` BBCode 仍可正常渲染。
enum ToolbarAction {
  undo,
  redo,
  bold,
  italic,
  underline,
  strikethrough,
  quote,
  hide,
  free,
  code,
  link,
  image,
  imageLongPress,
  hr,
  emoji,
  color,
  backcolor,
  alignLeft,
  alignCenter,
  alignRight,
  listUl,
  listOl,
  select,
  fontSize,
  history,
  clearStyles,
  mtImage,
}

/// 工具栏项的默认配置
class ToolbarItemConfig {
  final ToolbarAction action;
  final String id;
  final String name;
  final String defaultShortcut;
  final bool defaultVisible;

  const ToolbarItemConfig({
    required this.action,
    required this.id,
    required this.name,
    this.defaultShortcut = '',
    this.defaultVisible = true,
  });
}

/// 单一数据源：所有工具栏项的默认配置
///
/// 顺序即默认顺序。`defaultVisible: false` 的项首次使用时默认隐藏。
/// `imageLongPress` 不在列表中，因为它不是独立按钮（是 image 的长按操作）。
const allToolbarItemConfigs = [
  // ── 默认显示（第一组） ──
  ToolbarItemConfig(action: ToolbarAction.undo, id: 'undo', name: '撤销'),
  ToolbarItemConfig(action: ToolbarAction.redo, id: 'redo', name: '重做'),
  ToolbarItemConfig(
    action: ToolbarAction.select,
    id: 'select',
    name: '选中',
    defaultShortcut: 'Ctrl+D',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.clearStyles,
    id: 'clearStyles',
    name: '清除样式',
    defaultShortcut: 'Ctrl+\\',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.bold,
    id: 'bold',
    name: '加粗',
    defaultShortcut: 'Ctrl+B',
  ),
  ToolbarItemConfig(action: ToolbarAction.link, id: 'link', name: '链接'),
  ToolbarItemConfig(action: ToolbarAction.image, id: 'image', name: '图片'),
  ToolbarItemConfig(action: ToolbarAction.emoji, id: 'emoji', name: '表情'),
  ToolbarItemConfig(action: ToolbarAction.quote, id: 'quote', name: '引用'),
  ToolbarItemConfig(action: ToolbarAction.hide, id: 'hide', name: '隐藏'),
  ToolbarItemConfig(action: ToolbarAction.free, id: 'free', name: '免费'),
  ToolbarItemConfig(action: ToolbarAction.code, id: 'code', name: '代码'),
  ToolbarItemConfig(action: ToolbarAction.history, id: 'history', name: '历史'),
  ToolbarItemConfig(
    action: ToolbarAction.mtImage,
    id: 'mtImage',
    name: 'MT图床',
    defaultVisible: true,
  ),

  // ── 之后的项 ──
  ToolbarItemConfig(
    action: ToolbarAction.italic,
    id: 'italic',
    name: '斜体',
    defaultShortcut: 'Ctrl+I',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.underline,
    id: 'underline',
    name: '下划线',
    defaultShortcut: 'Ctrl+U',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.strikethrough,
    id: 'strikethrough',
    name: '删除线',
    defaultShortcut: 'Ctrl+Shift+S',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.color,
    id: 'color',
    name: '颜色',
    defaultShortcut: 'Ctrl+Shift+C',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.backcolor,
    id: 'backcolor',
    name: '背景色',
    defaultShortcut: 'Ctrl+Shift+B',
  ),
  ToolbarItemConfig(action: ToolbarAction.hr, id: 'hr', name: '分隔线'),
  ToolbarItemConfig(action: ToolbarAction.fontSize, id: 'fontSize', name: '字号'),

  // ── 默认隐藏 ──
  ToolbarItemConfig(
    action: ToolbarAction.alignLeft,
    id: 'alignLeft',
    name: '左对齐',
    defaultShortcut: 'Ctrl+L',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.alignCenter,
    id: 'alignCenter',
    name: '居中',
    defaultShortcut: 'Ctrl+E',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.alignRight,
    id: 'alignRight',
    name: '右对齐',
    defaultShortcut: 'Ctrl+R',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.listUl,
    id: 'listUl',
    name: '无序',
    defaultShortcut: 'Ctrl+Shift+L',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.listOl,
    id: 'listOl',
    name: '有序',
    defaultVisible: false,
  ),
];

/// 生成默认的工具栏项列表
List<ManagedItem> defaultToolbarItems() => allToolbarItemConfigs
    .map((c) => ManagedItem(id: c.id, name: c.name, visible: c.defaultVisible))
    .toList();

/// 生成默认的工具栏快捷键映射（仅含有关联快捷键的项）
Map<String, String> defaultToolbarShortcuts() => {
  for (final c in allToolbarItemConfigs.where(
    (c) => c.defaultShortcut.isNotEmpty,
  ))
    c.id: c.defaultShortcut,
};

/// 根据 item id 解析对应的 ToolbarAction
ToolbarAction? resolveToolbarAction(String id) {
  for (final config in allToolbarItemConfigs) {
    if (config.id == id) return config.action;
  }
  return null;
}

/// 检查 id 是否为有效的工具栏项
bool isValidToolbarItemId(String id) =>
    allToolbarItemConfigs.any((c) => c.id == id);

/// 工具栏项配置 — 单一数据源
///
/// 工具栏分两类（按项是否带 `template` 区分）：
/// - **模板项**：把选中文本按文本模板包裹，如 `[b]${selectText}[/b]`。
///   用户可在设置页新增自己的模板。见 [kSelectTextToken]。
/// - **复杂项**：需要弹窗/选择面板/上传等交互（图片、表情、链接、颜色…），
///   由 [ToolbarAction] 枚举 + 编辑器 `_handleToolbarAction` 处理。
///
/// `BBCodeToolbar` 的渲染、`EditorPage` 的快捷键绑定、设置页的排序/显隐
/// 全部从此文件的配置衍生，三者不再各自独立定义。
library;

import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/core/app/default_config.dart';

/// 模板占位符：应用模板时替换为选中文本；无选中则替换为空串。
const String kSelectTextToken = r'${selectText}';

/// 图片按钮长按（插入图片 URL）的伪 id。
///
/// 它不是工具栏项（无按钮、不参与排序），仅作为长按动作的派发标识。
const String kImageLongPressId = 'imageLongPress';

/// 工具栏末尾「设置」按钮的伪 id。
///
/// 该按钮**固定追加在工具栏末尾**、不受工具栏设置（排序/显隐）影响，
/// 因此不是工具栏项，也不出现在 `allToolbarItemConfigs` 中。
const String kEditorSettingsId = 'editorSettings';

/// 复杂工具栏操作枚举
///
/// 只保留需要弹窗/面板/上传等交互的项；纯文本包裹的简单项已改为
/// 模板项（见 [ToolbarItemConfig.template]），不再需要枚举值。
enum ToolbarAction {
  undo,
  redo,
  select,
  clearStyles,
  link,
  image,
  imageLongPress,
  emoji,
  color,
  backcolor,
  fontSize,
  history,
  editHistory,
  mdImport,
  mtImage,
  attach,
}

/// 工具栏项的默认配置
class ToolbarItemConfig {
  /// 复杂项对应的动作；模板项为 null
  final ToolbarAction? action;

  final String id;
  final String name;

  /// 模板项：含 [kSelectTextToken] 的文本模板；复杂项为 null
  final String? template;

  /// 模板项的按钮文字（如 `B`、`H1`）；复杂项用图标，留空即可
  final String label;

  /// 分隔线分组：相邻两项分组不同时插入分隔线
  final String group;

  /// 模板项且无占位符时，按「块级插入」处理（必要时补换行），
  /// 用于 `[hr]`、表格骨架这类自闭合/骨架模板
  final bool block;

  final String defaultShortcut;
  final bool defaultVisible;

  const ToolbarItemConfig({
    this.action,
    required this.id,
    required this.name,
    this.template,
    this.label = '',
    this.group = 'misc',
    this.block = false,
    this.defaultShortcut = '',
    this.defaultVisible = true,
  });

  bool get isTemplate => template != null;

  /// 序列化进 [ManagedItem.data] 的自定义字段
  Map<String, dynamic> get data => {
    if (template != null) 'template': template,
    if (label.isNotEmpty) 'label': label,
    'group': group,
    if (block) 'block': true,
  };
}

/// 单一数据源：所有内置工具栏项的默认配置
///
/// 顺序即默认顺序。`defaultVisible: false` 的项首次使用时默认隐藏。
/// `imageLongPress` 不在列表中，因为它不是独立按钮（是 image 的长按操作）。
///
/// **默认快捷键取自 Typora（Windows）官方默认表**，只映射两边都有的能力
/// （见 docs/05「默认快捷键与 Typora 对齐」）。
/// 真正的落地值以 `assets/config/toolbar.json` 为准，此处只是 JSON 读取失败时的兜底，
/// **两处必须保持一致**（测试 `shortcut_helper_test.dart` 会逐字校验）。
const allToolbarItemConfigs = [
  // ── 默认显示（第一组） ──
  ToolbarItemConfig(
    action: ToolbarAction.undo,
    id: 'undo',
    name: '撤销',
    group: 'undo',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.redo,
    id: 'redo',
    name: '重做',
    group: 'undo',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.select,
    id: 'select',
    name: '选中',
    group: 'select',
    defaultShortcut: 'Ctrl+D',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.clearStyles,
    id: 'clearStyles',
    name: '清除样式',
    group: 'clearStyles',
    defaultShortcut: 'Ctrl+\\',
  ),
  ToolbarItemConfig(
    id: 'bold',
    name: '加粗',
    template: r'[b]${selectText}[/b]',
    label: 'B',
    group: 'style',
    defaultShortcut: 'Ctrl+B',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.link,
    id: 'link',
    name: '链接',
    group: 'insert',
    defaultShortcut: 'Ctrl+K',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.image,
    id: 'image',
    name: '图片',
    group: 'insert',
    defaultShortcut: 'Ctrl+Shift+I',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.emoji,
    id: 'emoji',
    name: '表情',
    group: 'emoji',
  ),
  ToolbarItemConfig(
    id: 'quote',
    name: '引用',
    template: r'[quote]${selectText}[/quote]',
    label: '引用',
    group: 'container',
    defaultShortcut: 'Ctrl+Shift+Q',
  ),
  ToolbarItemConfig(
    id: 'hide',
    name: '隐藏',
    template: r'[hide]${selectText}[/hide]',
    label: '隐藏',
    group: 'container',
  ),
  ToolbarItemConfig(
    id: 'free',
    name: '免费',
    template: r'[free]${selectText}[/free]',
    label: '免费',
    group: 'container',
  ),
  ToolbarItemConfig(
    id: 'code',
    name: '代码',
    template: r'[code]${selectText}[/code]',
    label: '代码',
    group: 'container',
    defaultShortcut: 'Ctrl+Shift+K',
  ),
  ToolbarItemConfig(
    id: 'table',
    name: '表格',
    template:
        '[table][tr][td]表头1[/td][td]表头2[/td][/tr]\n'
        '[tr][td]内容[/td][td]内容[/td][/tr][/table]',
    label: '表格',
    group: 'insert',
    block: true,
    defaultShortcut: 'Ctrl+T',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.history,
    id: 'history',
    name: '历史',
    group: 'history',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.editHistory,
    id: 'editHistory',
    name: '编辑历史',
    group: 'meta',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.mdImport,
    id: 'mdImport',
    name: '导入MD',
    group: 'meta',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.mtImage,
    id: 'mtImage',
    name: 'MT图床',
    group: 'mtImage',
    defaultVisible: true,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.attach,
    id: 'attach',
    name: '附件',
    group: 'attach',
    defaultVisible: true,
  ),

  // ── 之后的项 ──
  ToolbarItemConfig(
    id: 'italic',
    name: '斜体',
    template: r'[i]${selectText}[/i]',
    label: 'I',
    group: 'style',
    defaultShortcut: 'Ctrl+I',
  ),
  ToolbarItemConfig(
    id: 'underline',
    name: '下划线',
    template: r'[u]${selectText}[/u]',
    label: 'U',
    group: 'style',
    defaultShortcut: 'Ctrl+U',
  ),
  ToolbarItemConfig(
    id: 'strikethrough',
    name: '删除线',
    template: r'[s]${selectText}[/s]',
    label: 'S',
    group: 'style',
    defaultShortcut: 'Alt+Shift+5',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.color,
    id: 'color',
    name: '颜色',
    group: 'color',
    defaultShortcut: 'Ctrl+Shift+C',
  ),
  ToolbarItemConfig(
    action: ToolbarAction.backcolor,
    id: 'backcolor',
    name: '背景色',
    group: 'color',
    defaultShortcut: 'Ctrl+Shift+B',
  ),
  ToolbarItemConfig(
    id: 'hr',
    name: '分隔线',
    template: '[hr]',
    label: 'HR',
    group: 'insert',
    block: true,
  ),
  ToolbarItemConfig(
    action: ToolbarAction.fontSize,
    id: 'fontSize',
    name: '字号',
    group: 'select',
  ),

  // ── 默认隐藏 ──
  // 对齐没有 Typora 对应项，且刻意留空：快捷键与显隐解耦后，
  // 留着 Ctrl+L/E/R 会平白占用三个常用键
  ToolbarItemConfig(
    id: 'alignLeft',
    name: '左对齐',
    template: r'[align=left]${selectText}[/align]',
    label: '左',
    group: 'align',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    id: 'alignCenter',
    name: '居中',
    template: r'[align=center]${selectText}[/align]',
    label: '中',
    group: 'align',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    id: 'alignRight',
    name: '右对齐',
    template: r'[align=right]${selectText}[/align]',
    label: '右',
    group: 'align',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    id: 'listUl',
    name: '无序',
    template: r'[list]${selectText}[/list]',
    label: '•',
    group: 'list',
    defaultShortcut: 'Ctrl+Shift+]',
    defaultVisible: false,
  ),
  ToolbarItemConfig(
    id: 'listOl',
    name: '有序',
    template: r'[list=1]${selectText}[/list]',
    label: '1.',
    group: 'list',
    defaultShortcut: 'Ctrl+Shift+[',
    defaultVisible: false,
  ),
];

/// 生成默认的工具栏项列表
/// 优先从 [DefaultConfig] 加载（对应 toolbar.json），失败时用代码内嵌默认值。
List<ManagedItem> defaultToolbarItems() {
  final fromConfig = DefaultConfig.instance.defaultToolbarItems;
  if (fromConfig.isNotEmpty) return fromConfig;
  return allToolbarItemConfigs
      .map(
        (c) => ManagedItem(
          id: c.id,
          name: c.name,
          visible: c.defaultVisible,
          data: c.data,
        ),
      )
      .toList();
}

/// 生成默认的工具栏快捷键映射（仅含有关联快捷键的项）
/// 优先从 [DefaultConfig] 加载，失败时用代码内嵌默认值。
Map<String, String> defaultToolbarShortcuts() {
  final fromConfig = DefaultConfig.instance.defaultToolbarShortcuts;
  if (fromConfig.isNotEmpty) return fromConfig;
  return {
    for (final c in allToolbarItemConfigs.where(
      (c) => c.defaultShortcut.isNotEmpty,
    ))
      c.id: c.defaultShortcut,
  };
}

/// 根据 item id 解析对应的 [ToolbarAction]（模板项返回 null）
ToolbarAction? resolveToolbarAction(String id) {
  for (final config in allToolbarItemConfigs) {
    if (config.id == id) return config.action;
  }
  return null;
}

/// 检查 id 是否为**内置**工具栏项（用户自定义模板项不在其中）
bool isBuiltinToolbarItemId(String id) =>
    allToolbarItemConfigs.any((c) => c.id == id);

/// 检查 id 是否为有效的工具栏项（内置项，用于持久化剪枝）
bool isValidToolbarItemId(String id) => isBuiltinToolbarItemId(id);

/// 取出模板项的内置/自定义模板文本；复杂项返回 null
String? toolbarTemplateOf(ManagedItem item) {
  final tpl = item.data?['template'];
  if (tpl is String && tpl.isNotEmpty) return tpl;
  return null;
}

/// 模板项是否为「块级插入」（无占位符时按 insertBlockTag 语义，必要时补换行）
bool toolbarIsBlockOf(ManagedItem item) => item.data?['block'] == true;

/// 模板项按钮显示的文字：优先用户设置的 label，否则退回名称
String toolbarLabelOf(ManagedItem item) {
  final label = item.data?['label'];
  if (label is String && label.isNotEmpty) return label;
  return item.name;
}

/// 工具栏项的分隔线分组；用户自定义项统一归入 `custom`
String toolbarGroupOf(ManagedItem item) {
  final group = item.data?['group'];
  if (group is String && group.isNotEmpty) return group;
  for (final config in allToolbarItemConfigs) {
    if (config.id == item.id) return config.group;
  }
  return 'custom';
}

/// 是否为用户自定义模板项（非内置 id）
bool isCustomToolbarItem(ManagedItem item) =>
    !isBuiltinToolbarItemId(item.id) && toolbarTemplateOf(item) != null;

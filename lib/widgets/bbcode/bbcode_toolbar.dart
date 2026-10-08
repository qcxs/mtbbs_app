import 'package:flutter/material.dart';
import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/models/managed_item.dart';

part 'bbcode_toolbar_build.dart';
part 'bbcode_toolbar_widgets.dart';

/// BBCode 格式工具栏 — 数据驱动渲染
///
/// 从 [items] 中获取排序和显隐，从 [shortcuts] 中获取快捷键提示。
/// 不再硬编码任何按钮，完全由调用方（EditorPage）传入数据。
class BBCodeToolbar extends StatelessWidget {
  final BBCodeToolbarController controller;
  final bool canUndo;
  final bool canRedo;
  final List<ManagedItem> items;
  final Map<String, String> shortcuts;

  /// 角标：item id → 数量（如「图片」「附件」已上传的数量）。
  ///
  /// 有角标的项**无视用户的隐藏设置强制显示**：既然已经上传过图片/附件，
  /// 入口就应当可见（否则用户既看不到提示、也进不去管理面板）。
  /// 无角标时隐藏设置照常生效。
  final Map<String, int> badges;

  const BBCodeToolbar({
    super.key,
    required this.controller,
    this.canUndo = false,
    this.canRedo = false,
    required this.items,
    required this.shortcuts,
    this.badges = const {},
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 末尾固定追加「设置」按钮，因此即使所有项都被隐藏，工具栏仍会渲染；
    // 带角标的项（已上传图片/附件）同样强制显示。
    final visibleItems = items
        .where((e) => e.visible || (badges[e.id] ?? 0) > 0)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        alignment: WrapAlignment.start,
        children: _buildButtons(visibleItems, cs),
      ),
    );
  }
}

// ==================== 颜色面板 ====================

/// 常用颜色常量
const bbcodeCommonColors = <Color>[
  Color(0xFF000000), // 黑
  Color(0xFF808080), // 灰
  Color(0xFFC0C0C0), // 银
  Color(0xFFFFFFFF), // 白
  Color(0xFF800000), // 栗
  Color(0xFFFF0000), // 红
  Color(0xFFFF6600), // 橙
  Color(0xFFFFCC00), // 黄
  Color(0xFF008000), // 绿
  Color(0xFF00FF00), // 亮绿
  Color(0xFF008080), // 青
  Color(0xFF00FFFF), // 亮青
  Color(0xFF000080), // 藏蓝
  Color(0xFF0000FF), // 蓝
  Color(0xFF800080), // 紫
  Color(0xFFFF00FF), // 粉
];

part of 'bbcode_toolbar.dart';

extension _BBCodeToolbarBuild on BBCodeToolbar {
  List<Widget> _buildButtons(List<ManagedItem> visibleItems, ColorScheme cs) {
    final widgets = <Widget>[];
    String? lastGroup;
    for (final item in visibleItems) {
      final template = toolbarTemplateOf(item);
      final action = template == null ? resolveToolbarAction(item.id) : null;
      // 既不是模板项、也不是已知复杂项 → 跳过（脏数据保护）
      if (template == null && action == null) continue;

      final group = toolbarGroupOf(item);
      if (lastGroup != null && group != lastGroup) {
        widgets.add(_separator(cs));
      }
      lastGroup = group;

      widgets.add(
        template != null
            ? _buildTemplateButton(item, cs)
            : _buildButton(action!, item, cs),
      );
    }

    // 固定末尾：设置按钮（不受工具栏设置影响，始终渲染）
    if (showSettingsButton) {
      if (widgets.isNotEmpty) widgets.add(_separator(cs));
      widgets.add(_buildSettingsButton(cs));
    }
    return widgets;
  }

  /// 固定追加在工具栏末尾的「设置」按钮（打开编辑器设置页）
  Widget _buildSettingsButton(ColorScheme cs) {
    return _toolBtn(
      icon: Icons.settings_outlined,
      tooltip: '编辑器设置',
      id: kEditorSettingsId,
      name: '设置',
      cs: cs,
    );
  }

  /// 模板项按钮：显示 label（用户文字标签），tooltip 带完整名称与快捷键
  Widget _buildTemplateButton(ManagedItem item, ColorScheme cs) {
    final label = toolbarLabelOf(item);
    return _toolBtn(
      label: label,
      tooltip: _tooltip(item),
      id: item.id,
      // label 与名称相同时不重复显示副标题
      name: label == item.name ? '' : item.name,
      cs: cs,
    );
  }

  Widget _buildButton(ToolbarAction action, ManagedItem item, ColorScheme cs) {
    final tooltip = _tooltip(item);
    final enabled = _isEnabled(action);

    switch (action) {
      case ToolbarAction.undo:
        return _toolBtn(
          icon: Icons.undo,
          tooltip: tooltip,
          id: item.id,
          enabled: enabled && canUndo,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.redo:
        return _toolBtn(
          icon: Icons.redo,
          tooltip: tooltip,
          id: item.id,
          enabled: enabled && canRedo,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.select:
        return _toolBtn(
          icon: Icons.near_me,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.clearStyles:
        return _toolBtn(
          icon: Icons.cleaning_services_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.link:
        return _toolBtn(
          icon: Icons.link,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.image:
        return _toolBtn(
          icon: Icons.image,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          badge: badges[item.id] ?? 0,
          onLongPress: () => controller.onAction(kImageLongPressId),
          cs: cs,
        );
      case ToolbarAction.emoji:
        return _toolBtn(
          icon: Icons.emoji_emotions,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.color:
        return _toolBtn(
          icon: Icons.palette_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.backcolor:
        return _toolBtn(
          icon: Icons.format_color_fill,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.fontSize:
        return _toolBtn(
          icon: Icons.format_size,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.history:
        return _toolBtn(
          icon: Icons.history,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.editHistory:
        return _toolBtn(
          icon: Icons.manage_history,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.mdImport:
        return _toolBtn(
          icon: Icons.article_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.mtImage:
        return _toolBtn(
          icon: Icons.cloud_upload_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.quickReply:
        return _toolBtn(
          icon: Icons.quickreply_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.attach:
        return _toolBtn(
          icon: Icons.attach_file_outlined,
          tooltip: tooltip,
          id: item.id,
          name: item.name,
          badge: badges[item.id] ?? 0,
          cs: cs,
        );
      case ToolbarAction.imageLongPress:
        return const SizedBox.shrink(); // 仅用作长按触发，不渲染按钮
    }
  }

  String _tooltip(ManagedItem item) {
    final shortcut = shortcuts[item.id] ?? '';
    return shortcut.isNotEmpty ? '${item.name} ($shortcut)' : item.name;
  }

  bool _isEnabled(ToolbarAction action) => true;

  Widget _separator(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Container(width: 1, color: cs.outlineVariant),
    );
  }

  Widget _toolBtn({
    IconData? icon,
    String? label,
    required String tooltip,
    required String id,
    bool enabled = true,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strike = false,
    String name = '',
    int badge = 0,
    VoidCallback? onLongPress,
    required ColorScheme cs,
  }) {
    final Widget child;
    if (icon != null) {
      final color = enabled
          ? cs.onSurfaceVariant
          : cs.onSurfaceVariant.withValues(alpha: 0.4);
      final iconWidget = Icon(icon, size: 16, color: color);
      child = Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 有角标时在图标右上角叠一个计数（如已上传的图片/附件数量）
            if (badge > 0)
              Badge.count(
                count: badge,
                textStyle: const TextStyle(fontSize: 9, height: 1.1),
                child: iconWidget,
              )
            else
              iconWidget,
            if (name.isNotEmpty)
              Text(
                name,
                style: TextStyle(
                  fontSize: 8,
                  color: cs.onSurfaceVariant,
                  height: 1.1,
                ),
                maxLines: 1,
              ),
          ],
        ),
      );
    } else {
      child = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label ?? '',
              style: TextStyle(
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                decoration: underline
                    ? TextDecoration.underline
                    : strike
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (name.isNotEmpty)
              Text(
                name,
                style: TextStyle(
                  fontSize: 8,
                  color: cs.onSurfaceVariant,
                  height: 1.1,
                ),
                maxLines: 1,
              ),
          ],
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: enabled ? () => controller.onAction(id) : null,
            onLongPress: onLongPress,
            // 不画背景：禁用态只用图标透明度表达（曾给禁用项加底色，
            // 导致撤销/重做与其它按钮底色不一致）
            child: child,
          ),
        ),
      ),
    );
  }
}

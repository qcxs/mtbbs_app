part of 'bbcode_toolbar.dart';

extension _BBCodeToolbarBuild on BBCodeToolbar {
  List<Widget> _buildButtons(List<ManagedItem> visibleItems, ColorScheme cs) {
    final widgets = <Widget>[];
    for (int i = 0; i < visibleItems.length; i++) {
      final item = visibleItems[i];
      final action = resolveToolbarAction(item.id);
      if (action == null) continue;

      if (i > 0) {
        final prevAction = resolveToolbarAction(visibleItems[i - 1].id);
        if (prevAction != null && _shouldAddSeparator(action, prevAction)) {
          widgets.add(_separator(cs));
        }
      }

      widgets.add(_buildButton(action, item, cs));
    }
    return widgets;
  }

  /// 判断两组间是否需要分隔线
  bool _shouldAddSeparator(ToolbarAction current, ToolbarAction prev) {
    const groups = [
      {ToolbarAction.undo, ToolbarAction.redo},
      {
        ToolbarAction.bold,
        ToolbarAction.italic,
        ToolbarAction.underline,
        ToolbarAction.strikethrough,
      },
      {ToolbarAction.color, ToolbarAction.backcolor},
      {
        ToolbarAction.quote,
        ToolbarAction.hide,
        ToolbarAction.free,
        ToolbarAction.code,
      },
      {
        ToolbarAction.alignLeft,
        ToolbarAction.alignCenter,
        ToolbarAction.alignRight,
      },
      {ToolbarAction.listUl, ToolbarAction.listOl},
      {ToolbarAction.link, ToolbarAction.image, ToolbarAction.hr},
      {ToolbarAction.emoji},
      {ToolbarAction.select, ToolbarAction.fontSize},
      {ToolbarAction.history},
    ];
    for (final group in groups) {
      if (group.contains(prev) && group.contains(current)) return false;
    }
    return true;
  }

  Widget _buildButton(ToolbarAction action, ManagedItem item, ColorScheme cs) {
    final shortcut = shortcuts[item.id] ?? '';
    final tooltip = shortcut.isNotEmpty
        ? '${item.name} ($shortcut)'
        : item.name;
    final enabled = _isEnabled(action);

    switch (action) {
      case ToolbarAction.undo:
        return _toolBtn(
          icon: Icons.undo,
          tooltip: tooltip,
          action: action,
          enabled: enabled && canUndo,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.redo:
        return _toolBtn(
          icon: Icons.redo,
          tooltip: tooltip,
          action: action,
          enabled: enabled && canRedo,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.bold:
        return _toolBtn(
          label: 'B',
          tooltip: tooltip,
          action: action,
          bold: true,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.italic:
        return _toolBtn(
          label: 'I',
          tooltip: tooltip,
          action: action,
          italic: true,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.underline:
        return _toolBtn(
          label: 'U',
          tooltip: tooltip,
          action: action,
          underline: true,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.strikethrough:
        return _toolBtn(
          label: 'S',
          tooltip: tooltip,
          action: action,
          strike: true,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.color:
        return _toolBtn(
          icon: Icons.palette_outlined,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.backcolor:
        return _toolBtn(
          icon: Icons.format_color_fill,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.quote:
        return _toolBtn(
          icon: Icons.format_quote,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.hide:
        return _toolBtn(
          icon: Icons.visibility_off,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.free:
        return _toolBtn(
          icon: Icons.card_giftcard,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.code:
        return _toolBtn(
          icon: Icons.code,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.alignLeft:
        return _toolBtn(
          icon: Icons.format_align_left,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.alignCenter:
        return _toolBtn(
          icon: Icons.format_align_center,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.alignRight:
        return _toolBtn(
          icon: Icons.format_align_right,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.listUl:
        return _toolBtn(
          icon: Icons.format_list_bulleted,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.listOl:
        return _toolBtn(
          icon: Icons.format_list_numbered,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.link:
        return _toolBtn(
          icon: Icons.link,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.image:
        return _toolBtn(
          icon: Icons.image,
          tooltip: tooltip,
          action: action,
          name: item.name,
          onLongPress: () => controller.onAction(ToolbarAction.imageLongPress),
          cs: cs,
        );
      case ToolbarAction.hr:
        return _toolBtn(
          label: 'HR',
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.emoji:
        return _toolBtn(
          icon: Icons.emoji_emotions,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.select:
        return _toolBtn(
          icon: Icons.near_me,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.fontSize:
        return _toolBtn(
          icon: Icons.format_size,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.history:
        return _toolBtn(
          icon: Icons.history,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.mtImage:
        return _toolBtn(
          icon: Icons.cloud_upload_outlined,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.imageLongPress:
        return const SizedBox.shrink(); // 仅用作长按触发，不渲染按钮
      case ToolbarAction.clearStyles:
        return _toolBtn(
          icon: Icons.cleaning_services_outlined,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
      case ToolbarAction.attach:
        return _toolBtn(
          icon: Icons.attach_file_outlined,
          tooltip: tooltip,
          action: action,
          name: item.name,
          cs: cs,
        );
    }
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
    required ToolbarAction action,
    bool enabled = true,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strike = false,
    String name = '',
    VoidCallback? onLongPress,
    required ColorScheme cs,
  }) {
    final Widget child;
    if (icon != null) {
      child = Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: enabled
                  ? cs.onSurfaceVariant
                  : cs.onSurfaceVariant.withValues(alpha: 0.4),
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
            onTap: enabled ? () => controller.onAction(action) : null,
            onLongPress: onLongPress,
            child: Container(
              decoration: BoxDecoration(
                color: enabled ? null : cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

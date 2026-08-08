part of 'editor_page.dart';

/// 顶栏提示系统 — 添加/关闭提示、Emoji 兼容性警告与提示条构建。
extension on _EditorPageState {
  /// 添加顶栏提示（自动去重）
  void _addHint(String id, String message) {
    if (_dismissedHints.contains(id)) return;
    // 通过 key 强制重建 HintBar widget
    _setState(() {});
  }

  /// 关闭指定提示
  void _dismissHint(String id) {
    _dismissedHints.add(id);
    _setState(() {});
  }

  /// 检测内容是否包含不兼容的 Emoji（4 字节 UTF-8 字符）
  bool _checkIncompatibleEmoji(String text) {
    for (final rune in text.runes) {
      if (rune > 0xFFFF) return true;
    }
    return false;
  }

  /// 更新 Emoji 警告提示状态
  void _updateEmojiWarning() {
    final hasEmoji =
        _checkIncompatibleEmoji(_titleCtl.text) ||
        _checkIncompatibleEmoji(_contentCtl.text);
    if (hasEmoji != _hasEmojiWarning) {
      _setState(() => _hasEmojiWarning = hasEmoji);
      if (hasEmoji) {
        _dismissedHints.remove('emoji'); // 重新出现时重新显示
      }
    }
  }

  /// 构建顶栏提示条
  Widget _buildHintBar() {
    final cs = Theme.of(context).colorScheme;
    final hints = <EditorHintData>[];

    // Emoji 警告
    if (_hasEmojiWarning && !_dismissedHints.contains('emoji')) {
      hints.add(
        EditorHintData(
          id: 'emoji',
          icon: Icons.warning_amber_rounded,
          color: cs.onSurfaceVariant,
          message: '输入内容包含不兼容的 Emoji，提交后可能被截断',
        ),
      );
    }

    // 意外关闭
    if (!_dismissedHints.contains('unexpected_close')) {
      final historyProv = context.read<EditorHistoryProvider>();
      if (historyProv.hasSession(_sessionKey)) {
        hints.add(
          EditorHintData(
            id: 'unexpected_close',
            icon: Icons.info_outline,
            color: cs.onSurfaceVariant,
            message: '上次编辑器意外关闭，可在编辑历史中恢复',
          ),
        );
      }
    }

    return EditorHintBar(hints: hints, onDismiss: _dismissHint);
  }
}

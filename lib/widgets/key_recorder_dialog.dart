import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 快捷键录入对话框
///
/// 用户按下键盘组合键，界面实时显示按下的按键，
/// 点击确定后以字符串形式返回（如 `"Ctrl+T"`、`"F5"`、`"Escape"`）。
class KeyRecorderDialog extends StatefulWidget {
  final String? initial;

  const KeyRecorderDialog({super.key, this.initial});

  @override
  State<KeyRecorderDialog> createState() => _KeyRecorderDialogState();
}

class _KeyRecorderDialogState extends State<KeyRecorderDialog> {
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _meta = false;
  LogicalKeyboardKey? _key;
  bool _recorded = false;

  /// 按键 → 可读标签映射
  static String _keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
    if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.backquote) return '`';
    if (key == LogicalKeyboardKey.minus) return '-';
    if (key == LogicalKeyboardKey.equal) return '=';
    if (key == LogicalKeyboardKey.bracketLeft) return '[';
    if (key == LogicalKeyboardKey.bracketRight) return ']';
    if (key == LogicalKeyboardKey.semicolon) return ';';
    if (key == LogicalKeyboardKey.quote) return "'";
    if (key == LogicalKeyboardKey.comma) return ',';
    if (key == LogicalKeyboardKey.period) return '.';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.backslash) return '\\';
    // 字母和数字
    final keyId = key.keyLabel;
    if (keyId.length == 1) return keyId.toUpperCase();
    return keyId;
  }

  /// 构建可读的快捷键字符串
  String get _displayString {
    final parts = <String>[];
    if (_ctrl) parts.add('Ctrl');
    if (_alt) parts.add('Alt');
    if (_shift) parts.add('Shift');
    if (_meta) parts.add('Meta');
    if (_key != null) parts.add(_keyLabel(_key!));
    return parts.isNotEmpty ? parts.join(' + ') : '';
  }

  /// 构建存储用的序列化字符串
  String get _serialized {
    final parts = <String>[];
    if (_ctrl) parts.add('Ctrl');
    if (_alt) parts.add('Alt');
    if (_shift) parts.add('Shift');
    if (_meta) parts.add('Meta');
    if (_key != null) {
      parts.add(_keyLabel(_key!).replaceAll(' ', ''));
    }
    return parts.join('+');
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyRepeatEvent) return KeyEventResult.handled;

    if (event is KeyDownEvent) {
      setState(() {
        if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight) {
          _ctrl = true;
        } else if (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight) {
          _alt = true;
        } else if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
            event.logicalKey == LogicalKeyboardKey.shiftRight) {
          _shift = true;
        } else if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
            event.logicalKey == LogicalKeyboardKey.metaRight) {
          _meta = true;
        } else {
          _key = event.logicalKey;
          _recorded = true;
        }
      });
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      setState(() {
        // 修饰键释放时清除对应标志（仅当还没录入主键时）
        if (event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight) {
          if (!_recorded) _ctrl = false;
        } else if (event.logicalKey == LogicalKeyboardKey.altLeft ||
            event.logicalKey == LogicalKeyboardKey.altRight) {
          if (!_recorded) _alt = false;
        } else if (event.logicalKey == LogicalKeyboardKey.shiftLeft ||
            event.logicalKey == LogicalKeyboardKey.shiftRight) {
          if (!_recorded) _shift = false;
        } else if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
            event.logicalKey == LogicalKeyboardKey.metaRight) {
          if (!_recorded) _meta = false;
        }
        // 主键释放：如果是纯修饰键组合（没有主键），保持原样
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('设置快捷键'),
      constraints: const BoxConstraints(maxWidth: 360),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: SizedBox(
          height: 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _recorded ? '已录制' : '按下新的快捷键...',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _recorded
                      ? Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.08)
                      : cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _displayString.isNotEmpty ? _displayString : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _recorded
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _recorded
              ? () => Navigator.of(context).pop(_serialized)
              : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

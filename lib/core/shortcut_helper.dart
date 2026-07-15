import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 快捷键序列化与反序列化
///
/// 格式：`"Ctrl+T"`、`"F5"`、`"Ctrl+Shift+R"`、`"Escape"`

// ==================== Intent 定义 ====================

/// 返回（Esc）
class GoBackIntent extends Intent {}

/// 发帖（Ctrl+T）— 已从全局快捷键移除，保留定义供程序化调用
class NewThreadIntent extends Intent {}

/// 刷新（F5）
class RefreshIntent extends Intent {}

/// 切换到下一个 Tab（Ctrl+Tab）
class SwitchTabNextIntent extends Intent {}

/// 切换到上一个 Tab（Ctrl+Shift+Tab）
class SwitchTabPrevIntent extends Intent {}

// ==================== 工具类 ====================
class ShortcutHelper {
  /// 默认快捷键配置
  static const Map<String, String> defaults = {
    'refresh': 'F5',
    'goBack': 'Escape',
    'switchTabNext': 'Ctrl+Tab',
    'switchTabPrev': 'Ctrl+Shift+Tab',
  };

  /// 各快捷键的可读说明
  static const Map<String, String> labels = {
    'refresh': '刷新',
    'goBack': '返回',
    'switchTabNext': '下一个 Tab',
    'switchTabPrev': '上一个 Tab',
  };

  /// 字母键映射
  static const _letters = {
    'A': LogicalKeyboardKey.keyA,
    'B': LogicalKeyboardKey.keyB,
    'C': LogicalKeyboardKey.keyC,
    'D': LogicalKeyboardKey.keyD,
    'E': LogicalKeyboardKey.keyE,
    'F': LogicalKeyboardKey.keyF,
    'G': LogicalKeyboardKey.keyG,
    'H': LogicalKeyboardKey.keyH,
    'I': LogicalKeyboardKey.keyI,
    'J': LogicalKeyboardKey.keyJ,
    'K': LogicalKeyboardKey.keyK,
    'L': LogicalKeyboardKey.keyL,
    'M': LogicalKeyboardKey.keyM,
    'N': LogicalKeyboardKey.keyN,
    'O': LogicalKeyboardKey.keyO,
    'P': LogicalKeyboardKey.keyP,
    'Q': LogicalKeyboardKey.keyQ,
    'R': LogicalKeyboardKey.keyR,
    'S': LogicalKeyboardKey.keyS,
    'T': LogicalKeyboardKey.keyT,
    'U': LogicalKeyboardKey.keyU,
    'V': LogicalKeyboardKey.keyV,
    'W': LogicalKeyboardKey.keyW,
    'X': LogicalKeyboardKey.keyX,
    'Y': LogicalKeyboardKey.keyY,
    'Z': LogicalKeyboardKey.keyZ,
  };

  /// 数字键映射
  static const _digits = {
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };

  /// 将存储字符串（如 `"Ctrl+T"`）解析为 [ShortcutActivator]
  static ShortcutActivator? parse(String keyString) {
    if (keyString.isEmpty) return null;
    final parts = keyString.split('+');
    bool control = false, alt = false, shift = false, meta = false;
    LogicalKeyboardKey? key;

    for (final part in parts) {
      switch (part) {
        case 'Ctrl':
          control = true;
          break;
        case 'Alt':
          alt = true;
          break;
        case 'Shift':
          shift = true;
          break;
        case 'Meta':
          meta = true;
          break;
        default:
          key = _parseKey(part);
      }
    }

    if (key == null) return null;
    return SingleActivator(
      key,
      control: control,
      alt: alt,
      shift: shift,
      meta: meta,
    );
  }

  static LogicalKeyboardKey _parseKey(String name) {
    // 功能键
    if (name == 'Esc') return LogicalKeyboardKey.escape;
    if (name == 'F1') return LogicalKeyboardKey.f1;
    if (name == 'F2') return LogicalKeyboardKey.f2;
    if (name == 'F3') return LogicalKeyboardKey.f3;
    if (name == 'F4') return LogicalKeyboardKey.f4;
    if (name == 'F5') return LogicalKeyboardKey.f5;
    if (name == 'F6') return LogicalKeyboardKey.f6;
    if (name == 'F7') return LogicalKeyboardKey.f7;
    if (name == 'F8') return LogicalKeyboardKey.f8;
    if (name == 'F9') return LogicalKeyboardKey.f9;
    if (name == 'F10') return LogicalKeyboardKey.f10;
    if (name == 'F11') return LogicalKeyboardKey.f11;
    if (name == 'F12') return LogicalKeyboardKey.f12;
    if (name == 'Space') return LogicalKeyboardKey.space;
    if (name == 'Enter') return LogicalKeyboardKey.enter;
    if (name == 'Delete') return LogicalKeyboardKey.delete;
    if (name == 'Home') return LogicalKeyboardKey.home;
    if (name == 'End') return LogicalKeyboardKey.end;
    if (name == 'Tab') return LogicalKeyboardKey.tab;
    // 字母
    if (name.length == 1 &&
        name.codeUnitAt(0) >= 65 &&
        name.codeUnitAt(0) <= 90) {
      return _letters[name] ?? LogicalKeyboardKey.keyA;
    }
    // 数字
    if (name.length == 1 &&
        name.codeUnitAt(0) >= 48 &&
        name.codeUnitAt(0) <= 57) {
      return _digits[name] ?? LogicalKeyboardKey.digit0;
    }
    return LogicalKeyboardKey.escape;
  }
}

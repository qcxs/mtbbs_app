import 'dart:io';

/// 应用字体选择（按平台显式指定）
///
/// 背景：旧主题写死 `fontFamily: 'sans-serif'`。这只是 Android 的系统字体别名，
/// Windows/macOS/Linux 上**并不存在**该字体族，只能走引擎兜底——中文常被回退到
/// 宋体，小字号发虚、观感与系统其他应用不一致。
///
/// 这里统一给出平台字体与回退链；Android / iOS / 鸿蒙保持系统默认（返回 null），
/// 不改变移动端既有观感。
///
/// 使用范围：仅 `main.dart` 构造 `ThemeData` 时引用（主字体 + 等宽主题扩展）。
/// 业务代码取等宽样式请用 `context.appTypography.mono`，不要直接 import 本文件。

/// 界面主字体（null = 使用 Flutter/平台默认）
String? get appFontFamily {
  if (Platform.isWindows) return 'Microsoft YaHei UI';
  if (Platform.isMacOS) return 'PingFang SC';
  if (Platform.isLinux) return 'Noto Sans CJK SC';
  return null;
}

/// 界面字体回退链（主字体缺字时按顺序找）
List<String>? get appFontFallback {
  if (Platform.isWindows) {
    // 雅黑 UI 缺失时退到雅黑；西文/emoji 交给 Segoe
    return const [
      'Microsoft YaHei',
      'Segoe UI',
      'Segoe UI Emoji',
      'Segoe UI Symbol',
    ];
  }
  if (Platform.isMacOS) {
    return const ['Helvetica Neue', 'Apple Color Emoji'];
  }
  if (Platform.isLinux) {
    return const ['Noto Sans', 'DejaVu Sans'];
  }
  return null;
}

/// 等宽字体（代码块 / 日志 / 序列号）
///
/// 通用名 `monospace` 在 Windows 没有对应字体族，会退成比例字体（代码对不齐）。
String get appMonoFontFamily {
  if (Platform.isWindows) return 'Cascadia Mono';
  if (Platform.isMacOS) return 'SF Mono';
  if (Platform.isLinux) return 'Noto Sans Mono';
  return 'monospace';
}

/// 等宽字体回退链
List<String>? get appMonoFontFallback {
  if (Platform.isWindows) {
    // Cascadia Mono 只在较新的 Win10/11 自带；Consolas 是更稳的兜底
    return const ['Consolas', 'Courier New', 'monospace'];
  }
  if (Platform.isMacOS) return const ['Menlo', 'Monaco', 'monospace'];
  if (Platform.isLinux) return const ['DejaVu Sans Mono', 'monospace'];
  return null;
}

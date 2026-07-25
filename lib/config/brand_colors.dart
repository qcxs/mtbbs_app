/// 品牌固定色 — 集中管理所有功能色
///
/// 用法：
/// ```dart
/// final cs = Theme.of(context).colorScheme;
/// cs.linkColor    // 自适应亮暗的链接色
/// cs.levelColor   // 用户等级标签色（固定 #FF9900）
/// ```
///
/// 设计原则：
/// - 功能色（链接、标签、badge）用固定色值，不随 seed 变化
/// - 容器色（quote/free/hide 背景）在浅色保持原有特征色，深色自动适配
/// - 所有颜色通过 brightness 判断自动切换亮暗，调用方零判断
library;

import 'package:flutter/material.dart';

/// 亮暗色对
class _ColorPair {
  final Color light;
  final Color dark;
  const _ColorPair(this.light, this.dark);

  Color resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

// ==================== 固定色值定义 ====================

// -- 链接色 --
const _linkPair = _ColorPair(Color(0xFF336699), Color(0xFF64B5F6));

// -- 标签/badge 色（固定不变）--
const levelColor = Color(0xFFFF9900);
const forumColor = Color(0xFF53BCF5);
const onlineColor = Color(0xFF4CAF50);

// -- 编码块 --
const codeBg = Color(0xFF1E1E1E);
const codeText = Color(0xFF98C379);

// -- BBCode 容器色（浅色保留特征，深色用 M3 语义色替代）--
// quote/free/hide 背景：浅色用暖黄
// 深色从 colorScheme.tertiaryContainer 取（不在常量中定义）
const quoteBgLight = Color(0xFFFFF8E1);
const quoteBgDark = Color(0xFF333333);

// -- BBCode 其他容器色 --
const attachBg = Color(0xFFE3F2FD);
const lockedBg = Color(0xFFFFF3E0);
const pstatusBg = Color(0xFFF5F5F5);
const pstatusText = Color(0xFF999999);

// -- 设置页图标色板 --
const iconSite = Color(0xFF2196F3);
const iconUser = Color(0xFF4CAF50);
const iconForum = Color(0xFFFF9800);
const iconEmoji = Color(0xFFFFC107);
const iconStorage = Color(0xFF607D8B);
const iconLink = Color(0xFF9C27B0);
const iconTab = Color(0xFF3F51B5);
const iconPalette = Color(0xFFFF9800);
const iconSettings = Color(0xFF607D8B);
const iconKeyboard = Color(0xFF00BCD4);
const iconStagger = Color(0xFF009688);
const iconSearch = Color(0xFF00BCD4);
const iconUa = Color(0xFFFF5722);
const iconHistory = Color(0xFF607D8B);
const iconCalculate = Color(0xFFE91E63);
const iconDecoration = Color(0xFFFF5722);

// ==================== ColorScheme Extension ====================

/// ColorScheme 扩展 — 通过 cs.xxx 直接获取品牌色
extension BrandColors on ColorScheme {
  /// 链接色（浅色 #336699，深色 #64B5F6）
  Color get linkColor => _linkPair.resolve(brightness);

  /// 容器引用/免费/隐藏背景色（浅色暖黄，深色使用 tertiaryContainer）
  Color get quoteBg =>
      brightness == Brightness.dark ? quoteBgDark : quoteBgLight;

  /// 编码块背景
  Color get codeBgColor => codeBg;

  /// 编码块文本色
  Color get codeTextColor => codeText;

  /// 代码块（带工具栏）内容背景 — 自适应亮暗
  Color get codeBlockBg => brightness == Brightness.dark
      ? const Color(0xFF272822)
      : const Color(0xFFF8F8F8);

  /// 代码块顶部工具栏背景
  Color get codeBlockBarBg => brightness == Brightness.dark
      ? Colors.black.withValues(alpha: 0.2)
      : Colors.black.withValues(alpha: 0.04);

  /// 代码块顶部工具栏文本色
  Color get codeBlockBarText => brightness == Brightness.dark
      ? const Color(0xFFB0B0B0)
      : const Color(0xFF656D76);

  /// 代码块顶部工具栏图标激活色
  Color get codeBlockIconActive => brightness == Brightness.dark
      ? Colors.white
      : Colors.black.withValues(alpha: 0.7);

  /// 代码块顶部工具栏图标非激活色
  Color get codeBlockIconInactive => brightness == Brightness.dark
      ? const Color(0xFF888888)
      : Colors.black.withValues(alpha: 0.25);

  /// 附件卡片背景
  Color get attachBgColor => attachBg;

  /// 锁定内容背景
  Color get lockedBgColor => lockedBg;

  /// 帖子状态背景
  Color get pstatusBgColor => pstatusBg;

  /// 帖子状态文本色
  Color get pstatusTextColor => pstatusText;

  /// 「隐藏内容」标签色
  Color get hideLabelColor => error;

  /// 设置页图标色 — 通过 [iconBoxColor] 获取，不直接暴露
}

/// 工具：固定色 + 12% 透明度背景
///
/// 用于标签/badge 渲染，只需传前景色即可获得适配的容器色。
extension ColorBadge on Color {
  /// 生成带 12% 透明度的背景色
  Color get withBg => withValues(alpha: 0.12);

  /// 生成标签 widget
  Widget toBadge(String text, {double fontSize = 11}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: withBg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize, color: this),
      ),
    );
  }
}

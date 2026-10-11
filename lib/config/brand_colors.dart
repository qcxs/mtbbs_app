/// 品牌固定色 — 集中管理所有功能色
///
/// 用法：
/// ```dart
/// final cs = Theme.of(context).colorScheme;
/// cs.linkColor    // 自适应亮暗的链接色
/// levelColor      // 用户等级标签色（固定 #FF9900）
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

// -- 精华徽标色（金色，与等级/版块色区分）--
const digestColor = Color(0xFFE6A23C);

// -- 置顶回复徽标色（红，呼应站内 settop 图标）--
const stickTopColor = Color(0xFFE5484D);

// -- 搜索结果关键词高亮（对应网页 <font color="#ff0000">；深色提高亮度保证可读）--
const _searchHlPair = _ColorPair(Color(0xFFD32F2F), Color(0xFFFF8A80));

// -- 编码块 --
const codeText = Color(0xFF98C379);

// -- BBCode 容器色（浅色保留特征，深色用 M3 语义色替代）--
// quote/free/hide 背景：浅色用暖黄
// 深色从 colorScheme.tertiaryContainer 取（不在常量中定义）
const quoteBgLight = Color(0xFFFFF8E1);
const quoteBgDark = Color(0xFF333333);

// -- BBCode 其他容器色 --
const attachBg = Color(0xFFE3F2FD);
const lockedBg = Color(0xFFFFF3E0);
const pstatusText = Color(0xFF999999);

// ==================== ColorScheme Extension ====================

/// ColorScheme 扩展 — 通过 cs.xxx 直接获取品牌色
extension BrandColors on ColorScheme {
  /// 链接色（浅色 #336699，深色 #64B5F6）
  Color get linkColor => _linkPair.resolve(brightness);

  /// 搜索结果关键词高亮色
  Color get searchHighlightColor => _searchHlPair.resolve(brightness);

  /// 容器引用/免费/隐藏背景色（浅色暖黄，深色使用 tertiaryContainer）
  Color get quoteBg =>
      brightness == Brightness.dark ? quoteBgDark : quoteBgLight;

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

  /// 帖子状态文本色
  Color get pstatusTextColor => pstatusText;
}

/// 工具：颜色扩展
extension ColorBadge on Color {
  /// 生成「盖章」样式标签：略微旋转 + 描边 + 淡底，模仿站内印章（精华/置顶等）
  Widget toStamp(String text, {double fontSize = 13, double angle = -0.12}) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: withValues(alpha: 0.08),
          border: Border.all(color: this, width: 1.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: this,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

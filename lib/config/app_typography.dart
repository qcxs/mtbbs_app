import 'package:flutter/material.dart';
import 'package:mtbbs/core/utils/app_fonts.dart';

/// 排版能力的主题扩展（目前是等宽字体）
///
/// 字体属于主题：挂到 [ThemeData.extensions] 后，业务代码用
/// `context.appTypography.mono` 取样式，不再直接依赖平台字体工具。
/// 界面主字体仍由 `ThemeData.fontFamily` 承担，见 `app_fonts.dart`。
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({required this.monoFamily, this.monoFallback});

  /// 平台默认值：主题未注入时兜底（widget 测试里常见）
  static AppTypography get platform => AppTypography(
    monoFamily: appMonoFontFamily,
    monoFallback: appMonoFontFallback,
  );

  /// 等宽字体族（代码块 / 日志 / 序列号）
  final String monoFamily;

  /// 等宽字体回退链
  final List<String>? monoFallback;

  /// 等宽基础样式，配合 `copyWith` 叠加字号/颜色
  TextStyle get mono =>
      TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback);

  @override
  AppTypography copyWith({String? monoFamily, List<String>? monoFallback}) =>
      AppTypography(
        monoFamily: monoFamily ?? this.monoFamily,
        monoFallback: monoFallback ?? this.monoFallback,
      );

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) =>
      t < 0.5 ? this : (other is AppTypography ? other : this);
}

extension AppTypographyContext on BuildContext {
  /// 取主题排版扩展；未注入（如部分测试）时回退到平台默认
  AppTypography get appTypography =>
      Theme.of(this).extension<AppTypography>() ?? AppTypography.platform;
}

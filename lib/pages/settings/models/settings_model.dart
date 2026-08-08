import 'package:flutter/material.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 设置项图标：与 PiliPlus 一致，裸 Icon、不指定颜色（跟随 ListTile 主题灰），无背景容器
Widget settingIcon(BuildContext context, IconData icon) {
  return Icon(icon);
}

/// 设置项模型：数据描述 + UI 构建绑定在同一处（参考 PiliPlus 声明式设计）。
/// 各分组通过返回 `List<SettingsModel>` 描述设置项，页面渲染时逐项构建。
sealed class SettingsModel {
  const SettingsModel({required this.title, this.subtitle, required this.icon});

  final String title;
  final String? subtitle;
  final IconData icon;

  /// 构建列表项（读取 [settings] 实时值）
  Widget build(BuildContext context, SettingsProvider settings);
}

/// 普通点击行：可跳页/弹窗，支持动态副标题与自定义 trailing
class NormalSetting extends SettingsModel {
  const NormalSetting({
    required super.title,
    super.subtitle,
    required super.icon,
    this.subtitleBuilder,
    this.trailing,
    this.trailingBuilder,
    required this.onTap,
  }) : assert(
         subtitle == null || subtitleBuilder == null,
         'subtitle 与 subtitleBuilder 只能提供一个',
       ),
       assert(
         trailing == null || trailingBuilder == null,
         'trailing 与 trailingBuilder 只能提供一个',
       );

  /// 动态副标题（读取 provider 实时值；返回 null 表示无副标题）
  final String? Function(SettingsProvider)? subtitleBuilder;
  final Widget? trailing;

  /// 动态 trailing（读取 provider 实时值，如快捷键键值徽章）
  final Widget Function(BuildContext context, SettingsProvider settings)?
  trailingBuilder;
  final void Function(BuildContext context, SettingsProvider settings) onTap;

  @override
  Widget build(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    final sub = subtitleBuilder?.call(settings) ?? subtitle;
    return ListTile(
      leading: settingIcon(context, icon),
      title: Text(title),
      subtitle: sub == null ? null : Text(sub),
      trailing:
          trailingBuilder?.call(context, settings) ??
          trailing ??
          Icon(Icons.chevron_right, color: cs.outline),
      onTap: () => onTap(context, settings),
    );
  }
}

/// 开关行
class SwitchSetting extends SettingsModel {
  const SwitchSetting({
    required super.title,
    super.subtitle,
    required super.icon,
    required this.value,
    required this.onChanged,
  });

  final bool Function(SettingsProvider) value;
  final void Function(BuildContext context, SettingsProvider settings, bool v)
  onChanged;

  @override
  Widget build(BuildContext context, SettingsProvider settings) {
    return SwitchListTile(
      secondary: settingIcon(context, icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value(settings),
      onChanged: (v) => onChanged(context, settings, v),
    );
  }
}

/// 分组小标题（非点击项，如快捷键分组内的区域标题）
class HeaderSetting extends SettingsModel {
  const HeaderSetting({required super.title, super.subtitle})
    : super(icon: Icons.label_outline);

  @override
  Widget build(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

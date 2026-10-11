import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/content_settings.dart';
import 'package:mtbbs/pages/settings/models/data_settings.dart';
import 'package:mtbbs/pages/settings/models/display_settings.dart';
import 'package:mtbbs/pages/settings/models/editor_settings.dart';
import 'package:mtbbs/pages/settings/models/mcp_settings.dart';
import 'package:mtbbs/pages/settings/models/page_gate_settings.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/models/site_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';

/// 一个设置分组：标题 + 图标 + 设置项构建器。
///
/// [models] 接收 provider —— 个别分组要展开运行时数据（如 MCP 令牌列表、工具栏项）。
class SettingsGroupDef {
  const SettingsGroupDef({
    required this.title,
    required this.icon,
    required this.models,
  });

  final String title;
  final IconData icon;

  /// 每次构建时重新生成设置项，保证动态内容（MCP 令牌列表、调用记录）始终最新
  final List<SettingsModel> Function(SettingsProvider) models;
}

/// 全部设置分组 —— 设置主页与设置搜索页共用的**唯一清单**（见 docs/07 #51）。
///
/// 新增 / 改名 / 调整分组只改这里一处。搜索页在此之上再并入其检索专属的补充项
/// （快捷键明细、关于页内的项、开发者选项），见 `settings_search_page.dart`。
final settingsGroups = <SettingsGroupDef>[
  SettingsGroupDef(
    title: '站点与网络',
    icon: Icons.dns,
    models: (_) => siteSettings(),
  ),
  SettingsGroupDef(
    title: '外观',
    icon: Icons.palette,
    models: (_) => displaySettings(),
  ),
  SettingsGroupDef(
    title: '阅读与渲染',
    icon: Icons.article,
    models: (_) => contentSettings(),
  ),
  SettingsGroupDef(
    title: '编辑与快捷键',
    icon: Icons.edit,
    models: (_) => editorSettings(),
  ),
  SettingsGroupDef(
    title: '存储与工具',
    icon: Icons.storage,
    models: (_) => dataSettings(),
  ),
  SettingsGroupDef(
    title: '页面接管',
    icon: Icons.pages,
    models: (_) => pageGateSettings(),
  ),
  SettingsGroupDef(
    title: 'MCP 服务',
    icon: Icons.hub,
    models: (_) => mcpSettings(),
  ),
];

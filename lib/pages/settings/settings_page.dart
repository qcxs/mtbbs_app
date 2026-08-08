import 'package:flutter/material.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/models/content_settings.dart';
import 'package:mtbbs/pages/settings/models/data_settings.dart';
import 'package:mtbbs/pages/settings/models/display_settings.dart';
import 'package:mtbbs/pages/settings/models/editor_settings.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/models/shortcut_settings.dart';
import 'package:mtbbs/pages/settings/models/site_settings.dart';
import 'package:mtbbs/pages/settings/settings_group_page.dart';
import 'package:mtbbs/pages/settings/settings_search_page.dart';

/// 设置分组描述
class _SettingsGroup {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.models,
  });

  final String title;
  final IconData icon;
  final List<SettingsModel> models;
}

/// 设置页面 — 分组入口列表（竖屏）/ 分组内容（宽屏双栏见 P4）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 宽屏双栏下当前选中的分组索引（竖屏不使用）
  int _currentIndex = 0;

  static final List<_SettingsGroup> _groups = [
    _SettingsGroup(title: '站点', icon: Icons.dns, models: siteSettings()),
    _SettingsGroup(title: '数据与缓存', icon: Icons.storage, models: dataSettings()),
    _SettingsGroup(title: '界面', icon: Icons.palette, models: displaySettings()),
    _SettingsGroup(
      title: '内容渲染',
      icon: Icons.article,
      models: contentSettings(),
    ),
    _SettingsGroup(title: '编辑器', icon: Icons.edit, models: editorSettings()),
    _SettingsGroup(
      title: '快捷键',
      icon: Icons.keyboard,
      models: shortcutSettings(),
    ),
    _SettingsGroup(
      title: '关于',
      icon: Icons.info_outline,
      models: aboutSettings(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsSearchPage()),
            ),
          ),
        ],
      ),
      // 竖屏：分组入口列表；横屏（宽屏）：左分组列表 + 右分组内容双栏
      body: isPortrait ? _buildGroupList(context) : _buildLandscape(context),
    );
  }

  Widget _buildLandscape(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final group = _groups[_currentIndex];
    return Row(
      children: [
        // 左栏固定宽度，避免占太多空间
        SizedBox(width: 280, child: _buildGroupList(context)),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          flex: 1,
          child: SettingsGroupPage(
            title: group.title,
            models: group.models,
            showAppBar: false,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    return ListView.builder(
      itemCount: _groups.length,
      itemBuilder: (context, i) {
        final g = _groups[i];
        return ListTile(
          leading: settingIcon(context, g.icon),
          title: Text(g.title),
          subtitle: Text('${g.models.length} 项'),
          trailing: Icon(Icons.chevron_right, color: cs.outline),
          selected: !isPortrait && i == _currentIndex,
          selectedTileColor: cs.secondaryContainer,
          onTap: () {
            if (isPortrait) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsGroupPage(title: g.title, models: g.models),
                ),
              );
            } else {
              setState(() => _currentIndex = i);
            }
          },
        );
      },
    );
  }
}

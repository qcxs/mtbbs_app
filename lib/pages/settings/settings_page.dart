import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/models/content_settings.dart';
import 'package:mtbbs/pages/settings/models/data_settings.dart';
import 'package:mtbbs/pages/settings/models/display_settings.dart';
import 'package:mtbbs/pages/settings/models/editor_settings.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/models/site_settings.dart';
import 'package:mtbbs/pages/settings/settings_group_page.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

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

/// 设置页面 — 分组入口列表（竖屏）/ 分组内容（宽屏双栏）
///
/// 分组按「用户关心什么」划分：站点与网络 / 外观 / 阅读与渲染 /
/// 编辑与快捷键 / 存储与工具；「关于」作为列表底部单独一行，不占分组位。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 宽屏双栏下当前选中的分组索引（竖屏不使用）
  int _currentIndex = 0;

  static final List<_SettingsGroup> _groups = [
    _SettingsGroup(title: '站点与网络', icon: Icons.dns, models: siteSettings()),
    _SettingsGroup(title: '外观', icon: Icons.palette, models: displaySettings()),
    _SettingsGroup(
      title: '阅读与渲染',
      icon: Icons.article,
      models: contentSettings(),
    ),
    _SettingsGroup(
      title: '编辑与快捷键',
      icon: Icons.edit,
      models: editorSettings(),
    ),
    _SettingsGroup(title: '存储与工具', icon: Icons.storage, models: dataSettings()),
  ];

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      // 竖屏：分组入口列表；横屏（宽屏）：左分组列表 + 右分组内容双栏
      body: isPortrait ? _buildPortrait(context) : _buildLandscape(context),
    );
  }

  Widget _buildPortrait(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      children: [
        _buildSearchEntry(context),
        Expanded(
          child: ListView(
            children: [
              for (final g in _groups) _groupTile(context, g, selected: false),
              const Divider(height: 8),
              for (final m in aboutSettings()) m.build(context, settings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final group = _groups[_currentIndex];
    return Row(
      children: [
        // 左栏固定宽度，避免占太多空间
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _buildSearchEntry(context),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < _groups.length; i++)
                      _groupTile(
                        context,
                        _groups[i],
                        selected: i == _currentIndex,
                        index: i,
                      ),
                    const Divider(height: 8),
                    for (final m in aboutSettings()) m.build(context, settings),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  /// 搜索入口 — 顶部伪搜索框，点击进入搜索页
  Widget _buildSearchEntry(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/settings/search'),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                '搜索设置',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupTile(
    BuildContext context,
    _SettingsGroup g, {
    required bool selected,
    int? index,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    return ListTile(
      leading: settingIcon(context, g.icon),
      title: Text(g.title),
      subtitle: Text('${g.models.length} 项'),
      trailing: Icon(Icons.chevron_right, color: cs.outline),
      selected: selected,
      selectedTileColor: cs.secondaryContainer,
      onTap: () {
        if (isPortrait) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsGroupPage(title: g.title, models: g.models),
            ),
          );
        } else if (index != null) {
          setState(() => _currentIndex = index);
        }
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/utils/screen_size_ext.dart';
import 'package:mtbbs/pages/settings/about_page.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/models/settings_groups.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/settings_group_page.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 设置页面 — 分组入口列表（竖屏）/ 分组内容（宽屏双栏）
///
/// 分组按「用户关心什么」划分，清单见 `models/settings_groups.dart`
/// （与设置搜索页共用同一份，避免"两套清单"，见 docs/07 #51）；「关于」作为
/// 列表底部单独一行（宽屏则作为右栏内容），不占分组位。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 宽屏双栏下当前选中的分组索引（竖屏不使用）
  int _currentIndex = 0;

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
              for (final g in settingsGroups)
                _groupTile(context, g, settings: settings, selected: false),
              const Divider(height: 8),
              for (final m in aboutSettings()) m.build(context, settings),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    // settingsGroups.length 这一档代表「关于」：它不是分组（竖屏是列表底部单独一行），
    // 但宽屏下同样作为右栏内容展示，避免"其他都右侧、只有它跳新页"的不一致
    final isAbout = _currentIndex >= settingsGroups.length;
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
                    for (var i = 0; i < settingsGroups.length; i++)
                      _groupTile(
                        context,
                        settingsGroups[i],
                        settings: settings,
                        selected: i == _currentIndex,
                        index: i,
                      ),
                    const Divider(height: 8),
                    _aboutTile(context, selected: isAbout),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          flex: 1,
          child: isAbout
              ? const AboutPage(showAppBar: false)
              : SettingsGroupPage(
                  title: settingsGroups[_currentIndex].title,
                  modelsBuilder: () =>
                      settingsGroups[_currentIndex].models(settings),
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

  /// 宽屏左栏的「关于」行 —— 与分组行同款，选中后在右栏展示
  /// （竖屏仍走 `/settings/about` 路由，见 [_buildPortrait]）
  Widget _aboutTile(BuildContext context, {required bool selected}) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: settingIcon(context, Icons.info_outline),
      title: const Text('关于'),
      subtitle: Text(
        'MTBBS v${BuildConfig.versionName}+${BuildConfig.versionCode}',
      ),
      trailing: Icon(Icons.chevron_right, color: cs.outline),
      selected: selected,
      selectedTileColor: cs.secondaryContainer,
      onTap: () => setState(() => _currentIndex = settingsGroups.length),
    );
  }

  Widget _groupTile(
    BuildContext context,
    SettingsGroupDef g, {
    required SettingsProvider settings,
    required bool selected,
    int? index,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isPortrait = MediaQuery.sizeOf(context).isPortrait;
    return ListTile(
      leading: settingIcon(context, g.icon),
      title: Text(g.title),
      subtitle: Text('${g.models(settings).length} 项'),
      trailing: Icon(Icons.chevron_right, color: cs.outline),
      selected: selected,
      selectedTileColor: cs.secondaryContainer,
      onTap: () {
        if (isPortrait) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SettingsGroupPage(
                title: g.title,
                modelsBuilder: () => g.models(settings),
              ),
            ),
          );
        } else if (index != null) {
          setState(() => _currentIndex = index);
        }
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/models/content_settings.dart';
import 'package:mtbbs/pages/settings/models/data_settings.dart';
import 'package:mtbbs/pages/settings/models/developer_settings.dart';
import 'package:mtbbs/pages/settings/models/display_settings.dart';
import 'package:mtbbs/pages/settings/models/editor_settings.dart';
import 'package:mtbbs/pages/settings/models/mcp_settings.dart';
import 'package:mtbbs/pages/settings/models/page_gate_settings.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/pages/settings/models/shortcut_settings.dart';
import 'package:mtbbs/pages/settings/models/site_settings.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 设置搜索页 — 跨全部分组检索设置项（标题/副标题），结果可直接操作。
class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({super.key});

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final TextEditingController _ctl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// 全部分组（与设置主页共享同一份模型函数，每次检索时重新生成）
  ///
  /// `models` 接收 provider：个别分组（编辑与快捷键）要展开运行时数据
  /// （快捷键明细、工具栏项），无法在无参闭包里求值。
  static final List<
    ({String group, List<SettingsModel> Function(SettingsProvider) models})
  >
  _all = [
    (group: '站点与网络', models: (_) => siteSettings()),
    (group: '外观', models: (_) => displaySettings()),
    (group: '阅读与渲染', models: (_) => contentSettings()),
    // 并入快捷键明细（全局快捷键 + 工具栏项），否则面板里的每个快捷键项搜不到
    (group: '编辑与快捷键', models: (s) => [...editorSettings(), ...shortcutSettings(s)]),
    (group: '存储与工具', models: (_) => dataSettings()),
    (group: '页面接管', models: (_) => pageGateSettings()),
    (group: 'MCP 服务', models: (_) => mcpSettings()),
    // 「关于」组额外索引关于页内的项（如「检查更新」）—— 与关于页渲染同一份
    // aboutPageSettings()，改一处两边都跟着变，不存在两套清单（见 docs/07 #51）
    (group: '关于', models: (_) => [...aboutSettings(), ...aboutPageSettings()]),
  ];

  List<({String group, List<SettingsModel> items})> _results(
    SettingsProvider settings,
  ) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    // 开发者选项只在解锁后参与检索（未解锁时不该被搜出来）
    final all = [
      ..._all,
      if (settings.developerMode)
        (group: '开发者选项', models: (_) => developerSettings()),
    ];
    final results = <({String group, List<SettingsModel> items})>[];
    for (final entry in all) {
      final matched = entry
          .models(settings)
          .where((m) => _matches(m, q, settings))
          .toList();
      if (matched.isNotEmpty) {
        results.add((group: entry.group, items: matched));
      }
    }
    return results;
  }

  bool _matches(SettingsModel m, String q, SettingsProvider settings) {
    if (m.title.toLowerCase().contains(q)) return true;
    final sub = (m is NormalSetting && m.subtitleBuilder != null)
        ? m.subtitleBuilder!(settings)
        : m.subtitle;
    return sub != null && sub.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    final results = _results(settings);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索设置项',
            border: InputBorder.none,
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              tooltip: '清除',
              onPressed: () {
                _ctl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? Center(
              child: Text(
                '输入关键词搜索设置项',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : results.isEmpty
          ? Center(
              child: Text(
                '未找到匹配的设置项',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          : ListView(
              children: [
                for (final entry in results) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      entry.group,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final m in entry.items) m.build(context, settings),
                ],
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/about_settings.dart';
import 'package:mtbbs/pages/settings/models/content_settings.dart';
import 'package:mtbbs/pages/settings/models/data_settings.dart';
import 'package:mtbbs/pages/settings/models/display_settings.dart';
import 'package:mtbbs/pages/settings/models/editor_settings.dart';
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

  /// 全部分组（与主页共享同一份模型列表）
  static final List<({String group, List<SettingsModel> models})> _all = [
    (group: '站点', models: siteSettings()),
    (group: '数据与缓存', models: dataSettings()),
    (group: '界面', models: displaySettings()),
    (group: '内容渲染', models: contentSettings()),
    (group: '编辑器', models: editorSettings()),
    (group: '快捷键', models: shortcutSettings()),
    (group: '关于', models: aboutSettings()),
  ];

  List<({String group, List<SettingsModel> items})> _results(
    SettingsProvider settings,
  ) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <({String group, List<SettingsModel> items})>[];
    for (final entry in _all) {
      final matched = entry.models
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

import 'package:flutter/material.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 分组设置页：渲染一组设置项。
/// [showAppBar]=false 时无标题栏，作为宽屏双栏布局的右侧内容嵌入。
class SettingsGroupPage extends StatelessWidget {
  const SettingsGroupPage({
    super.key,
    required this.title,
    required this.models,
    this.showAppBar = true,
  });

  final String title;
  final List<SettingsModel> models;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(title), centerTitle: true) : null,
      body: ListView.builder(
        itemCount: models.length,
        itemBuilder: (_, i) => models[i].build(context, settings),
      ),
    );
  }
}

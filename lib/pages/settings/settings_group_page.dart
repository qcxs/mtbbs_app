import 'package:flutter/material.dart';
import 'package:mtbbs/mcp/mcp.dart';
import 'package:mtbbs/pages/settings/models/settings_model.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// 分组设置页：渲染一组设置项。
/// [showAppBar]=false 时无标题栏，作为宽屏双栏布局的右侧内容嵌入。
class SettingsGroupPage extends StatelessWidget {
  const SettingsGroupPage({
    super.key,
    required this.title,
    required this.modelsBuilder,
    this.showAppBar = true,
  });

  final String title;

  /// 每次构建时重新生成设置项，保证动态内容（MCP 令牌列表、调用记录）始终最新
  final List<SettingsModel> Function() modelsBuilder;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // MCP 设置项直接读 McpServerController（不经 SettingsProvider），
    // 这里订阅它，保证开关 / 状态 / 自检结果变化时本页跟着刷新
    context.watch<McpServerController>();
    final models = modelsBuilder();
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(title), centerTitle: true) : null,
      body: ListView.builder(
        itemCount: models.length,
        itemBuilder: (_, i) => models[i].build(context, settings),
      ),
    );
  }
}

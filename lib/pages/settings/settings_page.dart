import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../config/site_config.dart';
import '../../config/nav_config.dart';
import '../../core/shortcut_helper.dart';
import '../../providers/settings_provider.dart';
import '../../providers/history_provider.dart';
import 'user_management_dialog.dart';
import 'site_management.dart';
import 'forum_management.dart';
import 'formula_dialog.dart';
import 'bbcode_dialog.dart';
import 'shortcut_links_dialog.dart';
import 'default_tab_dialog.dart';

/// 设置页面 — 纯布局，具体功能委托给独立文件
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          // ==================== 站点 ====================
          _section('站点', [
            ListTile(
              leading: _iconBox(Icons.dns, Colors.green),
              title: const Text('当前站点'),
              subtitle: Text(SiteConfig.sites[settings.currentSiteIndex].name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => SiteManagement.showPicker(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.person, Colors.deepPurple),
              title: const Text('用户管理'),
              subtitle: const Text('账号切换、导入导出、清除登录信息'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog(
                context: context,
                builder: (_) => const UserManagementDialog(),
              ),
            ),
          ]),

          // ==================== 版块管理 ====================
          _section('版块管理', [
            ListTile(
              leading: _iconBox(Icons.forum, Colors.blue),
              title: const Text('版块管理'),
              subtitle: Text('${settings.forumEntries.length} 个板块'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ForumManagement.showPicker(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.emoji_emotions, Colors.amber),
              title: const Text('表情管理'),
              subtitle: const Text('查看和刷新当前站点表情'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/emoji'),
            ),
          ]),

          // ==================== 快捷链接 ====================
          _section('快捷链接', [
            ListTile(
              leading: _iconBox(Icons.link, Colors.lightBlue),
              title: const Text('管理快捷链接'),
              subtitle: Text('${settings.shortcutLinks.length} 个链接'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ShortcutLinksDialog.show(context, settings),
            ),
          ]),

          // ==================== 浏览历史 ====================
          _section('浏览历史', [
            ListTile(
              leading: _iconBox(Icons.history, Colors.brown),
              title: const Text('插入格式'),
              subtitle: const Text('编辑器引用时格式化文本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/history-format'),
            ),
            ListTile(
              leading: _iconBox(Icons.storage, Colors.brown),
              title: const Text('最大记录数'),
              subtitle: Text('${settings.historyMaxCount} 条'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showMaxCountDialog(context, settings),
            ),
          ]),

          // ==================== 积分公式 ====================
          _section('积分公式', [
            ListTile(
              leading: _iconBox(Icons.calculate, Colors.orange),
              title: const Text('积分计算公式'),
              subtitle: const Text('点击查看和刷新'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => FormulaDialog.show(context, settings),
            ),
          ]),

          // ==================== BBCode 渲染 ====================
          _section('BBCode 渲染', [
            ListTile(
              leading: _iconBox(Icons.palette_outlined, Colors.teal),
              title: const Text('禁用样式标签'),
              subtitle: Text(
                settings.disabledBbcodeTags.isEmpty
                    ? '全部已启用'
                    : '已禁用 ${settings.disabledBbcodeTags.length} 种',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => BbcodeDialog.show(context, settings),
            ),
            SwitchListTile(
              secondary: _iconBox(Icons.link, Colors.indigo),
              title: const Text('自动识别链接'),
              subtitle: const Text('纯文本 http(s) URL 自动转为可点击链接'),
              value: settings.autoDetectUrls,
              onChanged: (v) => settings.setAutoDetectUrls(v),
            ),
          ]),

          // ==================== 界面管理 ====================
          _section('界面管理', [
            ListTile(
              leading: _iconBox(Icons.tab, Colors.deepOrange),
              title: const Text('默认启动页'),
              subtitle: Text(_tabNameFor(settings.defaultTabIndex)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => DefaultTabDialog.show(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.settings, Colors.blueGrey),
              title: const Text('编辑器设置'),
              subtitle: const Text('快照、工具栏排序等'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/editor'),
            ),
          ]),

          // ==================== 快捷键 ====================
          _section('快捷键', [
            ListTile(
              leading: _iconBox(Icons.keyboard, Colors.indigo),
              title: const Text('自定义快捷键'),
              subtitle: Text('${ShortcutHelper.labels.length} 个可配置项'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/shortcuts'),
            ),
          ]),
        ],
      ),
    );
  }

  void _showMaxCountDialog(BuildContext context, SettingsProvider settings) {
    final ctl = TextEditingController(
      text: settings.historyMaxCount.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('最大记录数'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('设置浏览历史最多保存多少条记录（10-1000）。'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '记录数',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctl.text.trim()) ?? 200;
              settings.setHistoryMaxCount(v);
              context.read<HistoryProvider>().setMaxCount(v);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _tabNameFor(int index) {
    if (index < 0 || index >= navItems.length) return '';
    return navItems[index].label;
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}

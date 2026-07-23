import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/site_store.dart';
import '../../config/nav_config.dart';
import '../../core/shortcut_helper.dart';
import '../../core/stagger_queue.dart';
import '../../providers/settings_provider.dart';
import '../../providers/history_provider.dart';
import 'site_management.dart';
import 'user_management_dialog.dart';
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          // ==================== 站点 ====================
          _section(cs, '站点', [
            ListTile(
              leading: _iconBox(Icons.dns, const Color(0xFF2196F3)),
              title: const Text('当前站点'),
              subtitle: Text(
                SiteStore.instance.sites[settings.currentSiteIndex].name,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => SiteManagement.showPicker(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.person, const Color(0xFF4CAF50)),
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
          _section(cs, '版块管理', [
            ListTile(
              leading: _iconBox(Icons.forum, const Color(0xFFFF9800)),
              title: const Text('版块管理'),
              subtitle: Text('${settings.forumEntries.length} 个板块'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ForumManagement.showPicker(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.emoji_emotions, const Color(0xFFFFC107)),
              title: const Text('表情管理'),
              subtitle: const Text('查看和刷新当前站点表情'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/emoji'),
            ),
            ListTile(
              leading: _iconBox(Icons.storage, const Color(0xFF607D8B)),
              title: const Text('缓存管理'),
              subtitle: const Text('头像/表情/预览缓存，设置过期时间'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/cache'),
            ),
          ]),

          // ==================== 快捷链接 ====================
          _section(cs, '快捷链接', [
            ListTile(
              leading: _iconBox(Icons.link, const Color(0xFF9C27B0)),
              title: const Text('管理快捷链接'),
              subtitle: Text('${settings.shortcutLinks.length} 个链接'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ShortcutLinksDialog.show(context, settings),
            ),
          ]),

          // ==================== 浏览历史 ====================
          _section(cs, '浏览历史', [
            ListTile(
              leading: _iconBox(Icons.history, const Color(0xFF607D8B)),
              title: const Text('插入格式'),
              subtitle: const Text('编辑器引用时格式化文本'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/history-format'),
            ),
            ListTile(
              leading: _iconBox(Icons.storage, const Color(0xFF795548)),
              title: const Text('最大记录数'),
              subtitle: Text('${settings.historyMaxCount} 条'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showMaxCountDialog(context, settings),
            ),
          ]),

          // ==================== 积分公式 ====================
          _section(cs, '积分公式', [
            ListTile(
              leading: _iconBox(Icons.calculate, const Color(0xFFE91E63)),
              title: const Text('积分计算公式'),
              subtitle: const Text('点击查看和刷新'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => FormulaDialog.show(context, settings),
            ),
          ]),

          // ==================== BBCode 渲染 ====================
          _section(cs, 'BBCode 渲染', [
            ListTile(
              leading: _iconBox(
                Icons.palette_outlined,
                const Color(0xFFFF5722),
              ),
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
              secondary: _iconBox(Icons.link, const Color(0xFF9C27B0)),
              title: const Text('自动识别链接'),
              subtitle: const Text('纯文本 http(s) URL 自动转为可点击链接'),
              value: settings.autoDetectUrls,
              onChanged: (v) => settings.setAutoDetectUrls(v),
            ),
          ]),

          // ==================== 界面管理 ====================
          _section(cs, '界面管理', [
            ListTile(
              leading: _iconBox(Icons.tab, const Color(0xFF3F51B5)),
              title: const Text('默认启动页'),
              subtitle: Text(_tabNameFor(settings.defaultTabIndex)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => DefaultTabDialog.show(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.palette, const Color(0xFFFF9800)),
              title: const Text('主题色'),
              subtitle: Text(_colorNameFor(settings.seedColor)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showColorPicker(context, settings),
            ),
            ListTile(
              leading: _iconBox(Icons.settings, const Color(0xFF607D8B)),
              title: const Text('编辑器设置'),
              subtitle: const Text('快照、工具栏排序等'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/editor'),
            ),
          ]),

          // ==================== 快捷键 ====================
          _section(cs, '快捷键', [
            ListTile(
              leading: _iconBox(Icons.keyboard, const Color(0xFF00BCD4)),
              title: const Text('自定义快捷键'),
              subtitle: Text('${ShortcutHelper.labels.length} 个可配置项'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/shortcuts'),
            ),
          ]),

          // ==================== 通用错峰 ====================
          _section(cs, '通用错峰', [
            ListTile(
              leading: _iconBox(
                Icons.motion_photos_on,
                const Color(0xFF009688),
              ),
              title: const Text('请求间隔'),
              subtitle: Text('${settings.staggerInterval}ms，头像/预览等批量请求逐个放行'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showStaggerDialog(context, settings),
            ),
          ]),

          const SizedBox(height: 12),

          // ==================== 关于 ====================
          Material(
            color: cs.surface,
            child: ListTile(
              leading: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
              title: const Text('关于'),
              subtitle: const Text('MTBBS v1.0.0'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            ),
          ),
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

  String _colorNameFor(Color color) {
    for (final entry in SettingsProvider.presetColors.entries) {
      if (entry.value.toARGB32() == color.toARGB32()) return entry.key;
    }
    return '自定义';
  }

  void _showStaggerDialog(BuildContext context, SettingsProvider settings) {
    final ctl = TextEditingController(
      text: settings.staggerInterval.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('通用错峰间隔'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('短时间大量请求时，可能封ip，设置请求间隔，主动放慢请求。取值范围：（20-300ms），自行测试。'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '间隔（毫秒）',
                border: OutlineInputBorder(),
                isDense: true,
                helperText: '默认 40ms',
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
            onPressed: () async {
              final v = int.tryParse(ctl.text.trim()) ?? 40;
              await settings.setStaggerInterval(v);
              setStaggerInterval(Duration(milliseconds: v));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (ctx) {
        final mCs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('主题色'),
          content: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: SettingsProvider.presetColors.entries.map((e) {
              final isActive =
                  e.value.toARGB32() == settings.seedColor.toARGB32();
              return GestureDetector(
                onTap: () {
                  settings.setSeedColor(e.value);
                  Navigator.of(ctx).pop();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: isActive
                            ? Border.all(color: mCs.onSurfaceVariant, width: 3)
                            : null,
                      ),
                      child: isActive
                          ? Icon(Icons.check, color: Colors.white, size: 22)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(e.key, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _section(ColorScheme cs, String title, List<Widget> children) {
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
                color: cs.onSurfaceVariant,
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

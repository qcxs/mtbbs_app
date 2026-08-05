import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/config/nav_config.dart';
import 'package:mtbbs/config/build_config.dart';
import 'package:mtbbs/core/utils/shortcut_helper.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/history_provider.dart';
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
            // UA 切换
            ListTile(
              leading: _iconBox(Icons.phone_android, const Color(0xFFFF5722)),
              title: const Text('浏览模式'),
              subtitle: Text(SiteStore.instance.isMobileUA ? '移动版（推荐）' : '桌面版'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showUADialog(context, settings),
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
            SwitchListTile(
              secondary: _iconBox(Icons.dark_mode, const Color(0xFF3F51B5)),
              title: const Text('纯黑主题'),
              subtitle: const Text('深色模式下使用纯黑背景'),
              value: settings.isPureBlackTheme,
              onChanged: (v) => settings.setPureBlackTheme(v),
            ),
            ListTile(
              leading: _iconBox(Icons.settings, const Color(0xFF607D8B)),
              title: const Text('编辑器设置'),
              subtitle: const Text('快照、工具栏排序等'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/editor'),
            ),
            ListTile(
              leading: _iconBox(
                Icons.photo_size_select_large,
                const Color(0xFF3F51B5),
              ),
              title: const Text('图片最大宽度'),
              subtitle: Text('${settings.maxImageWidth}px，窄屏占满不受限制'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showMaxImageWidthDialog(context, settings),
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

          // ==================== 开发者选项 ====================
          _section(cs, '开发者选项', [
            SwitchListTile(
              secondary: _iconBox(Icons.face, const Color(0xFF9E9E9E)),
              title: const Text('显示头像'),
              subtitle: const Text('关闭后不再请求头像图片，仅显示文字'),
              value: settings.showAvatars,
              onChanged: (v) => settings.setShowAvatars(v),
            ),
            ListTile(
              leading: _iconBox(
                Icons.photo_size_select_actual,
                const Color(0xFF9E9E9E),
              ),
              title: const Text('头像尺寸'),
              subtitle: Text(settings.avatarSizeMode.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAvatarSizeDialog(context, settings),
            ),
            SwitchListTile(
              secondary: _iconBox(Icons.auto_fix_high, const Color(0xFF9E9E9E)),
              title: const Text('编辑器启动自检'),
              subtitle: const Text('关闭后编辑器忽略启动报错（如未登录、无权限等），无条件进入'),
              value: settings.editorStartupCheck,
              onChanged: (v) => settings.setEditorStartupCheck(v),
            ),
          ]),

          const SizedBox(height: 12),

          // ==================== 关于 ====================
          Material(
            color: cs.surface,
            child: ListTile(
              leading: Icon(Icons.info_outline, color: cs.onSurfaceVariant),
              title: const Text('关于'),
              subtitle: Text(
                'MTBBS v${BuildConfig.versionName}+${BuildConfig.versionCode}',
              ),
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

  void _showMaxImageWidthDialog(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final ctl = TextEditingController(text: settings.maxImageWidth.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('图片最大宽度'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('宽屏下帖子图片的最大宽度（100-2000px）。窄屏（手机）不受限制，自动占满宽度。'),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '宽度（px）',
                border: OutlineInputBorder(),
                isDense: true,
                helperText: '默认 600px',
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
              final v = int.tryParse(ctl.text.trim()) ?? 600;
              settings.setMaxImageWidth(v);
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

  void _showUADialog(BuildContext context, SettingsProvider settings) {
    final site = SiteStore.instance.current;
    final isMobile = site.isMobileUA;
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('浏览模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('选择当前站点使用的页面渲染模式：'),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.phone_android, color: cs.primary),
              title: const Text('移动版'),
              subtitle: const Text('使用手机 UA 访问，克米模板卡片式布局，默认推荐'),
              trailing: isMobile ? Icon(Icons.check, color: cs.primary) : null,
              onTap: () async {
                await settings.setSiteUA(Site.uaAndroid);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: Icon(Icons.desktop_windows, color: cs.onSurfaceVariant),
              title: const Text('桌面版'),
              subtitle: const Text('使用电脑 UA 访问，标准 Discuz 表格布局'),
              trailing: !isMobile ? Icon(Icons.check, color: cs.primary) : null,
              onTap: () async {
                await settings.setSiteUA(Site.uaPc);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showAvatarSizeDialog(BuildContext context, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: const Text('头像尺寸'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'small / middle / big 三种尺寸图片差异不大。'
              '固定某一尺寸可让同一用户在所有场景共用同一 URL，'
              '提高头像缓存命中率，避免重复下载。',
            ),
            const SizedBox(height: 16),
            for (final mode in AvatarSizeMode.values)
              ListTile(
                leading: Icon(_avatarSizeIcon(mode), color: cs.primary),
                title: Text(mode.label),
                subtitle: Text(_avatarSizeDesc(mode)),
                trailing: settings.avatarSizeMode == mode
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () async {
                  await settings.setAvatarSizeMode(mode);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  IconData _avatarSizeIcon(AvatarSizeMode mode) {
    switch (mode) {
      case AvatarSizeMode.auto:
        return Icons.auto_awesome;
      case AvatarSizeMode.small:
        return Icons.photo_size_select_small;
      case AvatarSizeMode.middle:
        return Icons.photo_size_select_actual;
      case AvatarSizeMode.big:
        return Icons.photo_size_select_large;
    }
  }

  String _avatarSizeDesc(AvatarSizeMode mode) {
    switch (mode) {
      case AvatarSizeMode.auto:
        return '按头像显示大小自动选择 small / middle / big（原行为）';
      case AvatarSizeMode.small:
        return '所有头像统一加载小尺寸';
      case AvatarSizeMode.middle:
        return '所有头像统一加载中尺寸（默认）';
      case AvatarSizeMode.big:
        return '所有头像统一加载大尺寸';
    }
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

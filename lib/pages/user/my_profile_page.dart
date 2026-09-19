import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/pages/settings/widgets/dialogs.dart';

/// 我的页面
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();

    final themeIcon = switch (settings.themeMode) {
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.system => Icons.settings_brightness,
    };

    return Material(
      type: MaterialType.transparency,
      child: ListView(
        children: [
          // 用户卡片
          Container(
            padding: const EdgeInsets.all(20),
            color: cs.surface,
            child: Row(
              children: [
                UserAvatar(uid: auth.uid, nickname: auth.username, radius: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.isLoggedIn ? auth.username : '未登录',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auth.isLoggedIn ? 'UID: ${auth.uid}' : '登录后可浏览论坛',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(themeIcon),
                  tooltip: '主题模式',
                  onPressed: () => showThemeModeDialog(
                    context,
                    context.read<SettingsProvider>(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  tooltip: '切换账号',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const UserManagementDialog(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 功能列表
          Material(
            color: cs.surface,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('小黑屋'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/darkroom'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('在线用户'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/online'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('浏览记录'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/history'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('我的帖子'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/my-threads'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.reply_outlined),
                  title: const Text('最近回复'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/my-threads?type=reply'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: const Text('我的收藏'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/favorite'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('设置'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
          ),

          // 开源信息
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
            child: Text(
              'https://github.com/qcxs/mtbbs_app',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

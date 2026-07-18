import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/widgets/login_sheet.dart';
import '../../widgets/user_avatar.dart';

/// 我的页面
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Material(
      type: MaterialType.transparency,
      child: ListView(
        children: [
          // 用户卡片
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
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
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!auth.isLoggedIn)
                  ElevatedButton(
                    onPressed: () => showLoginSheet(context),
                    child: const Text('登录'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 功能列表
          Material(
            color: Colors.white,
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
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  subtitle: const Text('MTBBS v1.0.0'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
              ],
            ),
          ),

          if (auth.isLoggedIn) ...[
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                onTap: () => auth.logout(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

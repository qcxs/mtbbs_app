import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/pages/settings/user_management_dialog.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 当前身份头像按钮 —— 编辑器 / 迷你编辑器旁边的小头像。
///
/// 点击弹出「当前身份」面板（站点 + 账号 + 登录状态），避免用户切换站点/账号后
/// 忘了自己以谁的身份发帖、评论。
class IdentityAvatarButton extends StatelessWidget {
  /// 头像半径（编辑器 14、迷你编辑器 12 左右）
  final double radius;

  const IdentityAvatarButton({super.key, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.username.isNotEmpty ? auth.username : '游客';
    return Tooltip(
      message: '当前身份：$name',
      child: InkResponse(
        onTap: () => showCurrentIdentitySheet(context),
        radius: radius + 8,
        child: UserAvatar(
          uid: auth.uid,
          nickname: auth.username,
          radius: radius,
          tapAction: AvatarTapAction.none,
        ),
      ),
    );
  }
}

/// 弹出「当前身份」底部面板
Future<void> showCurrentIdentitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _IdentitySheet(),
  );
}

class _IdentitySheet extends StatelessWidget {
  const _IdentitySheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final site = SiteStore.instance.current;
    final loggedIn = auth.isLoggedIn;
    final status = auth.isExpired
        ? '登录已过期'
        : (loggedIn ? '已登录' : '未登录（游客）');
    final name = auth.username.isNotEmpty ? auth.username : '游客';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                UserAvatar(
                  uid: auth.uid,
                  nickname: auth.username,
                  radius: 24,
                  tapAction: AvatarTapAction.none,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: auth.isExpired || !loggedIn
                              ? cs.error
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _infoRow(context, '站点', '${site.name}（${site.host}）'),
            if (auth.uid.isNotEmpty) _infoRow(context, 'UID', auth.uid),
            if (auth.userGroup.isNotEmpty)
              _infoRow(context, '用户组', auth.userGroup),
            if (auth.credits.isNotEmpty) _infoRow(context, '积分', auth.credits),
            const SizedBox(height: 8),
            Text(
              '发帖、评论、回复都会以该身份提交。切换站点或账号后，请确认这里的身份。',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showDialog<void>(
                    context: context,
                    builder: (_) => const UserManagementDialog(),
                  );
                },
                icon: const Icon(Icons.switch_account_outlined, size: 18),
                label: Text(loggedIn ? '管理账号' : '登录 / 管理账号'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

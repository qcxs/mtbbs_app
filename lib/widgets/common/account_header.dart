import 'package:flutter/material.dart';
import 'package:mtbbs/widgets/common/user_avatar.dart';

/// 用户列表页顶部账号卡片：头像 + 昵称 + UID + 用户组 + 在线状态。
///
/// 关注/粉丝、好友等页共用（原先各写一份逐字相同的实现）。
/// [profile] 为资料 Map（可为 null，如尚未加载）；[uid] 为兜底 uid（路由参数）；
/// [fallbackLabel] 在无昵称且无 uid 时显示（如「关注」「好友」）。
class AccountHeader extends StatelessWidget {
  const AccountHeader({
    super.key,
    required this.profile,
    required this.uid,
    required this.fallbackLabel,
  });

  final Map<String, dynamic>? profile;
  final String uid;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = profile;
    final nickname = p?['nickname'] as String? ?? '';
    final resolvedUid = p?['uid'] as String? ?? uid;
    final activity = p?['activity'];
    final userGroup = activity is Map
        ? (activity['userGroup'] as String? ?? '')
        : '';
    final online = p?['online'] == true;
    final muted = TextStyle(fontSize: 12, color: cs.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          UserAvatar(
            uid: resolvedUid,
            nickname: nickname,
            radius: 26,
            tapAction: AvatarTapAction.none,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname.isNotEmpty
                      ? nickname
                      : (resolvedUid.isNotEmpty ? '用户 $resolvedUid' : fallbackLabel),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (resolvedUid.isNotEmpty) Text('UID: $resolvedUid', style: muted),
                    if (resolvedUid.isNotEmpty && userGroup.isNotEmpty) ...[
                      Text(' · ', style: muted),
                      Text(userGroup, style: muted),
                    ],
                    if (online) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.circle, size: 8, color: cs.primary),
                      const SizedBox(width: 2),
                      Text(
                        '在线',
                        style: TextStyle(fontSize: 12, color: cs.primary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

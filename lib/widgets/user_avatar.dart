import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/site_config.dart';
import '../core/cache_utils.dart';
import 'image_preview/image_preview.dart';

/// 头像点击行为
enum AvatarTapAction {
  /// 打开用户个人空间 `/user/$uid`
  openUserSpace,

  /// 无操作
  none,

  /// 全屏查看头像
  viewAvatar,

  /// 自定义行为，需配合 [UserAvatar.onTap] 使用
  custom,
}

/// 通用用户头像组件
///
/// 根据 [tapAction] 控制点击行为，默认为 [AvatarTapAction.openUserSpace]。
/// uid='0'（游客/未登录）时点击显示「请先登录」提示。
///
/// 根据 [radius] 自动选择头像尺寸：
/// - radius < 18 → small
/// - radius 18~27 → middle（默认）
/// - radius ≥ 28 → big
class UserAvatar extends StatelessWidget {
  final String uid;
  final double radius;
  final String? nickname;
  final bool showBorder;

  /// 点击行为，默认为 [AvatarTapAction.openUserSpace]
  final AvatarTapAction tapAction;

  /// 自定义点击回调，仅在 [tapAction] 为 [AvatarTapAction.custom] 时生效
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.uid,
    this.radius = 20,
    this.nickname,
    this.showBorder = false,
    this.tapAction = AvatarTapAction.openUserSpace,
    this.onTap,
  });

  String get _urlSize {
    if (radius >= 28) return 'big';
    if (radius >= 18) return 'middle';
    return 'small';
  }

  String get _url =>
      '${SiteConfig.baseUrl}/uc_server/avatar.php?uid=$uid&size=$_urlSize';

  String get _fallbackText {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    if (uid.isNotEmpty) return uid;
    return '?';
  }

  void _handleTap(BuildContext context) {
    switch (tapAction) {
      case AvatarTapAction.none:
        return;
      case AvatarTapAction.custom:
        onTap?.call();
        return;
      case AvatarTapAction.viewAvatar:
        showImageViewer(context, imageUrls: [_url]);
        return;
      case AvatarTapAction.openUserSpace:
        if (uid == '0') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先登录')));
          return;
        }
        context.push('/user/$uid');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (uid.isEmpty) return _fallback(cs);

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: cs.surfaceContainerLow,
      child: ClipOval(
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: _url,
              cacheManager: avatarCacheManager,
              width: radius * 2,
              height: radius * 2,
              memCacheWidth: (radius * 2 * 2).toInt(),
              memCacheHeight: (radius * 2 * 2).toInt(),
              fit: BoxFit.cover,
              placeholder: (_, __) => _fallback(cs),
              errorWidget: (_, __, ___) => _fallback(cs),
            ),
            if (showBorder)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (tapAction == AvatarTapAction.none) return avatar;

    return GestureDetector(onTap: () => _handleTap(context), child: avatar);
  }

  Widget _fallback(ColorScheme cs) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.surfaceContainerLow,
      child: Text(
        _fallbackText.isNotEmpty ? _fallbackText[0] : '?',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

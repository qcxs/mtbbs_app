import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/site_config.dart';
import '../core/cache_utils.dart';

/// 通用用户头像组件
///
/// 默认点击行为：打开用户个人空间 `/user/$uid`。
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

  /// 设为 true 禁用点击（如个人空间页自己的头像）
  final bool disableTap;

  /// 自定义点击回调，覆盖默认行为
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.uid,
    this.radius = 20,
    this.nickname,
    this.showBorder = false,
    this.disableTap = false,
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
    if (onTap != null) {
      onTap!();
      return;
    }
    if (uid == '0') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }
    context.push('/user/$uid');
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return _fallback();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.shade100,
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
              placeholder: (_, __) => _fallback(),
              errorWidget: (_, __, ___) => _fallback(),
            ),
            if (showBorder)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (disableTap) return avatar;

    return GestureDetector(onTap: () => _handleTap(context), child: avatar);
  }

  Widget _fallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.shade100,
      child: Text(
        _fallbackText.isNotEmpty ? _fallbackText[0] : '?',
        style: TextStyle(
          color: Colors.deepPurple.shade700,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

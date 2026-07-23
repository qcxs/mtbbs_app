import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/cache_utils.dart';
import '../core/site_store.dart';
import '../core/stagger_queue.dart';
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
///
/// 内部使用全局错峰队列控制加载间隔，大量头像同时出现时自动以设定间隔排队请求。
class UserAvatar extends StatefulWidget {
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

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  StaggerSlot? _loadTask;
  bool _ready = false;
  String? _resolvedUrl;

  /// 301 重定向缓存，映射原始 URL → 最终 URL（null 表示无重定向）
  static final _redirectCache = <String, String?>{};

  /// 正在解析中的重定向请求
  static final _pendingRedirects = <String, Future<String?>>{};

  String get _urlSize {
    if (widget.radius >= 28) return 'big';
    if (widget.radius >= 18) return 'middle';
    return 'small';
  }

  String get _originalUrl =>
      '${SiteStore.instance.baseUrl}/uc_server/avatar.php?uid=${widget.uid}&size=$_urlSize';

  /// 最终使用的图片 URL（已解析重定向，或原始 URL）
  String get _imageUrl => _resolvedUrl ?? _originalUrl;

  String get _fallbackText {
    if (widget.nickname != null && widget.nickname!.isNotEmpty) {
      return widget.nickname!;
    }
    if (widget.uid.isNotEmpty) return widget.uid;
    return '?';
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _loadTask?.cancel();
      _ready = false;
      _resolvedUrl = null;
      _schedule();
    }
  }

  /// 解析 301 重定向 → 检查缓存 → 排队加载
  Future<void> _schedule() async {
    final originalUrl = _originalUrl;
    if (!mounted) return;

    // 1. 解析 301 重定向，获取 CDN 直链
    _resolvedUrl = await _resolveRedirect(originalUrl);
    if (!mounted) return;

    // 2. 以最终 URL 为 key 检查磁盘缓存
    final cacheUrl = _imageUrl;
    final cached = await avatarCacheManager.getFileFromCache(cacheUrl);
    if (!mounted) return;

    if (cached != null && cached.file.existsSync()) {
      setState(() => _ready = true);
      return;
    }

    // 3. 未缓存 → 错峰排队
    _loadTask = enqueueStagger();
    _loadTask!.ready.then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// 解析 301 重定向，返回最终 URL
  ///
  /// 所有 [UserAvatar] 实例共享内存缓存，相同原始 URL 只发一次 HEAD 请求。
  Future<String?> _resolveRedirect(String url) async {
    if (_redirectCache.containsKey(url)) return _redirectCache[url];
    if (_pendingRedirects.containsKey(url)) return _pendingRedirects[url];

    final future = _doResolve(url);
    _pendingRedirects[url] = future;
    try {
      final result = await future;
      _redirectCache[url] = result;
      return result;
    } finally {
      _pendingRedirects.remove(url);
    }
  }

  /// 发送 HEAD 请求，不跟随重定向，读取 Location 头
  Future<String?> _doResolve(String url) async {
    final client = HttpClient();
    try {
      final request = await client.headUrl(Uri.parse(url));
      request.followRedirects = false;
      final response = await request.close();
      final statusCode = response.statusCode;
      if (statusCode >= 300 && statusCode < 400) {
        final location = response.headers.value('location');
        if (location != null && location.isNotEmpty) {
          if (location.startsWith('http://') ||
              location.startsWith('https://')) {
            return location;
          }
          // 相对路径 → 拼接完整 URL
          final uri = Uri.parse(url);
          return '${uri.scheme}://${uri.host}$location';
        }
      }
      // 没有重定向，使用原始 URL
      return url;
    } catch (_) {
      return url;
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _loadTask?.cancel();
    super.dispose();
  }

  void _handleTap(BuildContext context) {
    switch (widget.tapAction) {
      case AvatarTapAction.none:
        return;
      case AvatarTapAction.custom:
        widget.onTap?.call();
        return;
      case AvatarTapAction.viewAvatar:
        showImageViewer(context, imageUrls: [_imageUrl]);
        return;
      case AvatarTapAction.openUserSpace:
        if (widget.uid == '0') {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先登录')));
          return;
        }
        context.push('/user/${widget.uid}');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.uid.isEmpty) return _fallback(cs);

    Widget avatarContent;
    if (_ready) {
      avatarContent = ClipOval(
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: _imageUrl,
              cacheManager: avatarCacheManager,
              width: widget.radius * 2,
              height: widget.radius * 2,
              memCacheWidth: (widget.radius * 2 * 2).toInt(),
              memCacheHeight: (widget.radius * 2 * 2).toInt(),
              fit: BoxFit.cover,
              placeholder: (_, __) => SizedBox(
                width: widget.radius * 2,
                height: widget.radius * 2,
                child: Center(
                  child: SizedBox(
                    width: widget.radius * 0.6,
                    height: widget.radius * 0.6,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => _fallback(cs),
            ),
            if (widget.showBorder)
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
      );
    } else {
      avatarContent = _fallback(cs);
    }

    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: cs.surfaceContainerLow,
      child: avatarContent,
    );

    if (widget.tapAction == AvatarTapAction.none) return avatar;

    return GestureDetector(onTap: () => _handleTap(context), child: avatar);
  }

  Widget _fallback(ColorScheme cs) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: cs.surfaceContainerLow,
      child: Text(
        _fallbackText.isNotEmpty ? _fallbackText[0] : '?',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: widget.radius * 0.7,
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
import 'package:mtbbs/core/app/avatar_url.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/image_preview/image_preview.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

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
/// 根据 [radius] 自动选择头像尺寸（[AvatarSizeMode.auto] 时）：
/// - radius < 18 → small
/// - radius 18~27 → middle（默认）
/// - radius ≥ 28 → big
///
/// 可通过设置「头像尺寸」固定为 small / middle / big，提高头像缓存命中率。
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
  bool _scheduledOnce = false;
  bool _lastShowAvatars = true;
  String? _resolvedUrl;

  /// 正在解析中的重定向请求（内存去重，避免同一 URL 并发重复 HEAD）
  static final _pendingRedirects = <String, Future<String>>{};

  /// 上一次生效的头像尺寸策略（首次构建时为 null，用于检测策略变化）
  AvatarSizeMode? _lastSizeMode;

  /// 按当前尺寸策略生成原始头像 URL：站点配置的模板，未配置时回退默认 API 方案
  String _originalUrlFor(AvatarSizeMode mode) => resolveAvatarUrl(
    template: SiteStore.instance.current.avatarTemplate ?? '',
    baseUrl: SiteStore.instance.baseUrl,
    cdn: SiteStore.instance.cdnUrl,
    uid: widget.uid,
    size: resolveAvatarSize(mode, widget.radius),
  );

  /// 原始头像 URL：按站点配置的模板解析，未配置时回退默认 API 方案
  String get _originalUrl =>
      _originalUrlFor(context.read<SettingsProvider>().avatarSizeMode);

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
      _scheduledOnce = false;
      _resolvedUrl = null;
      _schedule();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 仅在头像设置从禁用→启用时重新调度，避免父级 rebuild 重复触发磁盘 I/O
    // build 方法已通过 context.select 订阅 showAvatars 变化，此处只需读当前值
    final settings = context.read<SettingsProvider>();
    final showAvatars = settings.showAvatars;
    if (showAvatars && !_lastShowAvatars) {
      _lastShowAvatars = true;
      if (!_scheduledOnce) _schedule();
    }
    _lastShowAvatars = showAvatars;

    // 头像尺寸策略变化 → 原 URL 尺寸可能失效，重置后按新策略重新调度
    final sizeMode = settings.avatarSizeMode;
    if (_lastSizeMode != null && sizeMode != _lastSizeMode) {
      _loadTask?.cancel();
      _ready = false;
      _scheduledOnce = false;
      _resolvedUrl = null;
      _schedule();
    }
    _lastSizeMode = sizeMode;
  }

  /// 磁盘缓存是否新鲜（存在且未过期）
  Future<bool> _isFreshCache(String url) async {
    final info = await avatarCacheManager.getFileFromCache(url);
    return info != null &&
        info.file.existsSync() &&
        info.validTill.isAfter(DateTime.now());
  }

  /// 解析重定向 → 检查缓存 → 排队加载（仅执行一次）
  ///
  /// 顺序与旧实现相反：**先查缓存，缓存命中不发任何 HEAD 请求**；
  /// 仅当缓存缺失或过期时才 HEAD 重新解析重定向（结果持久化，供下次免 HEAD）。
  Future<void> _schedule() async {
    if (_scheduledOnce || !mounted) return;
    _scheduledOnce = true;

    // 头像已禁用 → 跳过所有网络请求；同时在此确定本次调度的尺寸策略
    final settings = context.read<SettingsProvider>();
    if (!settings.showAvatars) return;

    // 确保重定向映射已从磁盘加载
    await AvatarRedirectStore.instance.loadIfNeeded();
    if (!mounted) return;

    final originalUrl = _originalUrlFor(settings.avatarSizeMode);

    // 1. 已有重定向映射 → 不发 HEAD，直接以最终 URL 为 key 查磁盘缓存
    final known = AvatarRedirectStore.instance.lookup(originalUrl);
    if (known.known) {
      if (await _isFreshCache(known.value)) {
        _resolvedUrl = known.value;
        setState(() => _ready = true);
        return;
      }
    } else {
      // 兼容旧版缓存：曾无重定向时以原始 URL 为 key 存储，命中即用并回写映射
      if (await _isFreshCache(originalUrl)) {
        AvatarRedirectStore.instance.set(originalUrl, originalUrl);
        setState(() => _ready = true);
        return;
      }
    }
    if (!mounted) return;

    // 2. 缓存缺失/过期 → HEAD 解析重定向（内存去重 + 持久化结果）
    final resolved = await _resolveRedirect(originalUrl);
    if (!mounted) return;

    // 3. 解析出的最终 URL 可能已有缓存（如映射丢失但文件仍在）
    if (await _isFreshCache(resolved)) {
      _resolvedUrl = resolved == originalUrl ? null : resolved;
      setState(() => _ready = true);
      return;
    }
    if (!mounted) return;

    // 4. 真正需要下载 → 错峰排队，CachedNetworkImage 负责下载并以最终 URL 缓存
    _resolvedUrl = resolved == originalUrl ? null : resolved;
    _loadTask = enqueueStagger();
    _loadTask!.ready.then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// 解析 301 重定向，返回最终 URL
  ///
  /// 所有 [UserAvatar] 实例共享持久化映射，相同原始 URL 只发一次 HEAD 请求，
  /// 结果写入 [AvatarRedirectStore] 供后续直接查缓存。
  Future<String> _resolveRedirect(String url) async {
    final known = AvatarRedirectStore.instance.lookup(url);
    if (known.known) return known.value;
    if (_pendingRedirects.containsKey(url)) return _pendingRedirects[url]!;

    final future = _doResolve(url);
    _pendingRedirects[url] = future;
    try {
      final result = await future;
      AvatarRedirectStore.instance.set(url, result);
      return result;
    } finally {
      _pendingRedirects.remove(url);
    }
  }

  /// 发送 HEAD 请求，不跟随重定向，读取 Location 头
  Future<String> _doResolve(String url) async {
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
          showToast('请先登录');
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

    // 头像已禁用 → 不发起任何网络请求，仅显示文字，但仍可点击
    final showAvatars = context.select<SettingsProvider, bool>(
      (s) => s.showAvatars,
    );
    if (!showAvatars) {
      final fb = _fallback(cs);
      if (widget.tapAction == AvatarTapAction.none) return fb;
      return GestureDetector(onTap: () => _handleTap(context), child: fb);
    }

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

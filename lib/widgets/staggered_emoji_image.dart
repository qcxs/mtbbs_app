import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../core/cache_utils.dart';
import '../core/stagger_queue.dart';

/// 错峰加载的表情图片组件
///
/// 大量表情首次出现时（如打开选择器、表情管理页），
/// 按通用错峰间隔逐个放行网络请求，避免短时间大量并发。
/// 缓存命中时直接显示，跳过排队。
///
/// [imageUrl]  表情图片 URL
/// [size]      图片尺寸（正方形边长），默认 30
/// [cacheManager] 缓存管理器，默认 [emojiCacheManager]
class StaggeredEmojiImage extends StatefulWidget {
  final String imageUrl;
  final double size;
  final CacheManager? cacheManager;

  const StaggeredEmojiImage({
    super.key,
    required this.imageUrl,
    this.size = 30,
    this.cacheManager,
  });

  @override
  State<StaggeredEmojiImage> createState() => _StaggeredEmojiImageState();
}

class _StaggeredEmojiImageState extends State<StaggeredEmojiImage> {
  StaggerSlot? _task;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(StaggeredEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _task?.cancel();
      _ready = false;
      _schedule();
    }
  }

  Future<void> _schedule() async {
    final manager = widget.cacheManager ?? emojiCacheManager;
    // 已缓存则直接加载
    final cached = await manager.getFileFromCache(widget.imageUrl);
    if (cached != null && cached.file.existsSync()) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    // 未缓存则排队等待放行
    _task = enqueueStagger();
    _task!.ready.then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _task?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_ready) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        cacheManager: widget.cacheManager ?? emojiCacheManager,
        width: widget.size,
        height: widget.size,
        errorWidget: (_, __, ___) => Icon(
          Icons.emoji_emotions_outlined,
          size: widget.size * 0.75,
          color: cs.onSurfaceVariant,
        ),
      );
    }
    // 等待放行时显示占位图标
    return Icon(
      Icons.emoji_emotions_outlined,
      size: widget.size * 0.75,
      color: cs.onSurfaceVariant,
    );
  }
}

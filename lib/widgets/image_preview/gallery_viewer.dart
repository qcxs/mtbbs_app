import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 画廊容器 — 全屏图片查看器
///
/// 基于 [PhotoViewGallery] 实现，成熟稳定的手势处理：
/// - 捏合缩放 / 双击缩放 / 平移
/// - 多图左右滑动翻页
/// - 点击图片任意位置关闭
/// - 黑色背景 + 底部页码指示器
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageCtrl = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: PhotoViewGallery.builder(
              itemCount: total,
              builder: (_, index) {
                return PhotoViewGalleryPageOptions(
                  imageProvider: CachedNetworkImageProvider(
                    widget.imageUrls[index],
                  ),
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 2.0,
                  initialScale: PhotoViewComputedScale.contained,
                );
              },
              scrollPhysics: const BouncingScrollPhysics(),
              loadingBuilder: (_, event) => Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                    value: event == null
                        ? null
                        : event.cumulativeBytesLoaded /
                              (event.expectedTotalBytes ?? 1),
                  ),
                ),
              ),
              pageController: _pageCtrl,
              onPageChanged: (i) => setState(() => _currentIndex = i),
            ),
          ),

          // 底部页码指示器
          if (total > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: IgnorePointer(
                child: Text(
                  '${_currentIndex + 1} / $total',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

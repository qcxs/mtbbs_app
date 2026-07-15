import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'image_utils.dart';

/// 长按图片时弹出操作菜单
///
/// [imageUrls] 可传入多张（帖子卡片），单选一张后可通过左右滑动切换。
/// [sourceInfo] 图片来源描述。
void showImageActions(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  String? sourceInfo,
}) {
  final idx = initialIndex.clamp(0, imageUrls.length - 1);
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('查看图片'),
            subtitle: imageUrls.length > 1
                ? Text('共 ${imageUrls.length} 张，可左右滑动切换')
                : null,
            onTap: () {
              Navigator.of(ctx).pop();
              // 延迟一帧确保底部弹窗完全关闭后再打开，
              // 避免 Navigator 过渡态导致 canPop 判断异常
              Future.microtask(
                () => showImageViewer(
                  context,
                  imageUrls: imageUrls,
                  initialIndex: idx,
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('图片信息'),
            onTap: () {
              Navigator.of(ctx).pop();
              showImageInfoDialog(
                context,
                url: imageUrls[idx],
                sourceInfo: sourceInfo,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 全屏图片查看器（支持多图左右滑动）
void showImageViewer(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) {
  GoRouter.of(
    context,
  ).push('/image-viewer', extra: {'urls': imageUrls, 'index': initialIndex});
}

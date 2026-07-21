import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 长图检测阈值（宽高比大于此值视为长图）
const double kLongPicRatio = 2.6;

/// 检测是否为长图
bool isLongPic(double imageWidth, double imageHeight, double containerHeight) {
  if (imageWidth <= 0 || imageHeight <= 0) return false;
  final ratio = imageHeight / imageWidth;
  return ratio > kLongPicRatio && imageHeight > containerHeight;
}

/// 计算长图模式的最小缩放（适配宽度）
double calcLongPicMinScale(double imageWidth, double imageHeight, double containerWidth, double containerHeight) {
  if (imageWidth <= 0) return 1.0;
  final ratio = imageHeight / imageWidth;
  return containerWidth / containerHeight * ratio;
}

/// 图片信息对话框
void showImageInfoDialog(
  BuildContext context, {
  required String url,
  String? sourceInfo,
  Map<String, dynamic>? meta,
}) {
  final sizeStr = meta != null ? '${meta['width'] ?? '?'} × ${meta['height'] ?? '?'}' : null;
  final nameStr = meta?['name'] as String?;
  final downloadsStr = meta?['downloads'] as String?;
  final uploadTimeStr = meta?['uploadTime'] as String?;

  showDialog(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('图片信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (nameStr != null) _infoRow('文件名', nameStr, cs),
            if (sizeStr != null) _infoRow('尺寸', sizeStr, cs),
            if (downloadsStr != null) _infoRow('下载次数', downloadsStr, cs),
            if (uploadTimeStr != null) _infoRow('上传时间', uploadTimeStr, cs),
            if (sourceInfo != null) _infoRow('来源', sourceInfo, cs),
            const SizedBox(height: 8),
            Text('URL:', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(url, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制链接'), duration: Duration(seconds: 1)),
              );
            },
            child: const Text('复制链接'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

Widget _infoRow(String label, String value, ColorScheme cs) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}

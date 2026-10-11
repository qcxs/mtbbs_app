import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:mtbbs/core/utils/logger.dart';

/// 保存结果（供调用方给用户不同反馈）
enum SaveImageOutcome { saved, canceled, permissionDenied, failed }

/// 可截图的边界：与 `RepaintBoundary` 等价，额外对外暴露底层 [OffsetLayer]。
///
/// 想做「分块截图」必须拿到 layer，但 `RenderObject.layer` 是 `@protected`
/// （外部不可访问），`debugLayer` 在 release 又恒为 null —— 只能靠子类暴露。
class CaptureBoundary extends SingleChildRenderObjectWidget {
  const CaptureBoundary({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CaptureRenderObject();
}

class _CaptureRenderObject extends RenderRepaintBoundary {
  /// 已挂载且已 paint 时返回底层 [OffsetLayer]，否则 null
  OffsetLayer? get offsetLayer =>
      layer is OffsetLayer ? layer as OffsetLayer : null;
}

/// 图片导出：把 [`CaptureBoundary`] 截成 PNG，并按平台保存。
///
/// 无状态工具类，供「生成图片」分享卡（`pages/thread/thread_share_page.dart`）使用。
abstract final class ImageExport {
  /// 单块位图的最大像素高度。
  ///
  /// 单张 GPU 纹理有硬件上限（常见 4096），超过会渲染失败或被引擎强制降采样。
  /// 故按此高度分块渲染，再在 CPU 侧拼成一张长图（见 [capturePng]）。
  static const double _maxTilePx = 4096;

  /// 输出位图的总像素预算（内存保护）。
  ///
  /// 「超长内容 × 3 倍」会得到数百 MB 的位图 → OOM。超过预算时按比例降采样，
  /// 保证"中等长度楼层保持 3x 清晰、极长楼层不崩"（见 docs/07「生成图片」条目）。
  static const int _maxOutputPx = 32 * 1000 * 1000;

  /// 把 [boundaryKey] 对应的 [`CaptureBoundary`] 截成 PNG 字节；失败返回 null。
  ///
  /// **分块渲染 + CPU 拼接**：不用 `RenderRepaintBoundary.toImage` 一次成图
  /// （超长内容会触单张纹理上限，只能降采样 → 糊），而是用底层
  /// `OffsetLayer.toImage(rect)` 逐块渲染，各块原始 RGBA 拷进一张大缓冲后
  /// 用纯 Dart 编码 PNG，任意长度都能保持 [pixelRatio] 的清晰度。
  static Future<Uint8List?> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3,
  }) async {
    final context = boundaryKey.currentContext;
    if (context == null) return null;
    final object = context.findRenderObject();
    if (object is! _CaptureRenderObject) return null;
    final size = object.size;
    if (size.isEmpty) return null;
    final layer = object.offsetLayer;
    if (layer == null) return null;

    // 目标比例：默认 [pixelRatio]，受总像素预算约束（极长内容才降采样）
    var ratio = pixelRatio;
    final logicalPx = size.width * size.height;
    final budgetRatio = math.sqrt(_maxOutputPx / logicalPx);
    if (budgetRatio < ratio) ratio = math.max(budgetRatio, 1.0);

    final outW = (size.width * ratio).ceil();

    // 规划分块（每块像素高 ≤ _maxTilePx），据此算出输出总高
    final tileLogicalH = math.max(1.0, (_maxTilePx / ratio).floorToDouble());
    final tiles = <({double y, double h, int pxH})>[];
    var y = 0.0;
    var totalPxH = 0;
    while (y < size.height) {
      final h = math.min(tileLogicalH, size.height - y);
      final pxH = (ratio * h).ceil();
      tiles.add((y: y, h: h, pxH: pxH));
      totalPxH += pxH;
      y += h;
    }

    final out = img.Image(width: outW, height: totalPxH);
    var dstY = 0;
    try {
      for (final t in tiles) {
        final tile = await layer.toImage(
          Rect.fromLTWH(0, t.y, size.width, t.h),
          pixelRatio: ratio,
        );
        try {
          final bd = await tile.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (bd == null) return null;
          final tileImg = img.Image.fromBytes(
            width: tile.width,
            height: tile.height,
            bytes: bd.buffer,
            bytesOffset: bd.offsetInBytes,
            order: img.ChannelOrder.rgba,
          );
          img.compositeImage(out, tileImg, dstY: dstY);
        } finally {
          tile.dispose();
        }
        dstY += t.pxH;
      }
      return img.encodePng(out);
    } catch (e) {
      AppLogger.w('PAGE', '生成图片失败：$e');
      return null;
    }
  }

  /// 保存 PNG 字节：移动端存相册（gal，自带权限处理），桌面端走"另存为"对话框。
  static Future<SaveImageOutcome> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (Platform.isAndroid || Platform.isIOS) {
      return _saveToGallery(bytes, fileName);
    }
    return _saveAsFile(bytes, fileName);
  }

  static Future<SaveImageOutcome> _saveToGallery(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          return SaveImageOutcome.permissionDenied;
        }
      }
      await Gal.putImageBytes(bytes, name: fileName);
      return SaveImageOutcome.saved;
    } on GalException catch (e) {
      AppLogger.w('PAGE', '保存到相册失败：${e.type}');
      return e.type == GalExceptionType.accessDenied
          ? SaveImageOutcome.permissionDenied
          : SaveImageOutcome.failed;
    } catch (e) {
      AppLogger.w('PAGE', '保存到相册异常：$e');
      return SaveImageOutcome.failed;
    }
  }

  static Future<SaveImageOutcome> _saveAsFile(
    Uint8List bytes,
    String fileName,
  ) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存图片',
        fileName: '$fileName.png',
        type: FileType.image,
      );
      if (path == null) return SaveImageOutcome.canceled;
      await File(path).writeAsBytes(bytes);
      return SaveImageOutcome.saved;
    } catch (e) {
      AppLogger.w('PAGE', '另存为失败：$e');
      return SaveImageOutcome.failed;
    }
  }
}

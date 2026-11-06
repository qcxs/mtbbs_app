import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 保存生成的分享图的结果。
///
/// 刻意区分「相册」与「另存为」：Android/iOS 相册失败会回退到文件保存，
/// 两者成功的提示文案不同（避免明明存到了文件却提示“已保存到相册”）。
enum SaveImageOutcome {
  savedToGallery,
  savedToFile,
  canceled,
  permissionDenied,
  failed,
  unavailable,
}

/// 分享图保存适配器。
///
/// **唯一** import `gal` / `file_picker.saveFile` 的地方：
/// - Android / iOS 优先存相册（gal，自带权限处理）；
/// - 鸿蒙走“另存为”（file_picker 的 OH 分支要求传入已存在的源文件路径）；
/// - 其他平台（Windows 等）走“另存为”对话框；
/// - 相册不可用或失败时自动回退到“另存为”。
///
/// 平台差异：Android/iOS 的 `file_picker.saveFile` 要求必须传 bytes，且由插件
/// 直接写入；桌面端只需返回路径后自行写入（macOS 传 bytes 会抛错）。
///
/// 插件缺失时返回 [SaveImageOutcome.unavailable] 并关闭
/// [AppCapability.saveImage]，由入口隐藏/提示，而不是抛异常。
abstract final class ImageSave {
  ImageSave._();

  static Future<SaveImageOutcome> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.saveImage)) {
      return SaveImageOutcome.unavailable;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final gallery = await _saveToGallery(bytes, fileName);
      if (gallery == SaveImageOutcome.savedToGallery ||
          gallery == SaveImageOutcome.canceled) {
        return gallery;
      }
      // 相册不可用 / 无权限 / 失败 → 回退到“另存为”
    }

    final file = AppCapabilities.isOhos
        ? await _saveAsFileForOhos(bytes, fileName)
        : await _saveAsFile(bytes, fileName);
    if (file == SaveImageOutcome.unavailable) {
      AppCapabilities.disable(AppCapability.saveImage);
    }
    return file;
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
      // Gal 的 name 不带扩展名（插件按 bytes 推断）
      await Gal.putImageBytes(bytes, name: fileName);
      return SaveImageOutcome.savedToGallery;
    } on GalException catch (e) {
      AppLogger.w('PAGE', '保存到相册失败：${e.type}');
      return e.type == GalExceptionType.accessDenied
          ? SaveImageOutcome.permissionDenied
          : SaveImageOutcome.failed;
    } on MissingPluginException {
      AppLogger.w('PAGE', 'gal 无当前平台实现，改走另存为');
      return SaveImageOutcome.unavailable;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'gal 无当前平台实现，改走另存为');
      return SaveImageOutcome.unavailable;
    } catch (e) {
      AppLogger.w('PAGE', '保存到相册异常：$e');
      return SaveImageOutcome.failed;
    }
  }

  static Future<SaveImageOutcome> _saveAsFile(
    Uint8List bytes,
    String fileName,
  ) async {
    final writtenByPlugin = Platform.isAndroid || Platform.isIOS;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存图片',
        fileName: '$fileName.png',
        type: FileType.image,
        // Android/iOS 必须传 bytes，由插件直接写入；桌面端不传（macOS 会抛错）
        bytes: writtenByPlugin ? bytes : null,
      );
      if (path == null) return SaveImageOutcome.canceled;
      if (!writtenByPlugin) {
        await File(path).writeAsBytes(bytes);
      }
      return SaveImageOutcome.savedToFile;
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      return SaveImageOutcome.unavailable;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      return SaveImageOutcome.unavailable;
    } catch (e) {
      AppLogger.w('PAGE', '另存为失败：$e');
      return SaveImageOutcome.failed;
    }
  }

  /// 鸿蒙“另存为”。
  ///
  /// file_picker 的 OH 分支与官方实现语义不同：`initialDirectory` 不是“对话框初始
  /// 目录”，而是**要保存的源文件路径**——原生会先把该路径的文件复制到用户选中的
  /// 位置（`bytes` 参数被忽略）。因此这里先把图片写到缓存临时文件，再把该文件
  /// 路径传给 `saveFile`；插件的复制在 `saveFile` 返回前完成，之后即可删除临时文件。
  static Future<SaveImageOutcome> _saveAsFileForOhos(
    Uint8List bytes,
    String fileName,
  ) async {
    File? temp;
    try {
      final dir = Directory('${await AppPaths.tempDir}/save_export');
      if (!await dir.exists()) await dir.create(recursive: true);
      temp = File(
        '${dir.path}/${fileName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await temp.writeAsBytes(bytes, flush: true);

      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存图片',
        fileName: '$fileName.png',
        initialDirectory: temp.path,
        type: FileType.image,
      );
      return path == null
          ? SaveImageOutcome.canceled
          : SaveImageOutcome.savedToFile;
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      return SaveImageOutcome.unavailable;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      return SaveImageOutcome.unavailable;
    } catch (e) {
      AppLogger.w('PAGE', '鸿蒙另存为失败：$e');
      return SaveImageOutcome.failed;
    } finally {
      if (temp != null) {
        try {
          await temp.delete();
        } catch (_) {
          // 临时文件清理失败不影响保存结果
        }
      }
    }
  }
}

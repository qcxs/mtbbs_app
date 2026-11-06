import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 非图片文件保存结果
enum FileSaveOutcome { saved, canceled, unavailable, failed }

/// 非图片文件「另存为」适配器。
///
/// **唯一** 供非图片文件 import `file_picker.saveFile` 的地方（图片见
/// `image_save.dart`，选择文件见 `file_pick.dart`）。
///
/// file_picker 13 起 `saveFile` 的语义统一为「传入 bytes，由插件写入」：
/// - Android / iOS 由插件写入用户选中的文档（scoped storage 下也不能自己再写）；
/// - Windows / Linux / macOS 同样由插件落盘，返回 `Uri?`，不再是“只给路径”；
/// - `type` / `allowedExtensions` 已弃用（默认扩展名取自 [fileName]）。
///
/// - **鸿蒙**：file_picker 的 OH 分支与官方实现语义不同——`initialDirectory` 不是
///   “对话框初始目录”，而是**要保存的源文件路径**（原生把该文件复制到用户选中的
///   位置，`bytes` 参数被忽略）；不传会直接报 “initial Directory 为空”。因此这里
///   先把内容写到缓存临时文件，再以它为源交给插件。
///
/// 插件无当前平台实现时返回 [FileSaveOutcome.unavailable] 并关闭能力开关。
abstract final class FileSave {
  FileSave._();

  static bool get _isOhos => AppCapabilities.isOhos;

  /// 选择保存路径并写入文本（导出 JSON 等）
  static Future<FileSaveOutcome> saveText(
    String content, {
    required String fileName,
    String dialogTitle = '保存文件',
  }) {
    return saveBytes(
      Uint8List.fromList(utf8.encode(content)),
      fileName: fileName,
      dialogTitle: dialogTitle,
    );
  }

  /// 选择保存路径并写入二进制
  static Future<FileSaveOutcome> saveBytes(
    Uint8List bytes, {
    required String fileName,
    String dialogTitle = '保存文件',
  }) async {
    if (_isOhos) {
      return _saveBytesOnOhos(
        bytes,
        fileName: fileName,
        dialogTitle: dialogTitle,
      );
    }
    return _saveViaDialog(
      bytes,
      fileName: fileName,
      dialogTitle: dialogTitle,
    );
  }

  /// 选择保存路径并把已有文件另存。
  ///
  /// file_picker 13 的 `saveFile` 只接受 bytes，桌面端也必须先读入内存；
  /// 大文件（原始缓存库）导出请优先使用事务导出 / 尽力导出 JSON。
  static Future<FileSaveOutcome> copyFile(
    String sourcePath, {
    required String fileName,
    String dialogTitle = '保存文件',
  }) async {
    if (_isOhos) {
      // 源文件本来就存在于沙箱内，直接把它的路径交给 OH 分支复制
      return _saveExistingOnOhos(
        sourcePath,
        fileName: fileName,
        dialogTitle: dialogTitle,
      );
    }
    try {
      final bytes = await File(sourcePath).readAsBytes();
      return saveBytes(bytes, fileName: fileName, dialogTitle: dialogTitle);
    } catch (e) {
      AppLogger.w('PAGE', '读取待保存文件失败：$e');
      return FileSaveOutcome.failed;
    }
  }

  /// 鸿蒙「另存为」：先把内容落到缓存临时文件，再交给 OH 分支复制。
  static Future<FileSaveOutcome> _saveBytesOnOhos(
    Uint8List bytes, {
    required String fileName,
    required String dialogTitle,
  }) async {
    Directory? dir;
    try {
      // 每次单独一个子目录：用户可能选同名目标，避免互相覆盖
      dir = Directory(
        '${await AppPaths.tempDir}/save_export/${DateTime.now().millisecondsSinceEpoch}',
      );
      await dir.create(recursive: true);
      final temp = File('${dir.path}/$fileName');
      await temp.writeAsBytes(bytes, flush: true);
      return await _saveExistingOnOhos(
        temp.path,
        fileName: fileName,
        dialogTitle: dialogTitle,
        bytes: bytes,
      );
    } catch (e) {
      AppLogger.w('PAGE', '鸿蒙另存为失败：$e');
      return FileSaveOutcome.failed;
    } finally {
      if (dir != null) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // 临时目录清理失败不影响保存结果
        }
      }
    }
  }

  /// 鸿蒙「另存为」：`initialDirectory` 传源文件（OH 分支的原生语义）。
  ///
  /// [bytes] 仅供官方实现的签名要求：OH 分支在返回前用 `initialDirectory`
  /// 指向的源文件复制，**完全忽略 bytes**。已有大文件（缓存库导出）不要为了
  /// 这个必填参数把整份文件读进内存，传空列表即可。
  static Future<FileSaveOutcome> _saveExistingOnOhos(
    String sourcePath, {
    required String fileName,
    required String dialogTitle,
    Uint8List? bytes,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) {
      return FileSaveOutcome.unavailable;
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes ?? Uint8List(0),
        initialDirectory: sourcePath,
        mimeType: mimeTypeForFileName(fileName),
      );
      if (uri == null) return FileSaveOutcome.canceled;
      // 插件已在返回前把源文件复制到用户选中的位置，不要再写一次
      return FileSaveOutcome.saved;
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return FileSaveOutcome.unavailable;
    } on PlatformException catch (e) {
      // OH 分支的错误码/文案（如 13900001 无权访问）原样记录，便于排查
      AppLogger.w('PAGE', '鸿蒙另存为失败：${e.code} ${e.message}');
      return FileSaveOutcome.failed;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return FileSaveOutcome.unavailable;
    } catch (e) {
      AppLogger.w('PAGE', '鸿蒙另存为失败：$e');
      return FileSaveOutcome.failed;
    }
  }

  /// 官方实现统一的「另存为」：插件负责选路径并写入 [bytes]。
  static Future<FileSaveOutcome> _saveViaDialog(
    Uint8List bytes, {
    required String fileName,
    required String dialogTitle,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) {
      return FileSaveOutcome.unavailable;
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeTypeForFileName(fileName),
      );
      return uri == null ? FileSaveOutcome.canceled : FileSaveOutcome.saved;
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return FileSaveOutcome.unavailable;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return FileSaveOutcome.unavailable;
    } catch (e) {
      AppLogger.w('PAGE', '另存为失败：$e');
      return FileSaveOutcome.failed;
    }
  }
}

/// 按文件名推断 MIME（`saveFile` 的默认值 application/octet-stream 会让
/// Android 的下载文档类型不匹配，部分文件管理器打不开）。
String mimeTypeForFileName(String fileName) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'json' => 'application/json',
    'txt' || 'md' || 'markdown' => 'text/plain',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}

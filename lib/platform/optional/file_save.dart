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
/// 平台差异（必须保留）：
/// - **Android / iOS**：`file_picker.saveFile` 要求**必须传 bytes**，由插件直接
///   写入用户选中的文档；返回值只是为了展示而拼出的 `Download/<文件名>`，
///   并不是真实可写路径。因此这里绝不能再 `File(path).write...` 写第二次
///   （scoped storage 下也会失败）。
/// - **Windows / Linux**：`saveFile` 只负责选路径，不写文件；调用方拿到路径后
///   自行写入/复制。
/// - **macOS**：`saveFile(bytes:)` 会直接抛 `UnsupportedError`，桌面端一律不传。
///
/// - **鸿蒙**：file_picker 的 OH 分支与官方实现语义不同——`initialDirectory` 不是
///   “对话框初始目录”，而是**要保存的源文件路径**（原生把该文件复制到用户选中的
///   位置，`bytes` 参数被忽略）；不传会直接报 “initial Directory 为空”。因此这里
///   先把内容写到缓存临时文件，再以它为源交给插件。
///
/// 插件无当前平台实现时返回 [FileSaveOutcome.unavailable] 并关闭能力开关。
abstract final class FileSave {
  FileSave._();

  /// Android / iOS 由 file_picker 直接写入 bytes
  static bool get _bytesRequired => Platform.isAndroid || Platform.isIOS;

  static bool get _isOhos => AppCapabilities.isOhos;

  /// 选择保存路径并写入文本（导出 JSON 等）
  static Future<FileSaveOutcome> saveText(
    String content, {
    required String fileName,
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) {
    return saveBytes(
      Uint8List.fromList(utf8.encode(content)),
      fileName: fileName,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
    );
  }

  /// 选择保存路径并写入二进制
  static Future<FileSaveOutcome> saveBytes(
    Uint8List bytes, {
    required String fileName,
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) async {
    if (_isOhos) {
      return _saveBytesOnOhos(
        bytes,
        fileName: fileName,
        dialogTitle: dialogTitle,
      );
    }
    final picked = await _pickSavePath(
      fileName: fileName,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
    if (picked.error != null) return picked.error!;
    // Android / iOS：插件已经把 bytes 写入用户选中的文档，不能再写一次
    if (picked.writtenByPlugin) return FileSaveOutcome.saved;
    try {
      await File(picked.path!).writeAsBytes(bytes);
      return FileSaveOutcome.saved;
    } catch (e) {
      AppLogger.w('PAGE', '写入文件失败：$e');
      return FileSaveOutcome.failed;
    }
  }

  /// 选择保存路径并把已有文件另存。
  ///
  /// 移动端读入内存后交给 file_picker（插件要求 bytes）；桌面端保留
  /// `File.copy`，避免大文件整体进内存。
  static Future<FileSaveOutcome> copyFile(
    String sourcePath, {
    required String fileName,
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) async {
    if (_isOhos) {
      // 源文件本来就存在于沙箱内，直接把它的路径交给 OH 分支复制
      return _saveExistingOnOhos(
        sourcePath,
        fileName: fileName,
        dialogTitle: dialogTitle,
      );
    }
    if (_bytesRequired) {
      try {
        final bytes = await File(sourcePath).readAsBytes();
        return saveBytes(
          bytes,
          fileName: fileName,
          dialogTitle: dialogTitle,
          allowedExtensions: allowedExtensions,
        );
      } catch (e) {
        AppLogger.w('PAGE', '读取待保存文件失败：$e');
        return FileSaveOutcome.failed;
      }
    }
    final picked = await _pickSavePath(
      fileName: fileName,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
    );
    if (picked.error != null) return picked.error!;
    try {
      await File(sourcePath).copy(picked.path!);
      return FileSaveOutcome.saved;
    } catch (e) {
      AppLogger.w('PAGE', '复制文件失败：$e');
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
  static Future<FileSaveOutcome> _saveExistingOnOhos(
    String sourcePath, {
    required String fileName,
    required String dialogTitle,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) {
      return FileSaveOutcome.unavailable;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        initialDirectory: sourcePath,
      );
      if (path == null) return FileSaveOutcome.canceled;
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

  /// 选中的路径（[path]）或失败结果（[error]）；[writtenByPlugin] 表示
  /// 移动端已由插件写盘，调用方不要再写。
  static Future<
    ({String? path, FileSaveOutcome? error, bool writtenByPlugin})
  >
  _pickSavePath({
    required String fileName,
    required String dialogTitle,
    List<String>? allowedExtensions,
    Uint8List? bytes,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) {
      return (
        path: null,
        error: FileSaveOutcome.unavailable,
        writtenByPlugin: false,
      );
    }
    final writtenByPlugin = _bytesRequired;
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions == null || allowedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions: allowedExtensions,
        // 只有移动端传 bytes；桌面端的 saveFile 不接受（macOS 会直接抛错）
        bytes: writtenByPlugin ? bytes : null,
      );
      if (path == null) {
        return (
          path: null,
          error: FileSaveOutcome.canceled,
          writtenByPlugin: false,
        );
      }
      return (path: path, error: null, writtenByPlugin: writtenByPlugin);
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return (
        path: null,
        error: FileSaveOutcome.unavailable,
        writtenByPlugin: false,
      );
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return (
        path: null,
        error: FileSaveOutcome.unavailable,
        writtenByPlugin: false,
      );
    } catch (e) {
      AppLogger.w('PAGE', '另存为失败：$e');
      return (
        path: null,
        error: FileSaveOutcome.failed,
        writtenByPlugin: false,
      );
    }
  }
}

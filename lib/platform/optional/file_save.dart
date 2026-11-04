import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
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
/// 插件无当前平台实现时返回 [FileSaveOutcome.unavailable] 并关闭能力开关。
abstract final class FileSave {
  FileSave._();

  /// Android / iOS 由 file_picker 直接写入 bytes
  static bool get _bytesRequired => Platform.isAndroid || Platform.isIOS;

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

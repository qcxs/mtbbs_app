import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 非图片文件保存结果
enum FileSaveOutcome { saved, canceled, unavailable, failed }

/// 非图片文件「另存为」/「选择目录」适配器。
///
/// **唯一** 供非图片文件 import `file_picker.saveFile/getDirectoryPath`
/// 的地方（图片见 `image_save.dart`，选择文件见 `file_pick.dart`）。
/// 插件无当前平台实现时返回 [FileSaveOutcome.unavailable] 并关闭能力开关。
abstract final class FileSave {
  FileSave._();

  /// 选择保存路径并写入文本（导出 JSON 等）
  static Future<FileSaveOutcome> saveText(
    String content, {
    required String fileName,
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) async {
    final picked = await _pickSavePath(
      fileName: fileName,
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
    );
    if (picked.error != null) return picked.error!;
    try {
      await File(picked.path!).writeAsString(content);
      return FileSaveOutcome.saved;
    } catch (e) {
      AppLogger.w('PAGE', '写入文件失败：$e');
      return FileSaveOutcome.failed;
    }
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
    );
    if (picked.error != null) return picked.error!;
    try {
      await File(picked.path!).writeAsBytes(bytes);
      return FileSaveOutcome.saved;
    } catch (e) {
      AppLogger.w('PAGE', '写入文件失败：$e');
      return FileSaveOutcome.failed;
    }
  }

  /// 选择保存路径并把已有文件复制过去（原始缓存库备份）
  static Future<FileSaveOutcome> copyFile(
    String sourcePath, {
    required String fileName,
    String dialogTitle = '保存文件',
    List<String>? allowedExtensions,
  }) async {
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

  /// 选择目录（导出原始文件的伴随文件时使用）；取消返回 null
  static Future<String?> pickDirectory({String dialogTitle = '选择目录'}) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) return null;
    try {
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return null;
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return null;
    } catch (e) {
      AppLogger.w('PAGE', '选择目录失败：$e');
      return null;
    }
  }

  /// 选中的路径（[path]）或失败结果（[error]）
  static Future<({String? path, FileSaveOutcome? error})> _pickSavePath({
    required String fileName,
    required String dialogTitle,
    List<String>? allowedExtensions,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) {
      return (path: null, error: FileSaveOutcome.unavailable);
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions == null || allowedExtensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (path == null) {
        return (path: null, error: FileSaveOutcome.canceled);
      }
      return (path: path, error: null);
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return (path: null, error: FileSaveOutcome.unavailable);
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker.saveFile 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return (path: null, error: FileSaveOutcome.unavailable);
    } catch (e) {
      AppLogger.w('PAGE', '另存为失败：$e');
      return (path: null, error: FileSaveOutcome.failed);
    }
  }
}

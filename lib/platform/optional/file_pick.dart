import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/logger.dart';

export 'package:file_picker/file_picker.dart' show FileType, PlatformFile;

/// 文件选择适配器。
///
/// **唯一** import `file_picker` 的地方（保存另存为见 `image_save.dart` /
/// `file_save.dart`）。插件没有当前平台实现（如部分鸿蒙版本）时返回
/// 空列表 / null 并关闭 [AppCapability.filePicker]，由调用方按“用户取消”处理。
///
/// file_picker 13 起：
/// - `pickFiles` 总是可多选，取消返回空列表（不再有 `FilePickerResult`）；
/// - 单选改用 `pickFile`；
/// - `PlatformFile` 不再带 `bytes` / `size`，改按需 `readAsBytes()` / `length()`。
abstract final class FilePick {
  FilePick._();

  /// 选择多个文件（取消返回空列表）。
  static Future<List<PlatformFile>> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) return const [];
    try {
      return await FilePicker.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        // 新版默认 compressionQuality = 0（不压缩）：GIF 不再被转 JPG
        // （旧版必须显式 allowCompression: false，见 docs/07 #14）
      );
    } on MissingPluginException {
      AppLogger.w('PAGE', 'file_picker 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return const [];
    } on UnimplementedError {
      AppLogger.w('PAGE', 'file_picker 无当前平台实现');
      AppCapabilities.disable(AppCapability.filePicker);
      return const [];
    } catch (e) {
      // 插件参数错误 / 系统拒绝 / 选择器异常：按“用户取消”返回，避免把
      // PlatformException 冒到 UI 变成未捕获异常
      AppLogger.w('PAGE', '选择文件失败：$e');
      return const [];
    }
  }

  /// 选择单个文件（取消返回 null）。
  static Future<PlatformFile?> pickFile({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) return null;
    try {
      return await FilePicker.pickFile(
        type: type,
        allowedExtensions: allowedExtensions,
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
      AppLogger.w('PAGE', '选择文件失败：$e');
      return null;
    }
  }

  /// 清理 `pickFiles` 在 Android/iOS 复制到缓存的临时副本。
  ///
  /// 只删 `{tempDir}/file_picker/` 下的副本，绝不触碰用户原文件；桌面端
  /// `pickFiles` 直接返回原路径，本方法为空操作。
  static Future<void> cleanupTemp(String? path) async {
    if (path == null || path.isEmpty) return;
    await deleteFilePickerTempIfAny(path);
  }
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/logger.dart';

export 'package:file_picker/file_picker.dart'
    show FileType, FilePickerResult, PlatformFile;

/// 文件选择适配器。
///
/// **唯一** import `file_picker` 的地方（保存另存为见 `image_save.dart`）。
/// 插件没有当前平台实现（如部分鸿蒙版本）时返回 null 并关闭
/// [AppCapability.filePicker]，由调用方按“用户取消”处理。
abstract final class FilePick {
  FilePick._();

  static Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withReadStream = false,
    bool withData = false,
    bool allowCompression = true,
  }) async {
    if (!AppCapabilities.isAvailable(AppCapability.filePicker)) return null;
    try {
      return await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: allowMultiple,
        withReadStream: withReadStream,
        withData: withData,
        allowCompression: allowCompression,
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
      // 插件参数错误 / 系统拒绝 / 选择器异常：按“用户取消”返回，避免把
      // PlatformException 冒到 UI 变成未捕获异常
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

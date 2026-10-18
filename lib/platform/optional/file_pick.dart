import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_capabilities.dart';
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
    }
  }
}

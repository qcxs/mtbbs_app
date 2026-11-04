import 'package:flutter/services.dart';

import 'package:mtbbs/core/utils/logger.dart';

/// 剪切板工具类
///
/// 封装 Flutter 的 Clipboard 操作，提供类型安全的读写方法。
class ClipboardHelper {
  ClipboardHelper._();

  /// 将文本写入系统剪切板。
  ///
  /// 返回 `true` 表示写入成功；平台权限受限 / 剪贴板被占用等失败只记日志并
  /// 返回 `false`，**不抛异常**。调用方必须据此提示，不能无条件显示“已复制”
  /// （见 docs/07 #107）。
  static Future<bool> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      AppLogger.w('PAGE', '写入剪切板失败：$e');
      return false;
    }
  }

  /// 从系统剪切板读取文本
  ///
  /// 返回 null 表示剪切板为空或无法读取（平台无实现 / 权限受限等）。
  /// 读取失败不抛出：调用方只需处理「拿到内容 / 没拿到」，降级入口（手动输入）
  /// 由调用方提供，避免异常直接冒泡成未捕获错误。
  static Future<String?> read() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    } catch (e) {
      AppLogger.w('PAGE', '读取剪切板失败：$e');
      return null;
    }
  }
}

import 'package:flutter/services.dart';

/// 剪切板工具类
///
/// 封装 Flutter 的 Clipboard 操作，提供类型安全的读写方法。
class ClipboardHelper {
  ClipboardHelper._();

  /// 将文本写入系统剪切板
  static Future<void> write(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }

  /// 从系统剪切板读取文本
  ///
  /// 返回 null 表示剪切板为空或无法读取。
  static Future<String?> read() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}

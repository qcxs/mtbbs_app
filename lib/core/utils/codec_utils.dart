import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// 常用编解码 / 哈希工具（纯函数，不依赖 UI）。
///
/// 用于「编解码工具」页（`lib/pages/tools/codec_page.dart`）：52pojie 等
/// 技术论坛的帖子常把下载/资源链接做 Base64 或 URL 编码，粘贴还原后可直接打开。
class CodecUtils {
  CodecUtils._();

  /// Base64 编码（UTF-8 → 标准字母表，含 `=` 填充）。
  static String base64Encode(String text) => base64.encode(utf8.encode(text));

  /// Base64 解码，容忍论坛复制出来的常见脏格式：
  ///
  /// - 换行/空格（帖子自动折行、复制带缩进）
  /// - URL-safe 字母表（`-` / `_`）
  /// - 缺少 `=` 尾填充
  ///
  /// 解码结果按 UTF-8 解释；格式错误或非文本内容抛 [FormatException]。
  static String base64Decode(String text) {
    var s = text.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return '';
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = s.length % 4;
    if (remainder == 1) {
      throw const FormatException('Base64 长度不合法');
    }
    if (remainder != 0) {
      s = s.padRight(s.length + (4 - remainder), '=');
    }
    return utf8.decode(base64.decode(s));
  }

  /// URL 编码（percent-encoding，空格编码为 `%20`）。
  static String urlEncode(String text) => Uri.encodeComponent(text);

  /// URL 解码，容忍表单编码里的 `+`（按空格处理）。
  static String urlDecode(String text) =>
      Uri.decodeComponent(text.replaceAll('+', ' '));

  /// 十六进制编码（UTF-8 字节 → 小写 hex，无分隔）。
  static String hexEncode(String text) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(text)) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// 十六进制解码，容忍空格/换行与 `0x` 前缀。
  ///
  /// 长度为奇数或含非 hex 字符时抛 [FormatException]。
  static String hexDecode(String text) {
    var s = text.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return '';
    if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
    if (s.length.isOdd) throw const FormatException('十六进制长度必须为偶数');
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(s)) {
      throw const FormatException('包含非十六进制字符');
    }
    final bytes = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      bytes.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return utf8.decode(bytes);
  }

  /// MD5 摘要（UTF-8 输入，小写 hex）。
  static String md5(String text) => _digest(crypto.md5, text);

  /// SHA-1 摘要（UTF-8 输入，小写 hex）。
  static String sha1(String text) => _digest(crypto.sha1, text);

  /// SHA-256 摘要（UTF-8 输入，小写 hex）。
  static String sha256(String text) => _digest(crypto.sha256, text);

  static String _digest(crypto.Hash hash, String text) =>
      hash.convert(utf8.encode(text)).toString();
}

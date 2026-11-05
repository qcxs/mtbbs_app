import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/utils/codec_utils.dart';

/// CodecUtils：编解码工具页的纯逻辑回归（哈希用公开测试向量）。
void main() {
  group('Base64', () {
    test('编码 / 解码往返', () {
      expect(CodecUtils.base64Encode('hello'), 'aGVsbG8=');
      expect(CodecUtils.base64Decode('aGVsbG8='), 'hello');
      expect(CodecUtils.base64Encode('中文'), '5Lit5paH');
      expect(CodecUtils.base64Decode('5Lit5paH'), '中文');
    });

    test('容忍折行、缺失填充与 URL-safe 字母表', () {
      // 帖子复制时常带换行/空格
      expect(CodecUtils.base64Decode('aGVs\nbG8='), 'hello');
      expect(CodecUtils.base64Decode(' aGVs bG8 '), 'hello');
      // 缺省 '=' 填充
      expect(CodecUtils.base64Decode('aGVsbG8'), 'hello');
      // URL-safe 字母表：'-'/'_' 还原为 '+'/'/'
      for (final raw in ['???', '~~~']) {
        final standard = CodecUtils.base64Encode(raw);
        // 两个样本必须分别覆盖 '+' 与 '/'
        expect(standard, contains(RegExp(r'[+/]')));
        final urlSafe = standard.replaceAll('+', '-').replaceAll('/', '_');
        expect(CodecUtils.base64Decode(urlSafe), raw);
      }
    });

    test('非法输入抛 FormatException', () {
      // 长度余 1，无法补齐
      expect(() => CodecUtils.base64Decode('a'), throwsFormatException);
      // 非 UTF-8 二进制（0xFF）
      expect(
        () => CodecUtils.base64Decode(base64.encode([0xFF])),
        throwsFormatException,
      );
    });
  });

  group('URL', () {
    test('编码 / 解码往返（空格编码为 %20）', () {
      const raw = 'a b&c=中文/路径';
      expect(
        CodecUtils.urlEncode(raw),
        'a%20b%26c%3D%E4%B8%AD%E6%96%87%2F%E8%B7%AF%E5%BE%84',
      );
      expect(CodecUtils.urlDecode(CodecUtils.urlEncode(raw)), raw);
    });

    test('解码时 + 视为空格', () {
      expect(CodecUtils.urlDecode('a+b'), 'a b');
      expect(CodecUtils.urlDecode('a%2Bb'), 'a+b');
    });

    test('非法百分号编码抛异常', () {
      expect(() => CodecUtils.urlDecode('%zz'), throwsA(isA<Object>()));
    });
  });

  group('十六进制', () {
    test('编码 / 解码往返', () {
      expect(CodecUtils.hexEncode('中文'), 'e4b8ade69687');
      expect(CodecUtils.hexDecode('e4b8ade69687'), '中文');
    });

    test('容忍空格/换行与 0x 前缀', () {
      expect(CodecUtils.hexDecode('E4 B8 AD E6 96 87'), '中文');
      expect(CodecUtils.hexDecode('0xE4B8ADE69687'), '中文');
    });

    test('非法输入抛 FormatException', () {
      expect(() => CodecUtils.hexDecode('abc'), throwsFormatException);
      expect(() => CodecUtils.hexDecode('zz'), throwsFormatException);
    });
  });

  group('哈希', () {
    test('MD5 公开向量', () {
      expect(CodecUtils.md5('abc'), '900150983cd24fb0d6963f7d28e17f72');
      expect(CodecUtils.md5(''), 'd41d8cd98f00b204e9800998ecf8427e');
    });

    test('SHA-1 公开向量', () {
      expect(CodecUtils.sha1('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
    });

    test('SHA-256 公开向量', () {
      expect(
        CodecUtils.sha256('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
}

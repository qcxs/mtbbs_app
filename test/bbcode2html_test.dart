import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/bbcode2html.dart';

void main() {
  group('BBCode2Html - 表格渲染', () {
    test('表格 td 内 align 被提取到 td 样式', () {
      const bbcode =
          '[table][tr][td][align=center][b]网盘名称[/b][/align][/td][/tr][/table]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      // td 自身携带 text-align:center，不再有 <div align="center"> 包裹
      expect(html, contains('text-align:center'));
      expect(html, isNot(contains('<div align="center"')));
      expect(html, contains('<strong>网盘名称</strong>'));
    });

    test('表格 td 内无 align 时保持原样', () {
      const bbcode = '[table][tr][td]普通内容[/td][/tr][/table]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      expect(html, contains('普通内容'));
      expect(html, isNot(contains('text-align')));
    });

    test('表格 td 内链接保持原样', () {
      const bbcode =
          '[table][tr][td][url=https://example.com]示例[/url][/td][/tr][/table]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      expect(html, contains('<a href="https://example.com'));
      expect(html, contains('</a>'));
    });

    test('多行多列表格完整渲染', () {
      const bbcode = ''
          '[table]'
          '[tr]'
          '[td][align=center][b]名称[/b][/align][/td]'
          '[td][align=center][b]网址[/b][/align][/td]'
          '[/tr]'
          '[tr]'
          '[td][align=center]小飞机[/align][/td]'
          '[td][url=https://www.feejii.com/]feejii.com[/url][/td]'
          '[/tr]'
          '[/table]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      // 表头：text-align 在 td 上
      expect(html, contains('<td style='));
      // 两个 td 应有 text-align:center
      expect(html, contains('text-align:center'));
      // 链接正常
      expect(html, contains('<a href="https://www.feejii.com/'));
      // 不应有 div align 包裹
      expect(html, isNot(contains('<div align=')));
    });
  });
}

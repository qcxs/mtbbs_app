import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

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
      // 表头：text-align 由 [align] 转为内层 div，td 本身只承载结构
      expect(html, contains('<td>'));
      // 两个 td 内都应有 text-align:center
      expect(html, contains('text-align:center'));
      // 链接正常
      expect(html, contains('<a href="https://www.feejii.com/'));
      // 不应有 div align 包裹
      expect(html, isNot(contains('<div align=')));
    });
  });

  group('stripDisabledBbcodeTags（渲染层与 MCP 精简输出共用）', () {
    test('删除样式标签标记但保留内容', () {
      const bbcode = '[b]加粗[/b][color=red]红字[/color][size=5]大字[/size]';
      expect(
        stripDisabledBbcodeTags(bbcode, bbcodeStyleTagIds.toSet()),
        '加粗红字大字',
      );
    });

    test('带值与闭合标记都删（[tag=xxx] / [/tag]）', () {
      const bbcode = '[align=center]居中[/align][font=微软雅黑]字体[/font]';
      expect(
        stripDisabledBbcodeTags(bbcode, bbcodeStyleTagIds.toSet()),
        '居中字体',
      );
    });

    test('删除线带语义：不在清单内，因此被保留', () {
      expect(bbcodeStyleTagIds, isNot(contains('strikethrough')));
      expect(
        stripDisabledBbcodeTags('[s]作废[/s]', bbcodeStyleTagIds.toSet()),
        '[s]作废[/s]',
      );
    });

    test('禁用 backcolor 时连带删除同义的 background', () {
      const bbcode = '[backcolor=yellow]黄底[/backcolor][background=pink]粉底[/background]';
      expect(stripDisabledBbcodeTags(bbcode, {'backcolor'}), '黄底粉底');
    });

    test('非样式标签（quote/code/url/img）不受影响', () {
      const bbcode = '[quote]引用[/quote][code]var a=1;[/code][url=x]链接[/url][img]a.png[/img]';
      expect(stripDisabledBbcodeTags(bbcode, bbcodeStyleTagIds.toSet()), bbcode);
    });
  });
}

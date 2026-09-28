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
      const bbcode =
          ''
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
      const bbcode =
          '[backcolor=yellow]黄底[/backcolor][background=pink]粉底[/background]';
      expect(stripDisabledBbcodeTags(bbcode, {'backcolor'}), '黄底粉底');
    });

    test('非样式标签（quote/code/url/img）不受影响', () {
      const bbcode =
          '[quote]引用[/quote][code]var a=1;[/code][url=x]链接[/url][img]a.png[/img]';
      expect(
        stripDisabledBbcodeTags(bbcode, bbcodeStyleTagIds.toSet()),
        bbcode,
      );
    });
  });

  group('BBCode2Html - 正文图片标记（渲染层按帖/楼组画廊）', () {
    test('[img] 按文档顺序收集 URL 并写入 data-img-index', () {
      const bbcode =
          '[img]https://a.com/1.png[/img]中间文字[img]https://a.com/2.png[/img]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      expect(
        html,
        contains('<img data-img-index="0" src="https://a.com/1.png"'),
      );
      expect(
        html,
        contains('<img data-img-index="1" src="https://a.com/2.png"'),
      );
      expect(converter.imageUrls, [
        'https://a.com/1.png',
        'https://a.com/2.png',
      ]);
    });

    test('带参地址还原实体：imageUrls 与渲染层 src 逐字一致（防画廊全黑）', () {
      // 编辑器里已有的图片就是这种带 & 的 Discuz 附件地址
      const bbcode =
          '[img]https://bbs.example.com/forum.php?mod=image&aid=1&key=ab[/img]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      // HTML 属性里必须转义（渲染器解析时会解码回 &）
      expect(html, contains('&amp;aid=1&amp;key=ab'));
      // 交给画廊的必须是未转义的真实 URL，否则请求 404 → 全黑
      expect(converter.imageUrls, [
        'https://bbs.example.com/forum.php?mod=image&aid=1&key=ab',
      ]);
    });

    test('appdata 图片附件（编辑器预览同款链路）也计入画廊且已还原', () {
      const bbcode =
          '[appdata]{"type":"image_attach","url":"forum.php?mod=image&aid=7","aid":"7"}[/appdata]';
      final converter = BBCode2Html(baseUrl: 'https://bbs.example.com');
      converter.convert(bbcode);
      expect(converter.imageUrls, [
        'https://bbs.example.com/forum.php?mod=image&aid=7',
      ]);
    });

    test('顺序按文档而非按发射点：[img] 在前、appdata 附件在后', () {
      const bbcode =
          '[img]https://a.com/1.png[/img]中间[appdata]{"type":"image_attach","url":"https://a.com/2.png","aid":"2"}[/appdata]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      // appdata 在步骤 0 就被渲染（早于 [img]），若按发射顺序收集会颠倒
      expect(converter.imageUrls, [
        'https://a.com/1.png',
        'https://a.com/2.png',
      ]);
      expect(
        html.indexOf('data-img-index="0"'),
        lessThan(html.indexOf('data-img-index="1"')),
      );
    });

    test('表情不计入画廊；code 里的图片文本不算正文图片', () {
      final converter = BBCode2Html(emojiMap: {'[呵呵]': 'https://x/e.gif'});
      final html = converter.convert(
        '[img]https://a.com/1.png[/img][呵呵][code]<img src="x.png">[/code]',
      );
      expect(html, contains('data-type="emoji"'));
      expect(converter.imageUrls, ['https://a.com/1.png']);
    });
  });
}

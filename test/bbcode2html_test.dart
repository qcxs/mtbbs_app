import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

void main() {
  group('BBCode2Html - 数学公式', () {
    test('块级 math appdata → div 占位 + mathBlocks 记录原文', () {
      final converter = BBCode2Html();
      final html = converter.convert(
        r'[appdata]{"type":"math","tex":"\\frac{a}{b}","display":true}[/appdata]',
      );
      expect(html, contains('<div class="bbcode-math" data-math-index="0"'));
      expect(converter.mathBlocks.length, 1);
      expect(converter.mathBlocks.first.tex, r'\frac{a}{b}');
      expect(converter.mathBlocks.first.display, isTrue);
    });

    test('行内 math appdata → span 占位，保留在段落内', () {
      final converter = BBCode2Html();
      final html = converter.convert(
        r'点在 [appdata]{"type":"math","tex":"$x_{0}$","display":false}[/appdata] 处',
      );
      expect(html, contains('<span class="bbcode-math" data-math-index="0"'));
      expect(html, contains('点在 <span'));
      expect(html, contains('</span> 处'));
      expect(converter.mathBlocks.first.display, isFalse);
    });

    test('tex 为空时不生成占位元素', () {
      final converter = BBCode2Html();
      converter.convert('[appdata]{"type":"math","tex":""}[/appdata]');
      expect(converter.mathBlocks, isEmpty);
    });
  });

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

  group('BBCode2Html - 正文相对链接', () {
    test('[url=forum.php?...] 按注入的所属站点补全', () {
      final converter = BBCode2Html(baseUrl: 'https://b.example.com');
      final html = converter.convert(
        '[url=forum.php?mod=viewthread&tid=1]链接[/url]',
      );
      expect(
        html,
        contains(
          'href="https://b.example.com/forum.php?mod=viewthread&amp;tid=1"',
        ),
      );
    });

    test('绝对地址与 App 内路径不补站点前缀', () {
      final converter = BBCode2Html(baseUrl: 'https://b.example.com');
      expect(
        converter.convert('[url=https://a.example.com/x]绝对[/url]'),
        contains('href="https://a.example.com/x"'),
      );
      expect(
        converter.convert('[url=/thread/1]App[/url]'),
        contains('href="/thread/1"'),
      );
    });
  });

  group('BBCode2Html - 背景色标签', () {
    test('[backcolor] 转成 background-color 样式', () {
      final html = BBCode2Html().convert('[backcolor=red]背景[/backcolor]');
      expect(html, contains('background-color:red'));
    });

    test('[background] 不是合法标签，按纯文本原样保留', () {
      const bbcode = '[background=red]文字[/background]';
      final html = BBCode2Html().convert(bbcode);
      expect(html, contains(bbcode));
      expect(html, isNot(contains('background-color')));
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

    test('禁用 backcolor 只删除 backcolor 标记，background 纯文本不受影响', () {
      const bbcode =
          '[backcolor=yellow]黄底[/backcolor][background=pink]粉底[/background]';
      expect(
        stripDisabledBbcodeTags(bbcode, {'backcolor'}),
        '黄底[background=pink]粉底[/background]',
      );
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
      // appdata 在步骤 1 就被渲染（早于 [img]），若按发射顺序收集会颠倒
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

  group('BBCode2Html - 重复 convert 不累积', () {
    test('[code] 里的 [img] 不算正文图片', () {
      final c = BBCode2Html();
      c.convert('[code][img]https://a.com/x.png[/img][/code]\n后面');
      expect(c.imageUrls, isEmpty);
    });

    test('重复 convert 时输出列表被清空', () {
      final c = BBCode2Html();
      c.convert('[img]https://a.com/1.png[/img]');
      expect(c.imageUrls, ['https://a.com/1.png']);
      c.convert('纯文本');
      expect(c.imageUrls, isEmpty);
      expect(c.codeBlocks, isEmpty);
    });
  });

  group('BBCode2Html - [code] 内的 [appdata] 按原文展示', () {
    const appdata = '[appdata]{"type":"locked","message":"回复可见"}[/appdata]';

    test('存进 codeBlocks 的是原文，不解析成组件、不残留内部占位符', () {
      final converter = BBCode2Html(emitCodePlaceholder: true);
      final html = converter.convert('[code]$appdata[/code]');
      expect(converter.codeBlocks, hasLength(1));
      expect(converter.codeBlocks.single, appdata);
      expect(html, contains('data-code-index="0"'));
      // 内部占位符（\x00APPDATA* / \x00CODE*）绝不能外泄到 HTML
      expect(html.contains('\x00'), isFalse);
    });

    test('非占位元素模式：直接输出转义后的原文，不渲染成组件', () {
      final converter = BBCode2Html();
      final html = converter.convert('[code]$appdata[/code]');
      expect(html, contains('&quot;type&quot;:&quot;locked&quot;'));
      expect(html, isNot(contains('bbcode-locked')));
    });

    test('code 外的 [appdata] 仍正常解析（顺序调整不影响原有行为）', () {
      final converter = BBCode2Html();
      final html = converter.convert('$appdata\n[code]$appdata[/code]');
      // 代码外那一份渲染成组件
      expect(html, contains('bbcode-locked'));
      // 代码内那一份仍是原文
      expect(converter.codeBlocks.single, appdata);
    });
  });

  group('BBCode2Html - [md] 块（52pojie Markdown）', () {
    test('Markdown 转 HTML：标题 / 列表 / 表格 / 代码 / 图片', () {
      final converter = BBCode2Html(
        baseUrl: 'https://www.52pojie.cn',
        emitCodePlaceholder: true,
        supportsMd: true,
      );
      final html = converter.convert(
        '[md]# 标题\n\n- 甲\n- 乙\n\n'
        '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n'
        '```dart\nfinal a = 1;\n```\n\n'
        '![图](https://attach.52pojie.cn/a.jpg)[/md]',
      );
      expect(html, contains('<h1>标题</h1>'));
      expect(html, contains('<li>'));
      expect(html, contains('<table>'));
      expect(html, contains('data-code-index="0"'));
      expect(html, contains('data-img-index="0"'));
      expect(converter.codeBlocks.single.trim(), 'final a = 1;');
      expect(converter.imageUrls, hasLength(1));
      expect(html, isNot(contains('[md]')));
      expect(html.contains('\x00'), isFalse);
    });

    test('[md] 内的 [appdata] 公式不受 Markdown 解析影响', () {
      final converter = BBCode2Html(supportsMd: true);
      final html = converter.convert(
        '[md]行内公式 [appdata]{"type":"math","tex":"x^2","display":false}[/appdata] 结束[/md]',
      );
      expect(html, contains('bbcode-math'));
      expect(converter.mathBlocks.single.tex, 'x^2');
      expect(html, isNot(contains('[appdata]')));
      expect(html.contains('\x00'), isFalse);
    });

    test('非 52 站点（默认 supportsMd=false）不解析 Markdown，标签原样可见', () {
      final converter = BBCode2Html();
      final html = converter.convert('[md]# 标题\n\n- 甲\n- 乙[/md]');
      expect(html, isNot(contains('<h1>')));
      expect(html, isNot(contains('<li>')));
      // 标签不能消失：用户要知道这里原本有 [md] 包裹
      expect(html, contains('[md]'));
      expect(html, contains('[/md]'));
      expect(html, contains('# 标题'));
      expect(html, contains('- 甲'));
    });
  });
}

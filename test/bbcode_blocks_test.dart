import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode_blocks.dart';

/// BBCode 顶层分块器测试。
///
/// 重点守住一条不变量：**分块无损** —— `join(raw) == 原文`。
/// 这条不变量是「分块可视化」方案成立的前提：它保证块模型只是"切分视图"，
/// 提交给 Discuz 的内容与用户原文逐字节相同，`[attachimg]aid[/attachimg]`
/// 这类只在编辑器会话内有效的构造不会在往返中丢失。
void main() {
  /// 分块必须无损、且偏移自洽
  void expectLossless(String input) {
    final blocks = splitBbcodeBlocks(input);
    expect(
      blocks.map((b) => b.raw).join(),
      input,
      reason: '分块必须无损: ${escaped(input)}',
    );
    for (final b in blocks) {
      expect(
        input.substring(b.start, b.end),
        b.raw,
        reason: '偏移与切片必须自洽: ${escaped(input)}',
      );
    }
  }

  group('无损不变量（含畸形输入）', () {
    const cases = <String>[
      // 基本形态
      '',
      '纯文本',
      '第一行\n第二行',
      '[b]加粗[/b]与[i]斜体[/i]',
      // 顶层块
      '[quote]引用[/quote]',
      '前文\n[quote]引用[/quote]\n后文',
      '[quote]甲[/quote][quote]乙[/quote]',
      '[quote=作者;pid:123]带参数引用[/quote]',
      '[hide=100]回复可见[/hide]',
      '[free]免费内容[/free]',
      '[align=center]居中[/align]',
      '[list][*]甲[*]乙[/list]',
      '[list=1][*]甲[*]乙[/list]',
      '[list=a][*]甲[/list]',
      '[table][tr][td]格[/td][/tr][/table]',
      '[code]print("hi")[/code]',
      '[hr]',
      '上文[hr]下文',
      '[img]https://a.com/x.png[/img]',
      '文字[attachimg]123[/attachimg]文字',
      '[audio]https://a.com/x.mp3[/audio]',
      // appdata：解析层产出的正文里是常态（编辑记录 / 图片附件 / 文件附件 / 隐藏提示）
      '[appdata]{"type":"pstatus","message":"本帖最后由 X 编辑"}[/appdata]',
      '[appdata]{"type":"image_attach","url":"https://a.com/x.png"}[/appdata]后文',
      '[appdata]{"type":"attach","name":"a.zip","url":"https://a.com/a.zip"}[/appdata]',
      // appdata 的 JSON 里出现方括号 / 块级标签也不能影响边界
      '[appdata]{"type":"pstatus","message":"看[这里]"}[/appdata]',
      '[appdata]{"type":"pstatus","message":"[quote]x[/quote]"}[/appdata]',
      '[appdata]{"type":"pstatus","message":"[quote]未闭合"}[/appdata]',
      // 嵌套：内层块级标签不应单独成块
      '[quote][list=1][*]甲[/list][/quote]',
      '[quote][quote]内层[/quote][/quote]',
      '[quote][code][b]原样[/b][/code][/quote]',
      // 内联容器包裹块级原子：必须整段成块，不能被撕开
      '[url=https://a.com][img]https://a.com/x.png[/img][/url]',
      '前文[url=https://a.com][img]https://a.com/x.png[/img][/url]后文',
      '[url=https://a.com][attachimg]123[/attachimg][/url]',
      '[b][img]https://a.com/x.png[/img][/b]',
      '[color=red][img]https://a.com/x.png[/img][/color]',
      '[url=https://a.com][b][img]https://a.com/x.png[/img][/b][/url]',
      '[url=https://a.com][img]https://a.com/x.png[/img]正文[/url]',
      // 大小写不敏感
      '[QUOTE]大写[/QUOTE]',
      // code 内容原样：内部的块级标记不参与分块
      '[code][quote]不是引用[/quote][/code]',
      '[code][list][/code]',
      '[code][/list][/code]',
      '[code][code][/code]',
      // 畸形：未闭合 → 降级为文本
      '[quote]没有闭合',
      '[quote]未闭合[list]也没闭合',
      '[code]未闭合的代码',
      '[list=1][*]甲',
      '[table][tr][td]格',
      // 畸形：孤立闭标签 → 忽略
      '[/quote]',
      '前文[/quote]后文',
      '[/list][/table][/code]',
      // 畸形：裸方括号 / 空标签 / 非标签
      '[',
      '[[[[',
      '[]',
      '[ ]',
      '[=]',
      '文本[未闭合',
      'a[nonsense]b',
      // 混合真实形态
      '[color=#ff00]红字[/color]\n[attachimg]456[/attachimg]\n'
          '[quote]引用一段[/quote]\n[list=1][*]甲[*]乙[/list]\n'
          '[code]if (a > b) { return; }[/code]\n结尾',
    ];

    for (final input in cases) {
      test('无损: ${escaped(input)}', () => expectLossless(input));
    }
  });

  group('块切分', () {
    test('空串 → 空列表', () {
      expect(splitBbcodeBlocks(''), isEmpty);
    });

    test('纯文本 → 单个文本块', () {
      final blocks = splitBbcodeBlocks('纯文本');
      expect(blocks, hasLength(1));
      expect(blocks.single.isText, isTrue);
      expect(blocks.single.kind, BbBlockKind.text);
    });

    test('行内标签不产生块边界', () {
      final blocks = splitBbcodeBlocks('[b]加粗[/b][color=red]红[/color]');
      expect(blocks, hasLength(1));
      expect(blocks.single.isText, isTrue);
    });

    test('顶层容器切出 文本 / 块 / 文本', () {
      final blocks = splitBbcodeBlocks('前文[quote]引用[/quote]后文');
      expect(blocks.map((b) => b.tag), ['', 'quote', '']);
      expect(blocks[1].kind, BbBlockKind.quote);
      expect(blocks[1].raw, '[quote]引用[/quote]');
      expect(blocks[1].body, '[quote]引用[/quote]');
    });

    test('相邻块级标签切出两个块', () {
      final blocks = splitBbcodeBlocks('[quote]甲[/quote][code]乙[/code]');
      expect(blocks.map((b) => b.tag), ['quote', 'code']);
      expect(blocks.map((b) => b.kind), [BbBlockKind.quote, BbBlockKind.code]);
    });

    test('识别 [list=1]（outerBlocks 只认裸标签，这里必须支持带参数）', () {
      final blocks = splitBbcodeBlocks('[list=1][*]甲[/list]');
      expect(blocks, hasLength(1));
      expect(blocks.single.tag, 'list');
      expect(blocks.single.kind, BbBlockKind.list);
    });

    test('嵌套的块级标签只算最外层一个块', () {
      final blocks = splitBbcodeBlocks('[quote][list=1][*]甲[/list][/quote]');
      expect(blocks, hasLength(1));
      expect(blocks.single.tag, 'quote');
    });

    test('[hr] 自成一块，且与前后文本分离', () {
      final blocks = splitBbcodeBlocks('上文[hr]下文');
      expect(blocks.map((b) => b.tag), ['', 'hr', '']);
      expect(blocks[1].kind, BbBlockKind.hr);
      expect(blocks[1].raw, '[hr]');
    });

    test('图片块：img / attachimg 归为 image', () {
      final blocks = splitBbcodeBlocks(
        '文字[img]https://a.com/x.png[/img]文字[attachimg]123[/attachimg]',
      );
      expect(blocks.map((b) => b.kind), [
        BbBlockKind.text,
        BbBlockKind.image,
        BbBlockKind.text,
        BbBlockKind.image,
      ]);
    });

    test('标签名大小写不敏感', () {
      final blocks = splitBbcodeBlocks('[QUOTE]大写[/Quote]');
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, BbBlockKind.quote);
    });

    test('appdata 自成一块（解析层产出的正文里是常态）', () {
      final blocks = splitBbcodeBlocks(
        '[appdata]{"type":"pstatus","message":"编辑记录"}[/appdata]正文',
      );
      expect(blocks.map((b) => b.tag), ['appdata', '']);
      expect(blocks.first.kind, BbBlockKind.data);
      expect(
        blocks.first.raw,
        '[appdata]{"type":"pstatus","message":"编辑记录"}[/appdata]',
      );
    });

    test('appdata 的 JSON 里含块级标签时边界仍正确', () {
      final blocks = splitBbcodeBlocks(
        '[appdata]{"message":"[quote]x[/quote]"}[/appdata]后文',
      );
      expect(blocks.map((b) => b.tag), ['appdata', '']);
      expect(blocks.first.raw.endsWith('[/appdata]'), isTrue);
    });
  });

  group('内联容器不被撕开', () {
    test('[url][img][/img][/url] 整段成一个图片块', () {
      const src = '[url=https://a.com][img]https://a.com/x.png[/img][/url]';
      final blocks = splitBbcodeBlocks(src);
      expect(blocks, hasLength(1));
      expect(blocks.single.raw, src, reason: '不得拆出孤立的 [url=…] 或 [/url]');
      expect(blocks.single.kind, BbBlockKind.image);
    });

    test('前后有文本时切出 文本 / 图片 / 文本', () {
      final blocks = splitBbcodeBlocks(
        '前文[url=https://a.com][img]https://a.com/x.png[/img][/url]后文',
      );
      expect(blocks.map((b) => b.kind), [
        BbBlockKind.text,
        BbBlockKind.image,
        BbBlockKind.text,
      ]);
      expect(blocks[1].raw.startsWith('[url='), isTrue);
      expect(blocks[1].raw.endsWith('[/url]'), isTrue);
    });

    test('多层行内包裹时块起点回退到最外层', () {
      const src =
          '[url=https://a.com][b][img]https://a.com/x.png[/img][/b][/url]';
      final blocks = splitBbcodeBlocks(src);
      expect(blocks, hasLength(1));
      expect(blocks.single.raw, src);
    });

    test('行内包裹内还有正文时也整段成块', () {
      const src = '[url=https://a.com][img]https://a.com/x.png[/img]正文[/url]';
      final blocks = splitBbcodeBlocks(src);
      expect(blocks, hasLength(1));
      expect(blocks.single.raw, src);
    });

    test('未闭合的行内标签只降级，不影响无损性', () {
      final blocks = splitBbcodeBlocks(
        '[color=red]半截颜色[img]https://a.com/x.png[/img]',
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.isText, isTrue, reason: '行内标签未闭合 → 无法确定块边界，整段降级');
    });

    test('行内标签成对闭合后，后续块级标签仍正常切块', () {
      final blocks = splitBbcodeBlocks(
        '[color=red]红[/color][img]https://a.com/x.png[/img]',
      );
      expect(blocks.map((b) => b.kind), [BbBlockKind.text, BbBlockKind.image]);
    });
  });

  group('code 内容原样', () {
    test('code 内的块级标记不切块', () {
      final blocks = splitBbcodeBlocks('[code][quote]不是引用[/quote][/code]');
      expect(blocks, hasLength(1));
      expect(blocks.single.tag, 'code');
    });

    test('code 内未配对的块级标签不影响 code 边界', () {
      final blocks = splitBbcodeBlocks('[code][list][/code]后文');
      expect(blocks.map((b) => b.tag), ['code', '']);
      expect(blocks.first.raw, '[code][list][/code]');
    });

    test('code 内出现闭合标签时不会把外层 code 提前截断', () {
      final blocks = splitBbcodeBlocks('[code][/list][/code]后文');
      expect(blocks.map((b) => b.tag), ['code', '']);
      expect(blocks.first.raw, '[code][/list][/code]');
    });
  });

  group('畸形输入降级', () {
    test('未闭合容器不产出块，整段为文本', () {
      final blocks = splitBbcodeBlocks('[quote]没有闭合');
      expect(blocks, hasLength(1));
      expect(blocks.single.isText, isTrue);
    });

    test('未闭合容器不吞掉后续已闭合的块', () {
      // [quote] 未闭合 → 后续 [code] 也被并入同一段文本（栈未归零）
      final blocks = splitBbcodeBlocks('[quote]未闭合[code]代码[/code]');
      expect(blocks, hasLength(1));
      expect(blocks.single.isText, isTrue);
    });

    test('孤立闭标签被忽略', () {
      final blocks = splitBbcodeBlocks('前文[/quote]后文');
      expect(blocks, hasLength(1));
      expect(blocks.single.raw, '前文[/quote]后文');
    });

    test('裸方括号不抛异常', () {
      expect(() => splitBbcodeBlocks('[[[[[('), returnsNormally);
      expect(splitBbcodeBlocks('[[[['), hasLength(1));
    });
  });

  group('块间空白', () {
    test('块级标签之间的空行成为 body 为空的文本段', () {
      final blocks = splitBbcodeBlocks('[quote]甲[/quote]\n\n[quote]乙[/quote]');
      expect(blocks.map((b) => b.tag), ['quote', '', 'quote']);
      final gap = blocks[1];
      expect(gap.isText, isTrue);
      expect(gap.raw, '\n\n');
      expect(gap.body, isEmpty, reason: '纯空白段渲染时应被跳过');
    });

    test('文本块 body 去掉首尾空白，块级标签块 body 保持原样', () {
      final blocks = splitBbcodeBlocks('  \n[quote]甲[/quote]  \n');
      expect(blocks.first.body, isEmpty);
      expect(blocks[1].body, '[quote]甲[/quote]');
      expect(blocks.last.body, isEmpty);
    });
  });
}

/// 让失败信息里能看到原始输入（含换行），便于定位
String escaped(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll('\r', '\\r');

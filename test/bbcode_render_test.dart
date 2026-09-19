import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// ============================================================
/// BBCode 渲染回归测试套件（flutter_widget_from_html 版）
///
/// 覆盖迁移前 flutter_html 方案的各类失效模式：
///   ① 行内 / 块级语义共存（表情内联 vs 帖子图片块级）
///   ② 链接内图片点击冒泡（点击图片应触发 [url] 的点击）
///   ③ 表格 + 代码块注入，内容不丢失
///   ④ 极端嵌套（quote > hide > table > td > list/code）容器不被拆散
///   ⑤ 空行回归
///   ⑥ 颜色容错
///   ⑦ SelectionArea 兼容
///   ⑧ 性能量级
///   ⑨ 附件卡片不溢出
///   ⑩ 转换层遗留缺陷（与渲染器无关，换渲染器不会自动消失）
///   ⑪ 列表（无 ul/li，转换层展开为带前缀段落）
///   ⑫ 正文字号接线（跟随设置项 / 显式覆盖 / 代码块联动）
///
/// 两条测试约定（迁移时必须知道）：
/// 1. flutter_widget_from_html 的文本由 **RichText** 承载（不是 Text widget），
///    文本查找必须 `findRichText: true`，否则会误报 0 个匹配；
/// 2. 图片占位用 CircularProgressIndicator（无限动画），测试环境无法真正下载
///    图片，`pumpAndSettle` 永不收敛，故统一用固定帧 [_settle]。
/// ============================================================

Finder _text(String s) => find.textContaining(s, findRichText: true);

/// 固定帧推进（替代 pumpAndSettle，见文件头约定 2）
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// 取「包含指定文本的 RichText」的全局矩形，用于行内/块级判定
Rect? _rectOfText(String s) {
  for (final el in find.byType(RichText).evaluate()) {
    final rich = el.widget as RichText;
    final ro = el.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    if (!rich.text.toPlainText().contains(s)) continue;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }
  return null;
}

Widget _wrap(Widget child, {SettingsProvider? settings}) => MaterialApp(
  home: Scaffold(
    body: ChangeNotifierProvider.value(
      value: settings ?? SettingsProvider(),
      child: SingleChildScrollView(child: child),
    ),
  ),
);

/// 固定字号的 SettingsProvider —— 只覆盖 getter，避免测试触发数据库写入
class _FixedFontSettings extends SettingsProvider {
  @override
  double get fontSize => 24;
}

/// 取「包含指定文本的 RichText」的字号
double? _fontSizeOf(String s) {
  for (final el in find.byType(RichText).evaluate()) {
    final rich = el.widget as RichText;
    if (rich.text.toPlainText().contains(s)) {
      return rich.text.style?.fontSize;
    }
  }
  return null;
}

Widget _post(String bbcode, {double fontSize = 16}) =>
    _wrap(PostHtmlWidget(bbcode: bbcode, fontSize: fontSize));

/// 渲染树诊断（沿用 docs/07 第 15 条的三层 dump 方法）
void _dumpRichText(String label) {
  // ignore: avoid_print
  print('    ┌─ $label');
  for (final el in find.byType(RichText).evaluate()) {
    final rich = el.widget as RichText;
    final ro = el.renderObject as RenderParagraph?;
    // ignore: avoid_print
    print('    │  ${ro?.size}  "${rich.text.toPlainText()}"');
  }
}

void main() {
  setUp(() {
    // PostHtmlWidget 依赖 SiteStore 当前站点（baseUrl）
    SiteStore.instance.init();
  });

  group('① 行内 / 块级语义共存', () {
    testWidgets('帖子图片为块级：独占一行且占满可用宽度', (tester) async {
      const bbcode = '前缀文字\n[img]https://e.com/big.png[/img]\n结尾文字';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);
      _dumpRichText('行内/块级');

      expect(find.byType(BbcodeImage), findsOneWidget);
      final imgRect = tester.getRect(find.byType(BbcodeImage));
      // ignore: avoid_print
      print('    │  块级图片 rect=$imgRect');
      expect(imgRect.width, greaterThan(300), reason: '块级图片应占满可用宽度');

      // 正文段落不与块级图片垂直重叠（即图片独占一行）
      for (final t in ['前缀文字', '结尾文字']) {
        final r = _rectOfText(t);
        expect(r, isNotNull, reason: '「$t」应被渲染');
        final overlaps = r!.top < imgRect.bottom && r.bottom > imgRect.top;
        // ignore: avoid_print
        print('    │  "$t" rect=$r 与图片重叠=$overlaps');
        expect(overlaps, isFalse, reason: '块级图片应独占一行，「$t」不应与其同行');
      }
    });

    testWidgets('内联注入：InlineCustomWidget 与文字同行内（￼ 占位符）', (tester) async {
      // 直接验证 fwfh 的内联注入语义：customWidgetBuilder 返回
      // InlineCustomWidget 时，占位符进入文字行内；返回普通 Widget 则成块
      const html = '<div>前文<span class="inline-x">x</span>后文</div>';
      await tester.pumpWidget(
        _wrap(
          HtmlWidget(
            html,
            buildAsync: false,
            customWidgetBuilder: (e) => e.classes.contains('inline-x')
                ? const InlineCustomWidget(
                    alignment: PlaceholderAlignment.middle,
                    child: SizedBox(width: 20, height: 20),
                  )
                : null,
          ),
        ),
      );
      await _settle(tester);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('前文') &&
              w.text.toPlainText().contains('\uFFFC') &&
              w.text.toPlainText().contains('后文'),
        ),
        findsOneWidget,
        reason: '内联注入的元素必须与前后文字同段',
      );
    });
  });

  group('② 链接内图片点击冒泡', () {
    testWidgets('点击被 [url] 包裹的块级图片 → 触发链接弹窗', (tester) async {
      const bbcode =
          '[url=https://example.com/page][img]https://e.com/a.png[/img][/url]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      expect(find.byType(BbcodeImage), findsOneWidget);
      await tester.tap(find.byType(BbcodeImage));
      await _settle(tester);

      // 链接确认弹窗出现，且携带正确 URL —— 证明点击冒泡到了 [url]
      expect(find.text('链接'), findsOneWidget, reason: '应弹出链接确认弹窗');
      expect(_text('https://example.com/page'), findsWidgets);
    });

    testWidgets('点击纯文字链接 → 触发链接弹窗', (tester) async {
      const bbcode = '[url=https://example.com/t]点我[/url]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      await tester.tap(_text('点我'));
      await _settle(tester);

      expect(find.text('链接'), findsOneWidget);
      expect(_text('https://example.com/t'), findsWidgets);
    });
  });

  group('③ 表格 + 代码块注入', () {
    testWidgets('td 内 code 被注入且表格内容不丢失', (tester) async {
      const bbcode =
          '[table]'
          '[tr][td][b]标题[/b][/td][td][code]print(1)[/code][/td][/tr]'
          '[tr][td]单元格二[/td][td][url=https://x.com]链接[/url][/td][/tr]'
          '[/table]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);
      _dumpRichText('表格 + code');

      expect(_text('标题'), findsWidgets, reason: '表格文本不应丢失');
      expect(_text('单元格二'), findsWidgets);
      expect(_text('链接'), findsWidgets);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
      expect(find.byType(HtmlTable), findsOneWidget);

      final tableSize = tester.getSize(find.byType(HtmlTable));
      // ignore: avoid_print
      print('    │  HtmlTable size=$tableSize');
      expect(tableSize.width, greaterThan(0));
      expect(tableSize.height, greaterThan(0));
    });

    testWidgets('表格嵌套表格 + 双层 code', (tester) async {
      const bbcode =
          '[table][tr]'
          '[td]外层[table][tr][td][code]inner_code()[/code][/td][/tr][/table][/td]'
          '[td][code]outer_code()[/code][/td]'
          '[/tr][/table]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      expect(find.byType(HtmlTable), findsNWidgets(2), reason: '嵌套表格应为 2 层');
      expect(find.byType(BbcodeCodeBlock), findsNWidgets(2));
      expect(_text('外层'), findsWidgets);
      expect(_text('inner_code()'), findsWidgets);
      expect(_text('outer_code()'), findsWidgets);
    });
  });

  group('④ 极端嵌套', () {
    const nested =
        '[quote]引用开头\n'
        '[hide][table][tr]'
        '[td][list][*]项一[*]项二[/list][/td]'
        '[td][code]a<b>c[/code][/td]'
        '[/tr][/table][/hide]\n'
        '[url=https://x.com][img]https://e.com/n.png[/img][/url]\n'
        '引用结尾[/quote]';

    testWidgets('quote>hide>table>td>(list|code) 容器不被拆散', (tester) async {
      await tester.pumpWidget(_post(nested));
      await _settle(tester);
      _dumpRichText('极端嵌套');

      for (final t in ['引用开头', '引用结尾', '项一', '项二', '隐藏内容']) {
        expect(_text(t), findsWidgets, reason: '「$t」应被渲染出来');
      }
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
      expect(find.byType(BbcodeImage), findsOneWidget);
      expect(find.byType(HtmlTable), findsOneWidget);

      final allText = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join('\n');
      for (final leak in [
        '[quote]',
        '[/quote]',
        '[hide]',
        '[/hide]',
        '[table]',
        '[/table]',
        '[code]',
        '[/code]',
      ]) {
        expect(allText.contains(leak), isFalse, reason: '不应泄漏原始标签 $leak');
      }
    });
  });

  group('⑤ 空行回归', () {
    testWidgets('列表 + 紧凑换行不产生多余空白段落', (tester) async {
      const bbcode =
          '[list]\n[*]项一\n[*]项二\n[/list]\n'
          '[img]https://e.com/x.png[/img]\n'
          '尾部文字';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      final blanks = <String>[];
      for (final el in find.byType(RichText).evaluate()) {
        final rich = el.widget as RichText;
        final plain = rich.text.toPlainText();
        final ro = el.renderObject as RenderParagraph?;
        if (plain.trim().isEmpty && (ro?.size.height ?? 0) > 0) {
          blanks.add('${ro?.size} "$plain"');
        }
      }
      // ignore: avoid_print
      print('    │  空白段落数=${blanks.length}');
      expect(blanks, isEmpty, reason: '不应存在多余空行');
      expect(_text('项一'), findsWidgets);
      expect(_text('尾部文字'), findsWidgets);
    });
  });

  group('⑥ 颜色容错', () {
    testWidgets('非法 hex 不崩溃，文本照常渲染', (tester) async {
      await tester.pumpWidget(_post('[color=#FFYYTT]非法色文本[/color]'));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: '非法 hex 不应抛异常');
      expect(_text('非法色文本'), findsWidgets);
    });

    testWidgets('4 位短 hex 归一化后为不透明红（防 docs/07 #30 回归）', (tester) async {
      await tester.pumpWidget(_post('[color=#ff00]短色文本[/color]'));
      await _settle(tester);

      Color? found;
      for (final el in find.byType(RichText).evaluate()) {
        final rich = el.widget as RichText;
        rich.text.visitChildren((span) {
          if (span is TextSpan &&
              span.text == '短色文本' &&
              span.style?.color != null) {
            found = span.style!.color;
          }
          return true;
        });
      }
      // ignore: avoid_print
      print('    │  4 位 hex 渲染色=$found');
      expect(found, isNotNull);
      expect(found!.a, 1.0, reason: 'alpha 不应为 0（透明）');
      expect(found!.r, greaterThan(0.5));
      expect(found!.g, lessThan(0.5));
    });
  });

  group('⑦ SelectionArea 兼容', () {
    testWidgets('quote/表格/链接混排下正常构建且内容齐全', (tester) async {
      await tester.pumpWidget(
        _post(
          '[quote]可选中文字[/quote]\n[table][tr][td]表内文字[/td][/tr][/table]\n'
          '[url=https://a.com]链接文字[/url]',
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(_text('可选中文字'), findsWidgets);
      expect(_text('表内文字'), findsWidgets);
      expect(_text('链接文字'), findsWidgets);
      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });

  group('⑧ 性能量级', () {
    testWidgets('长帖（50 段 + 代码块 + 表格）转换与渲染耗时', (tester) async {
      final buf = StringBuffer();
      for (var i = 0; i < 50; i++) {
        buf.write('[quote]第 $i 段引用内容[/quote]\n');
        if (i % 10 == 5) buf.write('[code]void main() { print($i); }[/code]\n');
        if (i % 10 == 7) {
          buf.write('[table][tr][td]表 $i 单元格[/td][/tr][/table]\n');
        }
      }
      final bbcode = buf.toString();

      final sw = Stopwatch()..start();
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);
      sw.stop();

      // ignore: avoid_print
      print(
        '    │  bbcode=${bbcode.length} 字符  首次构建=${sw.elapsedMilliseconds}ms',
      );
      expect(find.byType(HtmlTable), findsWidgets);
    });
  });

  group('⑨ 附件卡片', () {
    testWidgets('超长文件名不溢出（曾报 RenderHtmlFlex overflowed）', (tester) async {
      const name =
          'abcdefghijklmnopqrstuvwxyz_0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ_'
          'abcdefghijklmnopqrstuvwxyz_0123456789.zip';
      final bbcode =
          '[appdata]{"type":"attach","name":"$name","size":"1.25 MB",'
          '"downloads":"3","url":"/forum.php?mod=attachment&aid=1"}[/appdata]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      // 根因：渲染器会执行 `display:flex`，但其 flex 不支持 `flex:1` 收缩，
      // 长文件名（不可断行串）横向排布时撑破容器。卡片因此改用纯块级布局。
      expect(tester.takeException(), isNull, reason: '附件卡片不应溢出');
      expect(_text(name), findsWidgets, reason: '文件名应完整渲染');
      expect(_text('大小: 1.25 MB'), findsWidgets);
      expect(_text('下载 3 次'), findsWidgets);
      expect(_text('下载'), findsWidgets);
    });
  });

  group('⑪ 列表', () {
    testWidgets('无序列表：项即普通段落，无前缀、无左侧缩进', (tester) async {
      const bbcode = '正文段落\n[list][*]项一\n[*]项二[/list]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);
      expect(tester.takeException(), isNull);

      expect(_text('项一'), findsWidgets);
      expect(_text('项二'), findsWidgets);
      // 与正文同一左边界：列表不产生任何左侧留白
      expect(_rectOfText('项一')!.left, _rectOfText('正文段落')!.left);
      expect(_rectOfText('项二')!.left, _rectOfText('正文段落')!.left);
      // 原始标签不泄漏
      expect(_text('[list]'), findsNothing);
      expect(_text('[*]'), findsNothing);
    });

    testWidgets('有序列表：项前拼 1. / 2.，同样不缩进', (tester) async {
      await tester.pumpWidget(_post('[list=1][*]甲\n[*]乙[/list]'));
      await _settle(tester);
      expect(_text('1. 甲'), findsWidgets);
      expect(_text('2. 乙'), findsWidgets);
      expect(_rectOfText('1. 甲')!.left, 0);
    });

    testWidgets('有序列表 [list=a] → a. / b.', (tester) async {
      await tester.pumpWidget(_post('[list=a][*]甲\n[*]乙[/list]'));
      await _settle(tester);
      expect(_text('a. 甲'), findsWidgets);
      expect(_text('b. 乙'), findsWidgets);
    });

    testWidgets('深层嵌套不消耗水平宽度', (tester) async {
      const bbcode =
          '[list][*]一级\n'
          '[list][*]二级\n'
          '[list][*]三级\n'
          '[list][*]四级[/list]\n[/list]\n[/list]\n[/list]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      for (final t in ['一级', '二级', '三级', '四级']) {
        expect(_rectOfText(t)!.left, 0, reason: '「$t」不应因嵌套产生左侧缩进');
      }
    });

    testWidgets('列表位于表格单元格内也能正确切分', (tester) async {
      await tester.pumpWidget(
        _post('[table][tr][td][list][*]项一[*]项二[/list][/td][/tr][/table]'),
      );
      await _settle(tester);
      expect(_text('项一'), findsWidgets);
      expect(_text('项二'), findsWidgets);
    });

    testWidgets('嵌套 + [/*] 项结束标记：不产生重复段落、标签不泄漏', (tester) async {
      const bbcode = '[list][*]外层一\n[list][*]内层\n[/list]\n[/*][*]item2[/list]';
      await tester.pumpWidget(_post(bbcode));
      await _settle(tester);

      final all = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join('\n');
      // 每个项只渲染一次（回归：曾因 [/*] 之后的 [*] 被误判为散落文本而重复）
      for (final t in ['外层一', '内层', 'item2']) {
        expect(RegExp(t).allMatches(all).length, 1, reason: '「$t」应只出现一次');
      }
      expect(all.contains('[*]'), isFalse);
      expect(all.contains('[/*]'), isFalse);
      expect(all.contains('[/list]'), isFalse);
    });
  });

  group('⑩ 转换层遗留缺陷（与渲染器无关）', () {
    testWidgets('嵌套 [quote] 因非贪婪正则配对失败而泄漏闭标签', (tester) async {
      // 转换层按 Discuz 行为对齐：格式不正确的嵌套标签在网页上同样渲染不出，
      // 因此这里只记录现状，不做修复。
      await tester.pumpWidget(_post('[quote]外层[quote]内层[/quote]尾[/quote]'));
      await _settle(tester);

      final allText = find
          .byType(RichText)
          .evaluate()
          .map((e) => (e.widget as RichText).text.toPlainText())
          .join('');
      // ignore: avoid_print
      print('    │  渲染文本: "$allText"');

      expect(allText.contains('外层'), isTrue);
      expect(allText.contains('内层'), isTrue);
      // 记录现状：嵌套 quote 的闭标签会作为字面文本泄漏
      expect(
        allText.contains('[/quote]'),
        isTrue,
        reason:
            '当前转换器用非贪婪正则配对 quote，嵌套时闭标签泄漏——'
            '这是转换层缺陷，换渲染器不能解决',
      );
    });
  });

  group('⑫ 正文字号接线', () {
    testWidgets('未显式传字号：跟随设置项「正文字号」', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostHtmlWidget(bbcode: '正文'),
          settings: _FixedFontSettings(),
        ),
      );
      await _settle(tester);

      expect(_fontSizeOf('正文'), 24);
    });

    testWidgets('显式传字号：覆盖设置项（列表预览 / 签名等次要位置）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostHtmlWidget(bbcode: '正文', fontSize: 12),
          settings: _FixedFontSettings(),
        ),
      );
      await _settle(tester);

      expect(_fontSizeOf('正文'), 12);
    });

    testWidgets('代码块字号跟随正文，不被 16 封顶', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostHtmlWidget(bbcode: '[code]var x = 1;[/code]'),
          settings: _FixedFontSettings(),
        ),
      );
      await _settle(tester);

      final block = tester.widget<BbcodeCodeBlock>(
        find.byType(BbcodeCodeBlock),
      );
      expect(block.fontSize, 24);
    });
  });
}

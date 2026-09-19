import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// 回归测试：嵌套场景（table 套 table / table 套标签 / 标签套 table）
///
/// 根因：原 table 处理用非贪婪正则，嵌套时内层 `[/table]` 会截断外层块。
/// 修复：`outerBlocks` 栈式匹配最外层块；渲染侧由 flutter_widget_from_html
/// 原生渲染 `<table>`，不再需要「占位元素 + 按 table 分段」。
///
/// 注意：flutter_widget_from_html 的文本由 RichText 承载（不是 Text widget），
/// 文本查找必须 `findRichText: true`。
Finder _text(String s) => find.textContaining(s, findRichText: true);

void main() {
  setUp(() {
    SiteStore.instance.init();
  });

  group('BBCode2Html 表格转换', () {
    test('嵌套表格：结构完整，无残留标签', () {
      const bbcode =
          '[table][tr][td]a[table][tr][td]b[/td][/tr][/table]c[/td][/tr][/table]';
      final html = BBCode2Html().convert(bbcode);
      // ignore: avoid_print
      print(html);
      expect(html, contains('<table'));
      expect(html, contains('a'));
      expect(html, contains('b'));
      expect(html, contains('c'));
      expect(html, isNot(contains('[table]')));
      expect(html, isNot(contains('[/table]')));
      // 内层表格同样转成 <table>
      expect(RegExp(r'<table').allMatches(html).length, 2);
    });

    test('hide 套 table：blockquote 包住 table，容器标签不残留', () {
      const bbcode = '[hide][table][tr][td]x[/td][/tr][/table][/hide]';
      final html = BBCode2Html().convert(bbcode);
      expect(html, contains('<blockquote>'));
      expect(html, contains('<table'));
      expect(html, contains('隐藏内容'));
      expect(html, isNot(contains('[hide]')));
      expect(html, isNot(contains('[/hide]')));
    });

    test('quote 套 table：blockquote 包住 table', () {
      const bbcode = '[quote][table][tr][td]x[/td][/tr][/table][/quote]';
      final html = BBCode2Html().convert(bbcode);
      expect(html, contains('<blockquote>'));
      expect(html, contains('<table'));
      expect(html, isNot(contains('[quote]')));
      expect(html, isNot(contains('[/quote]')));
    });

    test('table 内 hide/quote：无残留标签', () {
      final html = BBCode2Html().convert(
        '[table][tr][td][hide]x[/hide][quote]y[/quote][/td][/tr][/table]',
      );
      expect(html, contains('<table'));
      expect(html, isNot(contains('[hide]')));
      expect(html, isNot(contains('[quote]')));
    });

    test('table 内 code：占位元素落在 cell 内，codeBlocks 完整', () {
      final converter = BBCode2Html(emitCodePlaceholder: true);
      final html = converter.convert(
        '[table][tr][td][code]x[/code][/td][/tr][/table]',
      );
      expect(html, contains('<table'));
      expect(html, contains('<td>'));
      expect(html, contains('data-code-index="0"'));
      expect(converter.codeBlocks, ['x']);
    });

    test('td 内 [align] 转成 div text-align，不残留 align 标签', () {
      final html = BBCode2Html().convert(
        '[table][tr][td][align=center][b]标题[/b][/align][/td][/tr][/table]',
      );
      expect(html, contains('text-align:center'));
      expect(html, contains('<strong>标题</strong>'));
      expect(html, isNot(contains('[align')));
    });
  });

  group('PostHtmlWidget 渲染', () {
    Widget wrap(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider.value(
            value: SettingsProvider(),
            child: child,
          ),
        ),
      );
    }

    testWidgets('table 套 table：无异常、无残留标签', (tester) async {
      const bbcode =
          '[table][tr][td]a[table][tr][td]b[/td][/tr][/table]c[/td][/tr][/table]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // a/c 文字保留，b 在内层表格
      expect(_text('a'), findsWidgets);
      expect(_text('b'), findsWidgets);
      expect(_text('c'), findsWidgets);
      expect(_text('[table]'), findsNothing);
      expect(_text('[/table]'), findsNothing);
      expect(find.byType(HtmlTable), findsNWidgets(2));
    });

    testWidgets('hide 套 table：hide 容器渲染、内容可见', (tester) async {
      const bbcode = '[hide][table][tr][td]x[/td][/tr][/table][/hide]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_text('隐藏内容'), findsWidgets);
      expect(_text('x'), findsWidgets);
      expect(_text('[hide]'), findsNothing);
      expect(find.byType(HtmlTable), findsOneWidget);
    });

    testWidgets('quote 套 table：引用容器渲染', (tester) async {
      const bbcode = '[quote][table][tr][td]x[/td][/tr][/table][/quote]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_text('x'), findsWidgets);
      expect(_text('[quote]'), findsNothing);
    });

    testWidgets('table 内 hide/quote/code 混合', (tester) async {
      const bbcode =
          '[table][tr][td][hide]h[/hide][/td][td][code]c[/code][/td][/tr][/table]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_text('隐藏内容'), findsWidgets);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
    });
  });
}

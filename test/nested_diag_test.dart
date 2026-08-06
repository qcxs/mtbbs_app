import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_table.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// 回归测试：嵌套场景（table 套 table / table 套标签 / 标签套 table）
///
/// 根因：原 splitByTable / BBCode2Html 的 table 处理用非贪婪正则，
/// 嵌套时内层 [/table] 截断外层块；splitByTable 还会拆散 hide/quote 容器。
/// 修复：outerBlocks 栈式匹配 + splitByTable 跳过容器内 table。
void main() {
  setUp(() {
    SiteStore.instance.init();
  });

  group('splitByTable', () {
    test('嵌套表格按最外层切分为一个完整 table 段', () {
      const bbcode =
          '[table][tr][td]a[table][tr][td]b[/td][/tr][/table]c[/td][/tr][/table]';
      final segments = splitByTable(bbcode);
      expect(segments.length, 1);
      expect(segments.first.isTable, isTrue);
      expect(segments.first.content, bbcode);
    });

    test('hide 套 table：整体留在普通段，不拆散 hide 容器', () {
      const bbcode = '[hide][table][tr][td]x[/td][/tr][/table][/hide]';
      final segments = splitByTable(bbcode);
      expect(segments.length, 1);
      expect(segments.first.isTable, isFalse);
      expect(segments.first.content, bbcode);
    });

    test('quote 套 table：整体留在普通段', () {
      const bbcode = '[quote][table][tr][td]x[/td][/tr][/table][/quote]';
      final segments = splitByTable(bbcode);
      expect(segments.length, 1);
      expect(segments.first.isTable, isFalse);
      expect(segments.first.content, bbcode);
    });

    test('table 内 hide：仍是 table 段', () {
      const bbcode = '[table][tr][td][hide]x[/hide][/td][/tr][/table]';
      final segments = splitByTable(bbcode);
      expect(segments.length, 1);
      expect(segments.first.isTable, isTrue);
    });

    test('顶层普通 table 仍被切出', () {
      const bbcode = '前文[table][tr][td]x[/td][/tr][/table]后文';
      final segments = splitByTable(bbcode);
      expect(segments.length, 3);
      expect(segments[1].isTable, isTrue);
    });
  });

  group('BBCode2Html', () {
    test('嵌套表格（渲染模式）：占位元素 + tableBlocks 保留完整嵌套块', () {
      const bbcode =
          '[table][tr][td]a[table][tr][td]b[/td][/tr][/table]c[/td][/tr][/table]';
      final converter = BBCode2Html(emitTablePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('data-table-index="0"'));
      expect(converter.tableBlocks, [bbcode]);
      expect(html, isNot(contains('[table]')));
      expect(html, isNot(contains('[/table]')));
    });

    test('hide 套 table（渲染模式）：blockquote 内占位元素', () {
      const bbcode = '[hide][table][tr][td]x[/td][/tr][/table][/hide]';
      final converter = BBCode2Html(emitTablePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('<blockquote>'));
      expect(html, contains('data-table-index="0"'));
      expect(converter.tableBlocks, ['[table][tr][td]x[/td][/tr][/table]']);
      expect(html, isNot(contains('[hide]')));
      expect(html, isNot(contains('[/hide]')));
    });

    test('quote 套 table（渲染模式）：blockquote 内占位元素', () {
      const bbcode = '[quote][table][tr][td]x[/td][/tr][/table][/quote]';
      final converter = BBCode2Html(emitTablePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('<blockquote>'));
      expect(html, contains('data-table-index="0"'));
      expect(html, isNot(contains('[quote]')));
      expect(html, isNot(contains('[/quote]')));
    });

    test('table 内 hide/quote（渲染模式）：无残留标签', () {
      final converter = BBCode2Html(emitTablePlaceholder: true);
      final html = converter.convert(
        '[table][tr][td][hide]x[/hide][quote]y[/quote][/td][/tr][/table]',
      );
      expect(html, contains('data-table-index="0"'));
      expect(html, isNot(contains('[hide]')));
      expect(html, isNot(contains('[quote]')));
    });

    test('table 内 code（渲染模式）：tableBlocks 还原纯 BBCode，codeBlocks 完整', () {
      final converter = BBCode2Html(
        emitCodePlaceholder: true,
        emitTablePlaceholder: true,
      );
      final html = converter.convert(
        '[table][tr][td][code]x[/code][/td][/tr][/table]',
      );
      expect(html, contains('data-table-index="0"'));
      expect(converter.tableBlocks, [
        '[table][tr][td][code]x[/code][/td][/tr][/table]',
      ]);
      expect(converter.codeBlocks, ['x']);
    });

    test('默认模式（非渲染）：table 转 <table> HTML（兼容旧行为）', () {
      final html = BBCode2Html().convert('[table][tr][td]x[/td][/tr][/table]');
      expect(html, contains('<table'));
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
      expect(find.textContaining('a'), findsOneWidget);
      expect(find.textContaining('b'), findsOneWidget);
      expect(find.textContaining('c'), findsOneWidget);
      expect(find.textContaining('[table]'), findsNothing);
      expect(find.textContaining('[/table]'), findsNothing);
    });

    testWidgets('hide 套 table：hide 容器渲染、内容可见', (tester) async {
      const bbcode = '[hide][table][tr][td]x[/td][/tr][/table][/hide]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('隐藏内容'), findsOneWidget);
      expect(find.textContaining('x'), findsOneWidget);
      expect(find.textContaining('[hide]'), findsNothing);
    });

    testWidgets('quote 套 table：引用容器渲染', (tester) async {
      const bbcode = '[quote][table][tr][td]x[/td][/tr][/table][/quote]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('x'), findsOneWidget);
      expect(find.textContaining('[quote]'), findsNothing);
    });

    testWidgets('table 内 hide/quote/code 混合', (tester) async {
      const bbcode =
          '[table][tr][td][hide]h[/hide][/td][td][code]c[/code][/td][/tr][/table]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('隐藏内容'), findsOneWidget);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// 回归测试：
/// 1. code 不再参与分段：BBCode2Html 还原为占位元素，flutter_html
///    extension 原地替换为代码高亮组件，hide/quote/table 等容器结构完整
/// 2. 非法 hex 颜色（如 [color=#FFYYTT]）不导致 flutter_html 抛异常
void main() {
  setUp(() {
    // PostHtmlWidget 依赖 SiteStore 当前站点（baseUrl），测试环境需初始化
    SiteStore.instance.init();
  });

  group('BBCode2Html emitCodePlaceholder 模式', () {
    test('hide 内 code 还原为占位元素，容器结构完整', () {
      const bbcode = '[hide]内容[code]内容[/code]内容[/hide]';
      final converter = BBCode2Html(emitCodePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('<blockquote>'));
      expect(html, contains('隐藏内容'));
      expect(
        html,
        contains('<div class="bbcode-code" data-code-index="0"></div>'),
      );
      // hide 标签与 <pre> 都不应出现
      expect(html, isNot(contains('[hide]')));
      expect(html, isNot(contains('[/hide]')));
      expect(html, isNot(contains('<pre>')));
      // codeBlocks 与索引对应
      expect(converter.codeBlocks, ['内容']);
    });

    test('code 内容含 < > & 时存原始代码（不残留 &gt;/&lt; 实体）', () {
      const bbcode = '[code]if (a < b && c > d) & e[/code]';
      // 渲染模式：codeBlocks 为原始代码，高亮组件直接显示
      final converter = BBCode2Html(emitCodePlaceholder: true);
      converter.convert(bbcode);
      expect(converter.codeBlocks, ['if (a < b && c > d) & e']);
      // 非渲染模式：<pre> 内实体转义，flutter_html 解码后显示原始代码
      final plain = BBCode2Html().convert(bbcode);
      expect(plain, contains('&lt;'));
      expect(plain, contains('&amp;'));
      // 字面 &lt;（转义为 &amp;lt;）不应被二次解码为 <
      final literal = BBCode2Html(emitCodePlaceholder: true);
      literal.convert('[code]x &lt; y[/code]');
      expect(literal.codeBlocks, ['x &lt; y']);
    });

    test('多个 code 块索引连续', () {
      const bbcode = '[code]a[/code]x[code]b[/code]';
      final converter = BBCode2Html(emitCodePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('data-code-index="0"'));
      expect(html, contains('data-code-index="1"'));
      expect(converter.codeBlocks, ['a', 'b']);
    });

    test('table 内 code 保留在 cell 中', () {
      const bbcode = '[table][tr][td][code]x[/code][/td][/tr][/table]';
      final converter = BBCode2Html(emitCodePlaceholder: true);
      final html = converter.convert(bbcode);
      expect(html, contains('<table'));
      expect(html, contains('<td style='));
      expect(html, contains('data-code-index="0"'));
    });

    test('默认模式仍渲染 <pre><code>（兼容旧行为）', () {
      const bbcode = '[code]x[/code]';
      final converter = BBCode2Html();
      final html = converter.convert(bbcode);
      expect(html, contains('<pre><code>'));
      expect(html, isNot(contains('data-code-index')));
    });

    test('非法 hex 颜色省略样式而非直通', () {
      const bbcode = '[color=#FFYYTT]内容[/color]';
      final html = BBCode2Html().convert(bbcode);
      expect(html, isNot(contains('color:#FFYYTT')));
      expect(html, contains('<span>内容</span>'));
    });

    test('合法 6/8 位 hex 原样保留', () {
      expect(
        BBCode2Html().convert('[color=#ff0000]内容[/color]'),
        contains('color:#ff0000'),
      );
      expect(
        BBCode2Html().convert('[color=#80ff0000]内容[/color]'),
        contains('color:#80ff0000'),
      );
    });

    test('4 位 hex 仍归一化为 #RRGG00（防回归 #30）', () {
      final html = BBCode2Html().convert('[color=#ff00]内容[/color]');
      expect(html, contains('color:#ff0000'));
      expect(html, isNot(contains('color:#ff00>')));
    });
  });

  group('PostHtmlWidget 渲染（extension 原地替换）', () {
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

    testWidgets('hide 内 code：容器渲染 + 高亮组件 + 无异常', (tester) async {
      const bbcode = '[hide]内容[code]内容[/code]内容[/hide]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
      expect(find.textContaining('隐藏内容'), findsOneWidget);
      // hide 标签不原样残留
      expect(find.textContaining('[hide]'), findsNothing);
    });

    testWidgets('quote 内 code：容器渲染 + 高亮组件', (tester) async {
      const bbcode = '[quote][code]int x = 1;[/code][/quote]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
    });

    testWidgets('顶层 code：独立高亮组件', (tester) async {
      const bbcode = '文字[code]void main() {}\n[/code]文字';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
      // 前后文字在同一个 Text 内（块级占位元素嵌入文本流）
      expect(find.textContaining('文字'), findsOneWidget);
    });

    testWidgets('table 内 code：code 保留在表格 cell 内渲染', (tester) async {
      const bbcode =
          '[table][tr][td]表头[/td][/tr][tr][td][code]x[/code][/td][/tr][/table]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(BbcodeCodeBlock), findsOneWidget);
    });

    testWidgets('非法 hex 颜色不抛异常', (tester) async {
      const bbcode = '[color=#FFYYTT]内容[/color]';
      await tester.pumpWidget(wrap(const PostHtmlWidget(bbcode: bbcode)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

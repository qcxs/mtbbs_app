import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/parser/bbcode_parser.dart';

/// 诊断测试：`[color=#ff00]`（4 位 hex，网页 HTML color 属性语义下为红色）
/// 在 app 中渲染成白色的根因定位。
///
/// 复现素材来自 bbs.binmt.cc/thread-170525 楼主正文解析出的真实 BBCode。
///
/// 结论链：渲染器按 **CSS 规范**把 4 位 hex 解读为 `#RGBA`（第 4 位是 alpha），
/// 而网页 `<font color="#ff00">` 走的是 **HTML color 属性 legacy 语义**（红色）。
/// 两者语义不同，故转换层 `_normalizeColor` 必须先把 `#ff00` 归一化为
/// `#ff0000` 再交给渲染器——这是本条存在的意义。
const bbcode =
    ''
    '[color=#ff00][font=-apple-system, BlinkMacSystemFont, &quot][size=4]链接: [/size][/font][/color]'
    '[font=-apple-system, BlinkMacSystemFont, &quot][size=4]'
    '[url=https://pan.baidu.com/s/13EdKWg3hj_vL16gIXSLoBQ?pwd=j8m6]'
    'https://pan.baidu.com/s/13EdKWg3hj_vL16gIXSLoBQ?pwd=j8m6'
    '[/url][/size][/font]'
    '[color=#ff00][font=-apple-system, BlinkMacSystemFont, &quot][size=4]'
    '    提取码: j8m6'
    '[/size][/font][/color]';

/// 是否「不透明且偏红」——本条的真实回归意图是防 alpha=0 透明（docs/07 #30）
bool _isOpaqueRed(Color? c) {
  if (c == null) return false;
  return c.a == 1.0 && c.r > 0.5 && c.g < 0.5 && c.b < 0.5;
}

void main() {
  test('AST 层：color 节点的 value 是否正确保留', () {
    final nodes = BBCodeParser().parse(bbcode);
    // ignore: avoid_print
    print(
      JsonEncoder.withIndent(
        '  ',
      ).convert(nodes.map((n) => n.toJson()).toList()),
    );
    final colorValues = <String>[];
    void walk(AstNode n) {
      if (n.type == 'color') colorValues.add(n.attrs['value'] ?? '');
      for (final c in n.children) {
        walk(c);
      }
    }

    for (final n in nodes) {
      walk(n);
    }
    // ignore: avoid_print
    print('color values: $colorValues');
    expect(colorValues, isNotEmpty);
    expect(colorValues.every((v) => v == '#ff00'), isTrue);
  });

  test('HTML 层：BBCode2Html 生成的标签（#ff00 应归一化为 #ff0000）', () {
    final html = BBCode2Html().convert(bbcode);
    // ignore: avoid_print
    print(html);
    expect(html, contains('color:#ff0000'));
    expect(html, isNot(contains('style="color:#ff00">')));
  });

  testWidgets('渲染树层：暗色主题下 #ff00 实际渲染的颜色', (tester) async {
    final html = BBCode2Html().convert(bbcode);
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlWidget(html, buildAsync: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 遍历 RichText，dump 每个 span 的文本与颜色
    final found = <String>[];
    void walk(InlineSpan span, String path) {
      if (span is TextSpan) {
        final text = span.text ?? '';
        if (text.contains('链接') || text.contains('提取码')) {
          // ignore: avoid_print
          print(
            'span[$path] text="$text" '
            'color=${span.style?.color} '
            'fontSize=${span.style?.fontSize}',
          );
          found.add(text);
          // 回归断言：颜色必须是不透明的红，不能是 alpha=0 的透明色
          expect(
            _isOpaqueRed(span.style?.color),
            isTrue,
            reason: '「$text」渲染色应为不透明红，实际 ${span.style?.color}',
          );
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c, '$path/');
        }
      }
    }

    final richTexts = find
        .byType(RichText)
        .evaluate()
        .map((e) => e.widget as RichText);
    // ignore: avoid_print
    print('RichText count: ${richTexts.length}');
    for (final rt in richTexts) {
      walk(rt.text, 'root');
    }
    expect(found, isNotEmpty);
  });

  testWidgets('渲染器颜色解析边界：4 位 hex 不被识别（故转换层必须归一化）', (tester) async {
    // 各组颜色：网页 legacy 语义 vs 渲染器实际解析
    const cases = [
      '#ff00', // 4 位 hex → 网页 legacy 语义为红，CSS 语义为 #RGBA
      '#ff0000', // 6 位 hex = 红
      'rgb(255, 0, 0)', // rgb() = 红
      'red', // 命名色 = 红
    ];
    final html = cases
        .map((c) => '<span style="color:$c">[color=$c]</span>')
        .join('<br>');

    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlWidget(html, buildAsync: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final resolved = <String, Color?>{};
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        final text = span.text?.trim() ?? '';
        if (text.startsWith('[color=')) {
          resolved[text] = span.style?.color;
          // ignore: avoid_print
          print('$text -> ${span.style?.color}');
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c);
        }
      }
    }

    for (final rt
        in find.byType(RichText).evaluate().map((e) => e.widget as RichText)) {
      walk(rt.text);
    }

    // 除 4 位 hex 外的写法渲染器都能给出不透明红
    for (final c in ['#ff0000', 'rgb(255, 0, 0)', 'red']) {
      expect(
        _isOpaqueRed(resolved['[color=$c]']),
        isTrue,
        reason: '$c 应解析为不透明红',
      );
    }

    // 4 位 hex：渲染器不识别该写法 → 不套用颜色（回落到继承色）。
    // 无论如何都不能是 alpha=0 的透明色（那会让文字"消失"，见 docs/07 #30）。
    final raw4 = resolved['[color=#ff00]'];
    // ignore: avoid_print
    print('4 位 hex 渲染器解析结果: $raw4');
    expect(raw4 == null || raw4.a == 1.0, isTrue, reason: '4 位 hex 绝不能让文字变透明');
  });
}

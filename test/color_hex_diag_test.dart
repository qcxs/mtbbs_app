import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/parser/bbcode_parser.dart';

/// 诊断测试：`[color=#ff00]`（4 位 hex，网页 HTML color 属性语义下为红色）
/// 在 app 中渲染成白色的根因定位。
///
/// 复现素材来自 bbs.binmt.cc/thread-170525 楼主正文解析出的真实 BBCode。
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
          body: SingleChildScrollView(child: Html(data: html)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 遍历 RichText，dump 每个 span 的文本与颜色
    final red = const Color(0xFFFF0000);
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
          // 回归断言：颜色必须是红色，不能是 alpha=0 的异常色
          expect(span.style?.color, red);
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c, '$path/');
        }
      }
    }

    final richTexts = tester
        .elementList(find.byType(RichText))
        .map((e) => e.widget as RichText);
    // ignore: avoid_print
    print('RichText count: ${richTexts.length}');
    for (final rt in richTexts) {
      walk(rt.text as InlineSpan, 'root');
    }
    expect(found, isNotEmpty);
  });

  testWidgets('flutter_html 颜色解析对照：确认修复边界', (tester) async {
    // 各组颜色：期望网页语义下的目标色
    const cases = [
      '#ff00', // 4 位 hex，网页 legacy 语义 = 红 rgb(255,0,0)
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
          body: SingleChildScrollView(child: Html(data: html)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    void walk(InlineSpan span) {
      if (span is TextSpan) {
        final text = span.text ?? '';
        if (text.startsWith('[color=')) {
          // ignore: avoid_print
          print('$text -> ${span.style?.color}');
        }
        for (final c in span.children ?? const <InlineSpan>[]) {
          walk(c);
        }
      }
    }

    for (final rt
        in tester
            .elementList(find.byType(RichText))
            .map((e) => e.widget as RichText)) {
      walk(rt.text as InlineSpan);
    }
  });
}

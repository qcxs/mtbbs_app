import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';

/// 回归测试：list 末尾附件图片后不应出现空白。
///
/// 根因：[/appdata] 后的换行在 `\n` → `<br>` 阶段变成 `<br>` 紧贴块级容器
/// 边界，渲染器将其渲染为段落末尾的空行（图片下方空白）。
const bbcode =
    ''
    '[list] \n'
    ' [*]让 AI 在 Smali 中搜索关键词（如 checkSignature、verifyLicense、isVip、isPro） \n'
    ' [*]让 AI 分析某个方法的调用链，看看校验逻辑是怎么走的 \n'
    ' [*]让 AI 帮你理解混淆后的类名，推测原始功能 \n'
    ' AI 会帮你把散落在几十个 Smali 文件里的校验点全部揪出来，比你用文本搜索器一个个翻效率高得多。 \n'
    ' [appdata]{"type":"image_attach","url":"https://attach.52pojie.cn/forum/202607/25/172746ijs797osj78oeec8.png","width":"478","aid":"2866833","name":"22.png","size":"79.82 KB","downloads":"0","uploadTime":"2026-7-25 17:27"}[/appdata] \n'
    '[/list]';

void main() {
  test('list 末尾图片后不产生 <br> 紧贴块级容器', () {
    final html = BBCode2Html().convert(bbcode);
    // 列表在转换层已展开为 <div>，图片后直接是 </div>，中间不允许再出现 <br>
    expect(html, matches(RegExp(r'<img[^>]*/>\s*</div>')));
    expect(html, isNot(contains('<br></div>')));
  });

  test('通用规则：任何块级标签四周不残留紧邻 <br>', () {
    const cases = <String>[
      // 1. 本次报告场景：list 末尾附件图片
      '[list][*]item\n[appdata]{"type":"image_attach","url":"https://a.com/x.png","width":"100"}[/appdata]\n[/list]',
      // 2. 文本 + list：br 不能紧贴 <ul>
      'text\n[list][*]a[/list]',
      // 3. 连续两个 list：中间不能有 br
      '[list][*]a[/list]\n[list][*]b[/list]',
      // 4. [align] 首尾换行：br 不能紧贴 <div>
      '[align=center]\n居中\n[/align]',
      // 5. 表格换行：br 不能紧贴 <table>/<td>
      '[table]\n[tr][td]a\n[/td][/tr][/table]',
      // 6. 引用：原有 blockquote 前后行为保持（br 不紧贴）
      'before\n[quote]引用\n[/quote]\nafter',
      // 7. 嵌套列表 + 项内图片（li 内末尾 br）
      '[list][*]外层一\n[list][*]内层\n[/list]\n[/*][*]item2[/list]',
    ];
    for (final c in cases) {
      final html = BBCode2Html().convert(c);
      // ignore: avoid_print
      print('----- $c\n$html');
      // 四个方向均不允许 <br> 紧邻块级标签
      expect(
        html,
        isNot(
          matches(
            RegExp(r'<br>\s*<(?:div|blockquote|ul|ol|li|table|tr|td|pre|hr)'),
          ),
        ),
      );
      expect(
        html,
        isNot(
          matches(
            RegExp(r'<br>\s*</(?:div|blockquote|ul|ol|li|table|tr|td|pre)'),
          ),
        ),
      );
      expect(
        html,
        isNot(
          matches(
            RegExp(r'</(?:div|blockquote|ul|ol|li|table|tr|td|pre)>\s*<br'),
          ),
        ),
      );
      expect(
        html,
        isNot(
          matches(
            RegExp(
              r'<(?:div|blockquote|ul|ol|li|table|tr|td|pre)(?:\s[^>]*)?>\s*<br',
            ),
          ),
        ),
      );
    }
  });

  testWidgets('渲染树：列表与图片渲染完整，且无多余空白段落', (tester) async {
    final html = BBCode2Html().convert(bbcode);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: HtmlWidget(
              html,
              buildAsync: false,
              textStyle: const TextStyle(fontSize: 16),
              customStylesBuilder: (e) {
                if (e.localName == 'ul') {
                  return {'padding-left': '24px', 'margin': '0'};
                }
                if (e.localName == 'li') return {'margin': '0', 'padding': '0'};
                return null;
              },
              customWidgetBuilder: (e) => e.localName == 'img'
                  ? Container(
                      key: const ValueKey('diag-img'),
                      width: double.tryParse(e.attributes['width'] ?? ''),
                      height: 100,
                      color: Colors.blueGrey,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 列表项与图片都渲染出来
    expect(
      find.textContaining('让 AI 在 Smali', findRichText: true),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('diag-img')), findsOneWidget);

    // 关键回归：不存在「只含空白/换行」的可见段落 —— 即没有多余空行
    final blanks = <String>[];
    for (final el in find.byType(RichText).evaluate()) {
      final rich = el.widget as RichText;
      final ro = el.renderObject as RenderParagraph?;
      final plain = rich.text.toPlainText();
      if (plain.trim().isEmpty && (ro?.size.height ?? 0) > 0) {
        blanks.add('${ro?.size} "$plain"');
      }
    }
    // ignore: avoid_print
    print('空白段落: $blanks');
    expect(blanks, isEmpty, reason: '不应存在多余空行');
  });
}

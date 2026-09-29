import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode_anchors.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:provider/provider.dart';

/// 【方案验证探针】「逐锚点渲染」与「整篇渲染」的保真度对比。
///
/// 新架构把预览从"整篇一次渲染"改成"**逐锚点渲染**"，于是锚点本身就挂在
/// 渲染树上（`GlobalKey`），定位变成"读这个 widget 的真实位置"——
/// 零文字匹配、零插值。这条路唯一的风险是**锚点边界处的空白处理**可能与
/// 整篇渲染不同（整篇渲染会移除紧邻块级标签的 `<br>`，见 docs/07 #17）。
///
/// 关注两件事：
/// 1. 文本段数是否一致（丢字/多字会立刻暴露）
/// 2. y 差是否**有界、不累积**（有界 = 可用；随篇幅增长 = 不可用）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final samples = <String, String>{
    '长帖（多段+图片+引用+hr）':
        '首先说明一下这个app的背景。\n'
        '[hr]\n'
        '[b]搜索[/b]\n'
        '支持uid（查看用户）、tid（打开帖子）、username（通过用户名查看用户）\n'
        '[img]https://a.com/1.png[/img]\n'
        '[b]积分分析[/b]\n'
        '利用已有信息，反推精华帖数和积分占比\n'
        '\n'
        '这一段前面有空行，是独立的段落。\n'
        '\n'
        '[quote]这是一段引用内容\n引用第二行[/quote]\n'
        '\n'
        '最后一段文字收尾。',
    '纯段落（无块级标签，10 段空行分隔）': List.generate(
      10,
      (i) => '第${i + 1}段文字，每段之间都有一个空行。',
    ).join('\n\n'),
    '连续无空行（10 行）': List.generate(10, (i) => '第${i + 1}行文字').join('\n'),
    '列表+表格+代码':
        '[list]\n[*]甲\n[*]乙\n[/list]\n'
        '\n'
        '[table]\n[tr][td]甲[/td][td]乙[/td][/tr]\n[/table]\n'
        '\n'
        '[code]void main() {}\nprint(1);[/code]\n'
        '\n'
        '结尾。',
    '隐藏+免费+对齐':
        '[hide]需要回复才能看\n第二行[/hide]\n'
        '[free]免费内容[/free]\n'
        '[align=center]居中一行[/align]\n'
        '收尾。',
    '10 图交替': List.generate(
      10,
      (i) => '第${i + 1}段文字\n[img]https://a.com/$i.png[/img]',
    ).join('\n'),
    '10 段+hr': List.generate(10, (i) => '第${i + 1}段文字\n[hr]').join('\n'),
  };

  testWidgets('整篇 vs 逐锚点', (tester) async {
    SiteStore.instance.init();

    Future<({double height, List<String> texts, List<double> ys})> pump(
      Widget child,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: SettingsProvider(),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final ys = <double>[];
      final texts = <String>[];
      for (final e in find.byType(RichText).evaluate()) {
        final t = (e.widget as RichText).text.toPlainText().trim();
        if (t.isEmpty) continue;
        ys.add((e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy);
        texts.add(t.length > 12 ? t.substring(0, 12) : t);
      }
      return (
        height: tester.getSize(find.byType(SingleChildScrollView).first).height,
        texts: texts,
        ys: ys,
      );
    }

    for (final entry in samples.entries) {
      final src = entry.value;
      final anchors = bbAnchors(src);
      final whole = await pump(
        PostHtmlWidget(bbcode: src, autoDetectUrls: false),
      );
      final perAnchor = await pump(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in anchors)
              PostHtmlWidget(bbcode: a.raw, autoDetectUrls: false),
          ],
        ),
      );

      final wholeMap = <String, double>{};
      for (var i = 0; i < whole.texts.length; i++) {
        wholeMap.putIfAbsent(whole.texts[i], () => whole.ys[i]);
      }
      final diffs = <double>[];
      for (var i = 0; i < perAnchor.texts.length; i++) {
        final w = wholeMap[perAnchor.texts[i]];
        if (w != null) diffs.add(perAnchor.ys[i] - w);
      }
      // ignore: avoid_print
      print('════ ${entry.key}');
      // ignore: avoid_print
      print(
        '锚点=${anchors.length}  '
        '文本段 整篇=${whole.texts.length}/逐锚点=${perAnchor.texts.length}  '
        '总高 整篇=${whole.height.toStringAsFixed(0)}/逐锚点=${perAnchor.height.toStringAsFixed(0)}',
      );
      if (diffs.isEmpty) {
        // ignore: avoid_print
        print('  无可比文本段');
      } else {
        final last = diffs.last;
        final spread = diffs.reduce((a, b) => a.abs() > b.abs() ? a : b);
        // ignore: avoid_print
        print(
          '  y差序列=${diffs.map((d) => d.toStringAsFixed(0)).join(',')}\n'
          '  首差=${diffs.first.toStringAsFixed(0)} 末差=${last.toStringAsFixed(0)} '
          '最大绝对差=${spread.toStringAsFixed(0)} '
          '是否恒定=${diffs.every((d) => (d - diffs.first).abs() < 0.5)}',
        );
      }
      // ignore: avoid_print
      print(
        '  锚点: ${anchors.map((a) => '${a.index}:${a.kind.name}/${a.label}').join(' | ')}',
      );
    }
  });
}

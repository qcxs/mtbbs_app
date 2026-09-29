import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/bbcode_source_lines.dart';
import 'package:mtbbs/widgets/editor/block_marker_gutter.dart';
import 'package:mtbbs/widgets/editor/editor_line_metrics.dart';

/// 锚点标记槽与编辑区行测量的测试。
///
/// 定位粒度是**锚点**不是行：一行源码可能渲染成 0 行（图片）或 N 行（长段
/// 换行），逐行对应既做不到也没必要。锚点怎么切见 `bbcode_anchors_test.dart`；
/// 这里只锁两件事：标记怎么显示/怎么点，以及编辑区的真实行位置测得到。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlockMarkerGutter', () {
    List<BlockMark> marks(List<(int, double)> raw) => [
      for (final (id, y) in raw) (id: id, y: y, label: '锚点$id'),
    ];

    test('当前锚点 = 不大于它的最后一个标记', () {
      final m = marks([(0, 0), (5, 100), (9, 200)]);
      expect(BlockMarkerGutter.activeMarkId(m, 0), 0);
      expect(BlockMarkerGutter.activeMarkId(m, 4), 0);
      expect(BlockMarkerGutter.activeMarkId(m, 5), 5);
      expect(BlockMarkerGutter.activeMarkId(m, 100), 9);
      // 当前锚点在第一个标记之前 → 取第一个
      expect(BlockMarkerGutter.activeMarkId(m, -1), 0);
      expect(BlockMarkerGutter.activeMarkId(const [], 3), isNull);
      expect(BlockMarkerGutter.activeMarkId(m, null), isNull);
    });

    test('太近的标记被跳过，但当前锚点一定保留', () {
      final m = marks([(0, 0), (1, 3), (2, 100)]);
      final shown = BlockMarkerGutter.visibleMarks(m, 1, minGap: 14);
      // 锚点 0 与当前锚点（1）几乎重叠 → 让位给当前锚点，跳过
      expect(shown.map((e) => e.id).toSet(), {1, 2});
      // 没有当前锚点时，锚点 1 因为贴着锚点 0 被跳过
      expect(BlockMarkerGutter.visibleMarks(m, null, minGap: 14).length, 2);
    });

    testWidgets('当前锚点显示箭头，其余是圆点', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 40,
              child: BlockMarkerGutter(
                marks: marks([(0, 0), (5, 60), (9, 120)]),
                activeId: 5,
                onTapId: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_right), findsOneWidget);
    });

    testWidgets('点标记回调对应锚点 id', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              width: 40,
              child: BlockMarkerGutter(
                marks: marks([(0, 0), (5, 60), (9, 120)]),
                activeId: 0,
                onTapId: tapped.add,
              ),
            ),
          ),
        ),
      );

      // 按位置点锚点 9（y=120）的标记，而不是按文本找（已经没有文本了）
      final rect = tester.getRect(find.byType(BlockMarkerGutter));
      await tester.tapAt(Offset(rect.center.dx, rect.top + 128));
      expect(tapped, [9]);
    });

    testWidgets('空 marks 不抛异常', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 100,
              width: 40,
              child: BlockMarkerGutter(marks: const [], onTapId: (_) {}),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.arrow_right), findsNothing);
    });
  });

  group('EditorLineMetrics', () {
    Future<EditorLineMetrics> measure(
      WidgetTester tester,
      String text, {
      double? width,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextField(
                      key: key,
                      controller: TextEditingController(text: text),
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final box = key.currentContext!.findRenderObject() as RenderBox;
      return EditorLineMetrics.measure(
        container: box,
        editableRoot: box,
        lines: bbcodeSourceLines(text),
      );
    }

    testWidgets('每行都有 y，且随行号递增', (tester) async {
      final metrics = await measure(tester, '第一行\n第二行\n第三行');
      expect(metrics.measuredLines, 3);
      final ys = [for (var i = 0; i < 3; i++) metrics.yOf(i)!];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
    });

    testWidgets('软换行时下一行的 y 仍正确递增', (tester) async {
      final metrics = await measure(
        tester,
        '这是一段很长的文字用来触发软换行这是一段很长的文字用来触发软换行\n第二行',
        // 窄宽度才会真的软换行
        width: 160,
      );
      // 第一逻辑行占了多个视觉行 → 第二行的间距明显大于一行高度
      expect(metrics.yOf(1)! - metrics.yOf(0)!, greaterThan(30));
    });

    testWidgets('空内容只有一行且不抛异常', (tester) async {
      final metrics = await measure(tester, '');
      expect(metrics.measuredLines, 1);
    });
  });

  group('编辑区标记槽容器（这里出过两个坑）', () {
    /// 复刻真实布局：标记槽在 Stack 内的非负位置，正文靠内边距让位。
    ///
    /// 坑 1：Stack 给非 Positioned 子节点 loose 约束，TextField 会缩到内容宽
    ///       → 需要 SizedBox(width: double.infinity) 兜底
    /// 坑 2：标记槽若用负偏移放到 Stack 之外，**画得出来但点不到**
    ///       （RenderBox.hitTest 先判 size.contains(position)）；
    ///       正文太短时 Stack 不够高，靠下的标记同样点不到
    Future<List<int>> pumpEditorLike(WidgetTester tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: kMarkerGutterWidth),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextField(
                          controller: TextEditingController(
                            text: List.generate(30, (i) => '第$i行').join('\n'),
                          ),
                          maxLines: null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: BlockMarkerGutter(
                        marks: const [
                          (id: 0, y: 0, label: '第一个锚点'),
                          (id: 1, y: 60, label: '第二个锚点'),
                        ],
                        onTapId: tapped.add,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tapped;
    }

    testWidgets('结构可布局，且编辑框占满剩余宽度', (tester) async {
      await pumpEditorLike(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextField)).width,
        closeTo(400 - 6 - kMarkerGutterWidth - 12, 1),
        reason: '编辑框没有占满剩余宽度 → Stack 的 loose 约束漏了兜底',
      );
    });

    testWidgets('标记在 Stack 内 → 点得到（负偏移会画得出来但点不到）', (tester) async {
      final tapped = await pumpEditorLike(tester);
      final rect = tester.getRect(find.byType(BlockMarkerGutter));
      await tester.tapAt(Offset(rect.center.dx, rect.top + 68));
      expect(tapped, [1], reason: '点不动 → 标记槽多半被放到了 Stack 之外');
    });

    testWidgets('标记槽在正文左侧且不重叠', (tester) async {
      await pumpEditorLike(tester);
      final gutter = tester.getRect(find.byType(BlockMarkerGutter));
      final field = tester.getRect(find.byType(TextField));
      expect(gutter.left, greaterThanOrEqualTo(0));
      expect(gutter.width, kMarkerGutterWidth);
      expect(
        gutter.right,
        lessThanOrEqualTo(field.left + 0.01),
        reason: '标记槽与编辑框重叠了',
      );
    });
  });
}

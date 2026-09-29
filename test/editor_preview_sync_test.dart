import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/parser/bbcode_anchors.dart';
import 'package:mtbbs/core/parser/bbcode_selection_highlight.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/editor/block_marker_gutter.dart';
import 'package:mtbbs/widgets/editor/editor_preview.dart';
import 'package:provider/provider.dart';

/// 预览侧：选中高亮（BBCode 包裹）与"锚点定位"的集成行为。
///
/// 这里锁的是**新架构的核心承诺**：预览按锚点逐块渲染，锚点位置是**读**出来的
/// 真实渲染坐标。所以最关键的一条断言是 —— `revealAnchor(id)` 之后，第 id 个
/// 锚点的 widget **真的**落在视口里（不是"算得差不多"）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('选中高亮（backcolor 包裹）', () {
    test('基本包裹', () {
      const s = '前面选中后面';
      expect(
        bbcodeHighlightSelection(s, 2, 4, '#ffeeaa'),
        '前面[backcolor=#ffeeaa]选中[/backcolor]后面',
      );
    });

    test('去掉高亮标签后文字与原文一致（不改内容，只加标签）', () {
      const s = '[b]加粗[/b]普通[color=red]红[/color]';
      final out = bbcodeHighlightSelection(s, 0, s.length, '#ffeeaa');
      expect(out.replaceAll(RegExp(r'\[/?backcolor[^\]]*\]'), ''), s);
    });

    test('起点落在标签内部 → 吸附到标签之后（否则会把 [b] 切成 [b + ]）', () {
      //           0123456
      const s = '[b]加粗文字[/b]';
      // 选区从 `[b]` 的中间开始；吸附后区间是 [3,6) = 加粗文
      final out = bbcodeHighlightSelection(s, 1, 6, '#ffeeaa');
      expect(out, '[b][backcolor=#ffeeaa]加粗文[/backcolor]字[/b]');
    });

    test('终点落在标签内部 → 拉回标签之前', () {
      const s = '[b]加粗文字[/b]';
      // 终点落在 `[/b]` 中间
      final out = bbcodeHighlightSelection(s, 3, 10, '#ffeeaa');
      expect(out, '[b][backcolor=#ffeeaa]加粗文字[/backcolor][/b]');
    });

    test('完整标签内的文字：标签留在外面', () {
      const s = '[color=red]红字[/color]';
      final out = bbcodeHighlightSelection(s, 11, 13, '#ffeeaa');
      expect(out, '[color=red][backcolor=#ffeeaa]红字[/backcolor][/color]');
    });

    test('空选区 / 反转 / 越界 一律安全', () {
      const s = 'abc';
      expect(bbcodeHighlightSelection(s, 1, 1, '#f00'), s);
      expect(bbcodeHighlightSelection('', 0, 5, '#f00'), '');
      expect(bbcodeHighlightSelection(s, 999, 999, '#f00'), s);
      // 反转区间按正常处理，不抛异常
      expect(bbcodeHighlightSelection('abcd', 3, 1, '#f00'), contains('bc'));
    });

    test('未闭合的 [ 视为普通字符，不吸附', () {
      const s = 'a[未闭合';
      final out = bbcodeHighlightSelection(s, 1, s.length, '#f00');
      expect(out, 'a[backcolor=#f00][未闭合[/backcolor]');
    });
  });

  group('EditorPreview 锚点定位', () {
    // 足够长、锚点足够多（空行分段），保证内容高于测试视口 → 才有"能不能滚过去"可言
    final src = List.generate(40, (i) => '第${i + 1}行内容').join('\n\n');

    EditorPreviewData dataOf(String title, String content) => EditorPreviewData(
      title,
      [for (final a in bbAnchors(content)) EditorPreviewBlock(a.raw, a.label)],
    );

    Future<EditorPreviewState> pumpPreview(
      WidgetTester tester, {
      required bool offstage,
      String? content,
      int? activeAnchor,
    }) async {
      SiteStore.instance.init();
      final data = ValueNotifier(dataOf('', content ?? src));
      final key = GlobalKey<EditorPreviewState>();
      final preview = ChangeNotifierProvider.value(
        value: SettingsProvider(),
        child: EditorPreview(
          key: key,
          data: data,
          activeAnchor: activeAnchor ?? 3,
          onShowRaw: () {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: offstage
                  // 窄屏：编辑区在前、预览在 IndexedStack 第二格（布局但不绘制）
                  ? IndexedStack(
                      index: 0,
                      children: [const Text('编辑区'), preview],
                    )
                  : preview,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      return key.currentState!;
    }

    /// 取预览自己的滚动位置。
    ///
    /// 必须 `skipOffstage: false`：窄屏布局把预览放在 `IndexedStack` 的未选中格，
    /// 默认 finder 会当它 offstage 跳过（但它**仍然参与布局**，所以测量照常可用）。
    ScrollPosition previewPosition(WidgetTester tester) => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(EditorPreview, skipOffstage: false),
                matching: find.byType(Scrollable, skipOffstage: false),
                skipOffstage: false,
              )
              .first,
        )
        .position;

    testWidgets('标记槽渲染出来，且落在视口内（不会被 Stack 裁掉）', (tester) async {
      await pumpPreview(tester, offstage: false);

      final gutter = find.byType(BlockMarkerGutter);
      expect(gutter, findsOneWidget, reason: '标记槽没渲染出来');
      expect(
        find.byIcon(Icons.arrow_right),
        findsOneWidget,
        reason: '当前锚点标记（箭头）没渲染出来',
      );

      // 标记槽必须整体落在屏幕内：负偏移落进内边距时若被 Stack 裁掉，这里能看出来
      final rect = tester.getRect(gutter);
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.left, lessThan(screen.width));
      expect(rect.width, kMarkerGutterWidth);
    });

    testWidgets('每个锚点都有真实位置，且随文档顺序递增', (tester) async {
      final state = await pumpPreview(tester, offstage: false);
      final ys = [
        for (var i = 0; i < state.debugMarks.length; i++)
          state.debugAnchorY(state.debugMarks[i].id),
      ];
      expect(ys.length, greaterThanOrEqualTo(5), reason: '锚点太少，测不出东西');
      for (var i = 0; i < ys.length; i++) {
        expect(ys[i], isNotNull, reason: '第 $i 个锚点没有位置');
        if (i > 0) {
          expect(ys[i]!, greaterThan(ys[i - 1]!), reason: '锚点位置倒退');
        }
      }
    });

    testWidgets('定位准确：revealAnchor 之后该锚点真的在视口内', (tester) async {
      final state = await pumpPreview(tester, offstage: false);
      final last = state.debugMarks.last.id;

      state.revealAnchor(last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final pos = previewPosition(tester);
      expect(pos.pixels, greaterThan(0), reason: '完全没有滚动 → 定位没生效');

      // 硬断言：目标锚点的 widget 必须落在视口范围内
      final key = state.debugAnchorKey(last);
      expect(key, isNotNull);
      final rect = tester.getRect(find.byKey(key!));
      final viewport = tester.getRect(find.byType(EditorPreview));
      expect(
        rect.top,
        greaterThanOrEqualTo(viewport.top - 1),
        reason: '锚点被滚到了视口上方 → 定位偏了',
      );
      expect(rect.top, lessThan(viewport.bottom), reason: '锚点没有进入视口 → 定位偏了');
    });

    testWidgets('长帖中间任意锚点都能精确落进视口（不累积漂移）', (tester) async {
      final state = await pumpPreview(tester, offstage: false);
      final ids = state.debugMarks.map((m) => m.id).toList();
      final viewport = tester.getRect(find.byType(EditorPreview));

      // 从头走到尾挑几个：中途错了后面一定会露馅
      for (final id in [ids[ids.length ~/ 2], ids[ids.length - 2], ids.last]) {
        state.revealAnchor(id);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final key = state.debugAnchorKey(id)!;
        final rect = tester.getRect(find.byKey(key));
        expect(
          rect.top,
          inInclusiveRange(viewport.top - 1, viewport.bottom),
          reason: '锚点 $id 没落进视口（帖子越长越明显的那种偏差）',
        );
      }
    });

    testWidgets('长帖（段落 + 引用 + 图片混合）任意位置都精确落进视口', (tester) async {
      SiteStore.instance.init();
      // 形似真实长帖：段落多、夹引用、每隔几段一张附件图、还有空行
      final longPost = List.generate(
        30,
        (i) =>
            '第${i + 1}段正文，用来把帖子撑得足够长。\n'
            '[quote]第${i + 1}个引用内容[/quote]'
            '${i % 5 == 0 ? '\n[attachimg]${1000 + i}[/attachimg]' : ''}',
      ).join('\n\n');

      final state = await pumpPreview(
        tester,
        offstage: false,
        content: longPost,
      );
      final ids = state.debugMarks.map((m) => m.id).toList();
      expect(ids.length, greaterThan(50), reason: '锚点太少，测不出长帖的表现');
      final viewport = tester.getRect(find.byType(EditorPreview));

      for (final id in [
        ids[ids.length ~/ 4],
        ids[ids.length ~/ 2],
        ids[ids.length * 3 ~/ 4],
        ids[ids.length - 2],
        ids.last,
      ]) {
        state.revealAnchor(id);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final rect = tester.getRect(find.byKey(state.debugAnchorKey(id)!));
        expect(
          rect.top,
          inInclusiveRange(viewport.top - 1, viewport.bottom),
          reason: '锚点 $id 没落进视口 —— 长帖上的累积漂移',
        );
      }
    });

    testWidgets('离屏（窄屏未切到预览）也能测量并定位', (tester) async {
      final state = await pumpPreview(tester, offstage: true);
      final last = state.debugMarks.last.id;

      state.revealAnchor(last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        previewPosition(tester).pixels,
        greaterThan(0),
        reason: '完全没有滚动 → 定位没生效',
      );
    });

    testWidgets('尺寸变化不重建正文子树（拖动窗口卡顿的根源）', (tester) async {
      await pumpPreview(tester, offstage: false);
      final before = tester.widget(find.byType(PostHtmlWidget).first);

      // 模拟拖动窗口：改尺寸 → 触发重建
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pump();
      await tester.pump();

      final after = tester.widget(find.byType(PostHtmlWidget).first);
      expect(
        identical(before, after),
        isTrue,
        reason: '尺寸变化导致正文重建 → 拖动窗口会逐帧重跑 BBCode→Widget 转换',
      );
    });

    testWidgets('图片锚点有自己的位置（不退化到上一段）', (tester) async {
      SiteStore.instance.init();
      const plain = '第一行文字\n[img]https://a.com/x.png[/img]\n第三行文字';
      final state = await pumpPreview(tester, offstage: false, content: plain);

      final imageAnchor = state.debugMarks.firstWhere(
        (m) => m.id == 1,
        orElse: () => (id: -1, y: -1, label: ''),
      );
      expect(imageAnchor.id, 1, reason: '第 1 个锚点应为图片');
      expect(imageAnchor.label, '图片', reason: '图片锚点的提示应是类型名');

      final y0 = state.debugAnchorY(0)!;
      final y1 = state.debugAnchorY(1)!;
      final y2 = state.debugAnchorY(2)!;
      expect(y1, greaterThan(y0), reason: '图片锚点退化成了上一段（y 相同）');
      expect(y1, lessThan(y2), reason: '图片锚点应夹在前后两段之间');
    });

    testWidgets('长帖：标记散布全篇，不是全挤在同一处', (tester) async {
      SiteStore.instance.init();
      // 形似真实长帖：段落多、图片附件行多、有引用与分隔线、有空行
      const long =
          '首先说明一下这个app的背景。\n'
          '[hr]\n'
          '[b]搜索[/b]\n'
          '支持uid（查看用户）、tid（打开帖子）、username（通过用户名查看用户）\n'
          '[attachimg]367157[/attachimg]\n'
          '[b]积分分析[/b]\n'
          '利用已有信息，反推精华帖数和积分占比\n'
          '\n'
          '[quote]这是一段引用内容\n引用第二行[/quote]\n'
          '\n'
          '最后一段文字收尾。';
      final state = await pumpPreview(tester, offstage: false, content: long);

      final marks = state.debugMarks;
      expect(marks.length, greaterThanOrEqualTo(6), reason: '标记太少');
      // 关键：y 要分散。全挤在一个值说明定位退化了
      expect(
        marks.map((m) => m.y).toSet().length,
        greaterThanOrEqualTo(5),
        reason: '标记全挤在同一位置 → 锚点没有各自的位置',
      );
      for (var i = 1; i < marks.length; i++) {
        expect(
          marks[i].y,
          greaterThanOrEqualTo(marks[i - 1].y - 0.01),
          reason: '标记 y 倒退',
        );
      }
    });

    testWidgets('布局尺寸变化后会重测（图片撑开、改宽度都要重画标记）', (tester) async {
      final state = await pumpPreview(tester, offstage: false);
      final before = state.debugMeasureCount;

      // 只改高度、不改宽度：绕开"宽度变化"那条路径，专门验证滚动指标这条
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.debugMeasureCount,
        greaterThan(before),
        reason: '内容尺寸变了却没重测 → 图片加载完撑开整篇后，标记就画错位置了',
      );
    });

    test('数据相等性：内容没变就不通知（避免无谓重建）', () {
      final a = dataOf('标题', '第一段\n\n第二段');
      final b = dataOf('标题', '第一段\n\n第二段');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == (dataOf('标题', '第一段')), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/thread/thread_post_card.dart';
import 'package:provider/provider.dart';

/// 只读缓存页复用 [ThreadPostCard] 展示快照内容。
/// 回归：只读模式必须隐藏评分/回复、编辑与「更多」菜单，
/// 避免离线页误触发写操作。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SiteStore.instance.init());

  Widget harness(Widget child) =>
      ChangeNotifierProvider<SettingsProvider>.value(
        value: SettingsProvider(),
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  const comment = PostItem(
    pid: '101',
    floor: 2,
    uid: 'u1',
    username: 'alice',
    postTime: '3 小时前',
    bbcode: '',
  );

  testWidgets('只读模式隐藏评分、回复、编辑与更多菜单', (tester) async {
    await tester.pumpWidget(
      harness(
        const ThreadPostCard(
          post: comment,
          index: 0,
          tid: '42',
          currentUid: 'u1',
          readOnly: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('评分'), findsNothing);
    expect(find.text('回复'), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byType(PopupMenuButton<PostCardAction>), findsNothing);
  });

  testWidgets('可交互模式保留评分、回复、编辑与更多菜单', (tester) async {
    await tester.pumpWidget(
      harness(
        const ThreadPostCard(
          post: comment,
          index: 0,
          tid: '42',
          currentUid: 'u1',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('评分'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byType(PopupMenuButton<PostCardAction>), findsOneWidget);
  });
}

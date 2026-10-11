import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/models/thread_detail.dart';
import 'package:mtbbs/models/thread_item.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/thread/thread_card.dart';
import 'package:mtbbs/widgets/thread/thread_post_card.dart';

/// 帖子卡片/评论卡片的头部徽标布局回归：
/// 1) 标签多（楼主 + 置顶回复 + 印章 + 长昵称）时**不得横向溢出**（用 Wrap 化解）；
/// 2) 精华帖在右侧以「盖章」样式渲染（不再挤在标题前）。
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

  testWidgets('评论头部：楼主 + 置顶回复 + 印章 + 长昵称 不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const post = PostItem(
      pid: '9960355',
      floor: 3,
      floorLabel: '椅子',
      isOp: true,
      uid: '',
      username: '这是一个非常非常长的用户昵称用来触发横向溢出回归',
      usergroup: '博士后',
      postTime: '2025-8-4 16:36:46',
      ipLocation: '陕西',
      stamp: '精华',
      isStickReply: true,
    );
    await tester.pumpWidget(
      harness(const ThreadPostCard(post: post, index: 0, tid: '154148')),
    );
    await tester.pump();

    // 渲染成功（未抛 overflow）即可到这里
    expect(find.text('置顶回复'), findsOneWidget);
    expect(find.text('精华'), findsOneWidget);
    expect(find.text('楼主'), findsOneWidget);
  });

  testWidgets('帖子卡片：精华帖渲染「精」印章，标题保持完整', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const item = ThreadItem(
      uid: 0,
      nickname: '',
      time: '刚刚',
      title: '帖子标题',
      threadId: 1,
      digest: 1,
    );
    await tester.pumpWidget(harness(const ThreadCard(item: item)));
    await tester.pump();

    expect(find.text('精'), findsOneWidget);
    expect(find.text('帖子标题'), findsOneWidget);
  });
}

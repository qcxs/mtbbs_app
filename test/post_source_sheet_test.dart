import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/widgets/thread/post_source_sheet.dart';

void main() {
  const appdataBbcode =
      '[b]正文[/b]\n'
      '[appdata]{"type":"image_attach","url":"https://cdn.example.com/a.png"}[/appdata]';

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('默认显示纯 BBCode 视角（appdata 已降级）', (tester) async {
    await tester.pumpWidget(
      host(const PostSourceSheet(username: 'u', bbcode: appdataBbcode)),
    );

    expect(
      find.textContaining('[img]https://cdn.example.com/a.png[/img]'),
      findsOneWidget,
    );
    expect(find.textContaining('"type":'), findsNothing);
    expect(find.textContaining('可直接粘贴到编辑器'), findsOneWidget);
    // 正文块必须贴左（16 内边距），不能因内容变短而被 Column 居中
    expect(tester.getRect(find.byType(SelectableText)).left, 16.0);
  });

  testWidgets('右上角切到 App 后显示 appdata 原始结构', (tester) async {
    await tester.pumpWidget(
      host(const PostSourceSheet(username: 'u', bbcode: appdataBbcode)),
    );

    await tester.tap(find.text('App'));
    await tester.pumpAndSettle();

    expect(find.textContaining('"type":"image_attach"'), findsOneWidget);
    expect(find.textContaining('[img]'), findsNothing);
  });
}

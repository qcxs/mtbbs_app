import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/widgets/dialog/managed_list_dialog.dart';

/// 统一列表管理面板（底部抽屉）回归。
///
/// 关键约束：面板内容是 `Column + Expanded`，而 `Expanded` 依赖父级给出的
/// 高度上界 —— 所以 `showModalBottomSheet` 的 `constraints` 必须给 maxHeight，
/// 否则无界高度下布局直接抛异常（docs/07 #53 记过这个坑）。
/// 本文件用例只要成功渲染，就同时锁住了这条。
///
/// 另一个诉求是"充分使用宽度"：旧实现把正文写死 `SizedBox(width: 360)`，
/// 故断言列表行明显宽于 360。
void main() {
  final items = [
    ManagedItem(id: 'a', name: '链接 A'),
    ManagedItem(id: 'b', name: '链接 B'),
  ];

  Future<void> pumpHost(
    WidgetTester tester, {
    List<ManagedItem>? list,
    bool allowAdd = true,
    bool allowEdit = true,
    bool allowDelete = true,
    bool allowToggleVisibility = true,
    Future<ManagedItem?> Function()? onAdd,
    Future<bool> Function(String id)? onDelete,
    void Function(String id)? onToggleVisibility,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showManagedListDialog(
                  context: context,
                  title: '快捷链接',
                  items: list ?? items,
                  allowAdd: allowAdd,
                  allowEdit: allowEdit,
                  allowDelete: allowDelete,
                  allowReorder: true,
                  allowToggleVisibility: allowToggleVisibility,
                  onAdd: onAdd,
                  onDelete: onDelete,
                  onToggleVisibility: onToggleVisibility,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('以底部抽屉呈现：标题、列表项可见且无异常', (tester) async {
    await pumpHost(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('快捷链接'), findsOneWidget);
    expect(find.text('链接 A'), findsOneWidget);
    expect(find.text('链接 B'), findsOneWidget);
  });

  testWidgets('列表行宽于旧弹窗的 360px 正文宽度', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHost(tester);

    final width = tester.getSize(find.byType(ListTile).first).width;
    expect(width, greaterThan(400), reason: '应为铺开的抽屉宽度，而非写死的 360');
    expect(width, lessThanOrEqualTo(560), reason: '宽屏下仍受 maxWidth 约束');
  });

  testWidgets('空列表显示 emptyHint，不会因 Expanded 无界而崩', (tester) async {
    await pumpHost(tester, list: const []);

    expect(tester.takeException(), isNull);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('关闭按钮收起面板', (tester) async {
    await pumpHost(tester);
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显隐按钮回调带正确 id，并就地翻转图标', (tester) async {
    String? toggled;
    await pumpHost(tester, onToggleVisibility: (id) => toggled = id);

    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump();

    expect(toggled, 'a');
    // 第一个条目变为不可见：出现 visibility_off
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('新增入口存在并能拉起回调', (tester) async {
    var added = false;
    await pumpHost(
      tester,
      onAdd: () async {
        added = true;
        return null;
      },
    );

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(added, isTrue);
    // 关闭原则：拉起新增前先关闭本面板
    expect(find.byType(BottomSheet), findsNothing);
  });
}

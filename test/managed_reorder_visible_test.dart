import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/models/managed_item.dart';

/// 「只看已显示项」视图下的排序换算：可见子序列下标 → 完整列表的一次移动。
/// 关键不变量：**可见项的相对顺序**必须与用户在过滤视图里的操作一致。
void main() {
  ManagedItem v(String id) => ManagedItem(id: id, name: id, visible: true);
  ManagedItem h(String id) => ManagedItem(id: id, name: id, visible: false);

  /// 施加一次移动后，可见项 id 的顺序
  List<String> visibleIdsAfterMove(
    List<ManagedItem> items,
    int oldVisible,
    int newVisible,
  ) {
    final r = reorderVisibleToFull(items, oldVisible, newVisible);
    expect(r, isNotNull);
    final list = List<ManagedItem>.from(items);
    reorderManagedItems(list, r!.from, r.to);
    return list.where((e) => e.visible).map((e) => e.id).toList();
  }

  test('可见项被隐藏项穿插时，重排仍得到正确的可见顺序', () {
    // [A, h1, B, h2, C] → 可见 [A,B,C]
    List<ManagedItem> build() => [v('A'), h('h1'), v('B'), h('h2'), v('C')];

    // A 拖到末尾 → 可见 [B,C,A]
    expect(visibleIdsAfterMove(build(), 0, 2), ['B', 'C', 'A']);
    // C 拖到最前 → 可见 [C,A,B]
    expect(visibleIdsAfterMove(build(), 2, 0), ['C', 'A', 'B']);
    // A 拖到中间 → 可见 [B,A,C]
    expect(visibleIdsAfterMove(build(), 0, 1), ['B', 'A', 'C']);
    // B 拖到末尾 → 可见 [A,C,B]
    expect(visibleIdsAfterMove(build(), 1, 2), ['A', 'C', 'B']);
  });

  test('隐藏项不参与相对顺序判断（移位不可见）', () {
    final items = [v('A'), h('h1'), v('B'), h('h2'), v('C')];
    final r = reorderVisibleToFull(items, 0, 2)!;
    reorderManagedItems(items, r.from, r.to);
    // 可见顺序正确即可，隐藏项位置不保证
    expect(items.where((e) => e.visible).map((e) => e.id), ['B', 'C', 'A']);
  });

  test('无可见项 / 下标越界 → null', () {
    expect(reorderVisibleToFull([h('h1'), h('h2')], 0, 0), isNull);
    expect(reorderVisibleToFull([v('A'), h('h1')], 5, 0), isNull);
  });
}

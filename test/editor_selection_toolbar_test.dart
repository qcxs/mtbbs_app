import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/widgets/editor/editor_selection_toolbar.dart';

/// 选择菜单避让：选区离工具栏太近时判定为重叠，菜单应翻到选区下方。
void main() {
  test('选区靠近工具栏 → 判定为重叠', () {
    expect(
      selectionMenuWouldOverlapToolbar(selectionTop: 100, toolbarBottom: 80),
      isTrue,
    );
    // 差 55（菜单高度 56 以内）：仍算重叠
    expect(
      selectionMenuWouldOverlapToolbar(selectionTop: 135, toolbarBottom: 80),
      isTrue,
    );
  });

  test('选区远离工具栏 → 不重叠', () {
    expect(
      selectionMenuWouldOverlapToolbar(selectionTop: 140, toolbarBottom: 80),
      isFalse,
    );
  });
}

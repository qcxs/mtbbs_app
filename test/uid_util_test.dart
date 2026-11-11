import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/utils/uid_util.dart';

void main() {
  group('uidFromHref 兼容多种站点写法', () {
    test('伪静态 space-uid-N.html', () {
      expect(uidFromHref('space-uid-1155.html'), '1155');
      expect(uidFromHref('/forum.php?mod=space-uid-1155'), '1155');
    });

    test('52pojie 查询串 home.php?mod=space&uid=N', () {
      expect(
        uidFromHref('home.php?mod=space&uid=879080'),
        '879080',
      );
      // html 包有时保留实体，需自行归一化
      expect(
        uidFromHref('https://www.52pojie.cn/home.php?mod=space&amp;uid=879080'),
        '879080',
      );
    });

    test('space.php?uid=N', () {
      expect(uidFromHref('space.php?uid=42'), '42');
    });

    test('宽松模式兜底任意 uid=N', () {
      expect(uidFromHref('home.php?uid=7&do=wall'), '7');
    });

    test('严格模式拒绝非用户空间链接', () {
      // 私信删除菜单：也带 uid=，但 uid=1 不是对方 uid
      const deleteMenu =
          'home.php?mod=spacecp&ac=pm&op=delete&deletepm_deluid[]=1&uid=1';
      expect(uidFromHref(deleteMenu), '1');
      expect(uidFromHref(deleteMenu, strict: true), isNull);
      // spacecp 是操作页，不是用户主页
      expect(
        uidFromHref('home.php?mod=spacecp&ac=friend&uid=5', strict: true),
        isNull,
      );
    });

    test('无法识别时返回 null', () {
      expect(uidFromHref(null), isNull);
      expect(uidFromHref(''), isNull);
      expect(uidFromHref('thread-123-1-1.html'), isNull);
    });
  });
}

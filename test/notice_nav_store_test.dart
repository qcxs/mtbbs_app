import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/notice_nav_store.dart';

void main() {
  final nav = NoticeNavStore.instance;

  setUp(() => nav.clear());

  const views = [
    {'id': 'mypost', 'label': '我的帖子', 'count': 0},
    {'id': 'interactive', 'label': '坛友互动', 'count': 0},
    {'id': 'system', 'label': '系统提醒', 'count': 1},
  ];

  test('activeSubtype 按 view 隔离：系统提醒不会继承我的帖子的 post', () {
    nav.syncFromPage({
      'views': views,
      'activeView': 'mypost',
      'hasSubBar': true,
      'subtypes': [
        {'id': 'post', 'label': '帖子', 'count': 0},
        {'id': 'pcomment', 'label': '点评', 'count': 0},
      ],
      'activeSubtype': 'post',
    }, requestedView: 'mypost');

    expect(nav.activeSubtypeFor('mypost'), 'post');

    // 系统提醒页：有 ul.tb，但没有 type= 链接 → 子类型为空、activeSubtype 为空
    nav.syncFromPage({
      'views': views,
      'activeView': 'system',
      'hasSubBar': true,
      'subtypes': [],
      'activeSubtype': '',
    }, requestedView: 'system');

    expect(nav.subtypesOf('system'), isEmpty);
    expect(nav.activeSubtypeFor('system'), '');
    // 不能把系统提醒的空值写成"继承 mypost"或反过来污染 mypost
    expect(nav.activeSubtypeFor('mypost'), 'post');
  });

  test('无子类型视图的组计数不会因子类型求和而残留', () {
    nav.syncFromPage({
      'views': views,
      'activeView': 'system',
      'hasSubBar': true,
      'subtypes': [],
      'activeSubtype': '',
    }, requestedView: 'system');

    // 没有子类型 → 调用方应回落到 NoticeBadgeController 的组级计数
    expect(nav.subtypeSum('system'), isNull);
  });
}

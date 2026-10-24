import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/notice_config.dart';
import 'package:mtbbs/pages/message/message_page.dart';

/// 消息页一级 Tab 排序：第 1 项固定，其余未读稳定前移。
void main() {
  const tabs = [
    NoticeType('pm', '我的消息'),
    NoticeType('mypost', '我的帖子'),
    NoticeType('interactive', '坛友互动'),
    NoticeType('system', '系统提醒'),
    NoticeType('app', '应用提醒'),
  ];

  List<String> ids(List<NoticeType> list) => [for (final t in list) t.id];

  test('第 1 项固定，其余未读稳定前移', () {
    final ordered = prioritizeUnreadTabs(
      tabs,
      (t) => t.id == 'interactive' || t.id == 'app',
    );
    expect(ids(ordered), ['pm', 'interactive', 'app', 'mypost', 'system']);
  });

  test('没有未读时保持原顺序', () {
    final ordered = prioritizeUnreadTabs(tabs, (_) => false);
    expect(ids(ordered), ids(tabs));
  });

  test('第 1 项即使有未读也不动', () {
    final ordered = prioritizeUnreadTabs(tabs, (t) => t.id == 'pm');
    expect(ids(ordered), ids(tabs));
  });

  test('全部未读时保持原顺序（稳定）', () {
    final ordered = prioritizeUnreadTabs(tabs, (_) => true);
    expect(ids(ordered), ids(tabs));
  });

  test('空列表 / 单项列表原样返回', () {
    expect(prioritizeUnreadTabs(const <NoticeType>[], (_) => true), isEmpty);
    final one = [tabs.first];
    expect(ids(prioritizeUnreadTabs(one, (_) => true)), ['pm']);
  });
}

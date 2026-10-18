import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/home/notice_unread/parse.dart';

void main() {
  group('未读提醒计数解析', () {
    test('原生 Discuz：#myprompt_menu', () {
      const html = '''
        <a href="home.php?mod=space&do=notice" id="myprompt" class="a showmenu new">提醒(3)</a>
        <ul id="myprompt_menu" class="p_pop">
          <li><a href="home.php?mod=space&do=pm" id="pm_ntc"><em class="prompt_news_1"></em>消息</a></li>
          <li><a href="home.php?mod=follow&do=follower"><em class="prompt_follower_2"></em>新听众(2)</a></li>
          <li><a href="home.php?mod=space&do=notice&view=mypost"><em class="notice_mypost"></em>我的帖子(1)</a></li>
          <li><a href="home.php?mod=space&do=notice&view=interactive"><em class="notice_interactive"></em>坛友互动(2)</a></li>
          <li><a href="home.php?mod=space&do=notice&view=system"><em class="notice_system"></em>系统提醒(3)</a></li>
        </ul>
      ''';

      final r = parseUnread(html, 200);

      expect(r['success'], true);
      expect(r['byGroup'], {'mypost': 1, 'interactive': 2, 'system': 3});
      expect(r['noticeTotal'], 6);
      expect(r['hasNewPm'], true);
      expect(r['follower'], 2);
    });

    test('克米 PC（MT）：计数在顶部导航链接的 title 里', () {
      const html = '''
        <a href="https://bbs.binmt.cc/home.php?mod=space&amp;do=pm" target="_blank">消息</a>
        <a href="https://bbs.binmt.cc/home.php?mod=space&amp;do=notice" target="_blank"
           title="2条新提醒" class="new">提醒<span></span></a>
        <a href="https://bbs.binmt.cc/home.php?mod=follow" target="_blank"
           title="1条我关注的" class="new">我关注的<span></span></a>
        <a href="https://bbs.binmt.cc/home.php?mod=space&amp;do=notice&amp;view=system" target="_blank"
           title="1条系统提醒" class="system">系统提醒<span></span></a>
        <a href="https://bbs.binmt.cc/home.php?mod=space&amp;do=notice&amp;view=interactive" target="_blank"
           title="1条坛友互动" class="interactive">坛友互动<span></span></a>
      ''';

      final r = parseUnread(html, 200);

      expect(r['success'], true);
      expect(r['byGroup'], {'system': 1, 'interactive': 1});
      expect(r['noticeTotal'], 2);
      expect(r['hasNewPm'], false);
      expect(r['follower'], 1);
    });

    test('克米 PC：我的帖子未读 + 未读私信', () {
      const html = '''
        <a href="home.php?mod=space&do=pm" title="1条新消息" class="new">消息</a>
        <a href="home.php?mod=space&do=notice" title="3条新提醒" class="new">提醒</a>
        <a href="home.php?mod=space&do=notice&view=mypost" title="1条我的帖子" class="mypost">我的帖子</a>
        <a href="home.php?mod=space&do=notice&view=system" title="1条系统提醒" class="system">系统提醒</a>
        <a href="home.php?mod=space&do=notice&view=interactive" title="1条坛友互动" class="interactive">坛友互动</a>
      ''';

      final r = parseUnread(html, 200);

      expect(r['byGroup'], {'mypost': 1, 'system': 1, 'interactive': 1});
      expect(r['noticeTotal'], 3);
      expect(r['hasNewPm'], true);
    });
  });
}

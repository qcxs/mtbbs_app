import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/forum/ranklist/parse.dart' as parse;

/// 排行榜响应统一是 XML CDATA 包裹的 PC 模板 HTML
String _xml(String html) =>
    '<?xml version="1.0" encoding="gbk"?>\n<root><![CDATA[$html]]></root>';

void main() {
  group('帖子排行（type=thread）', () {
    test('52pojie：表格只有 4 个 td 时也能取到统计列', () {
      // 52pojie 的列：icn / th / frm / by / 统计（th 不计入 td），共 4 个 td。
      // 回归点：旧实现要求 td 数量 >= 5，导致 count 恒为空。
      const html =
          '<table><tbody><tr class="th">'
          '<td class="icn">&nbsp;</td><th>主题</th>'
          '<td class="frm">版块</td><td class="by">作者</td><td width="60">热度</td>'
          '</tr></tbody><tr>'
          '<td class="icn"><img src="rank_1.gif" alt="1" /></td>'
          '<th><a href="thread-2134044-1-1.html">标题</a></th>'
          '<td class="frm"><a href="forum-16-1.html">『精品软件区』</a></td>'
          '<td class="by">'
          '<cite><a href="home.php?mod=space&amp;uid=1078332">liujkk</a></cite>'
          '<em>2026-10-24 17:10</em></td>'
          '<td><a href="thread-2134044-1-1.html" class="xi2">1105</a></td>'
          '</tr></table>';

      final r = parse.parseThreadResponse(_xml(html), 200);
      expect(r['success'], true);
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(1));
      expect(items.first['rank'], 1);
      expect(items.first['tid'], '2134044');
      expect(items.first['authorUid'], '1078332');
      expect(items.first['count'], '1105');
    });
  });

  group('用户排行（type=member）', () {
    const html =
        '<ul class="tb cl">'
        '<li class="a"><a href="misc.php?mod=ranklist&amp;type=member&amp;view=beauty">美女排行</a></li>'
        '<li><a href="misc.php?mod=ranklist&amp;type=member&amp;view=credit">积分排行</a></li>'
        '<li><a href="misc.php?mod=ranklist&amp;type=member&amp;view=post">发帖数排行</a></li>'
        '</ul>'
        '<dl class="bbda cl">'
        '<dd class="ranknum"><img src="rank_1.gif" alt="1" /></dd>'
        '<dd class="m avt"><a href="home.php?mod=space&amp;uid=242220">'
        '<img src="avatar_small.jpg" /></a></dd>'
        '<dt class="y"><p><a href="home.php?mod=space&amp;uid=242220">去串个门</a></p></dt>'
        '<dt><a href="home.php?mod=space&amp;uid=242220" style="color:#3c9d40;">qwe2913207</a></dt>'
        '<dd><p><font color="#3c9d40">武林翘楚</font> 积分数: 3206人气: 5159</p></dd>'
        '</dl>';

    test('52pojie：昵称链接是 home.php?mod=space&uid=，仍能解析', () {
      // 回归点：旧实现只认 space-uid-，52 的每一条都会被当成"无 uid/用户名"丢弃。
      final r = parse.parseMemberResponse(_xml(html), 200);
      expect(r['success'], true);
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(1));
      expect(items.first['rank'], 1);
      expect(items.first['uid'], '242220');
      expect(items.first['username'], 'qwe2913207');
      expect(items.first['userGroup'], '武林翘楚');
      expect(items.first['userGroupColor'], '#3c9d40');
      expect(items.first['statLine'], '积分数: 3206人气: 5159');
    });

    test('返回站点实际提供的子榜（无 view 的「竞价排行」不算）', () {
      final r = parse.parseMemberResponse(_xml(html), 200);
      final views = (r['views'] as List).cast<Map<String, dynamic>>();
      expect(views.map((e) => e['id']).toList(), ['beauty', 'credit', 'post']);
      expect(views.map((e) => e['label']).toList(), ['美女', '积分', '发帖数']);
    });
  });

  group('版块排行（type=forum）', () {
    test('站点关闭排行：返回提示文案，而不是空列表', () {
      const html =
          '<h3 class="flb"><em>提示信息</em></h3>'
          '<div class="c altw">'
          '<div class="alert_error">此排行功能已关闭'
          '<script type="text/javascript">if(typeof errorhandle_==\'function\') '
          "{errorhandle_('此排行功能已关闭', {});}</script>"
          '</div></div>';

      final r = parse.parseForumResponse(_xml(html), 200);
      expect(r['success'], false);
      expect(r['message'], '此排行功能已关闭');
    });
  });
}

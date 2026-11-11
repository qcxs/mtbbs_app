import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/home/follow/parse.dart' as follow;

/// 52pojie（PC 模板）真实 DOM 片段：
/// 用户链接是 `home.php?mod=space&uid=N`，不是克米的 `space-uid-N.html`。
/// 旧实现只认后者，导致整列 uid 为空、卡片点击跳 `/user/` 报错。
String _page(String lis) =>
    '<html><body><div id="ct"><div class="bm_c"><ul class="flw_ulist">$lis'
    '</ul></div></div></body></html>';

const _followingLi = '''
<li class="cl">
<a href="home.php?mod=space&amp;uid=879080" title="涛之雨" id="edit_avt" class="flw_avt" shref="home.php?mod=space&amp;uid=879080"><img src="https://avatar.52pojie.cn/data/avatar/000/87/90/80_avatar_small.jpg"></a>
<a id="a_followmod_879080" href="home.php?mod=spacecp&amp;ac=follow&amp;op=add&amp;hash=a86cd33b&amp;fuid=879080" onclick="ajaxget(this.href);doane(event);" class="flw_btn_fo">收听</a>
<h6 class="pbn xs2"><a href="home.php?mod=space&amp;uid=879080" title="涛之雨" class="xi2" c="1" shref="home.php?mod=space&amp;uid=879080">涛之雨</a>&nbsp;<span id="followbkame_879080" class="xg1 xs1 xw0"></span></h6>
<p><span class="xg1">最近动作: </span>pdf.js 通用pdf下载教程</p><p class="ptm xg1">
来自: 北京市 延庆县 &nbsp;听众: <a href="home.php?mod=follow&amp;do=follower&amp;uid=879080"><strong class="xi2" id="followernum_879080">2298</strong></a>人 &nbsp;
收听: <a href="home.php?mod=follow&amp;do=following&amp;uid=879080"><strong class="xi2">41</strong></a>人 &nbsp;
</p>
</li>
''';

const _followerLi = '''
<li class="cl">
<a href="home.php?mod=space&amp;uid=836614" title="gcz860524" id="edit_avt" class="flw_avt" c="1" shref="home.php?mod=space&amp;uid=836614"><img src="https://avatar.52pojie.cn/data/avatar/000/83/66/14_avatar_small.jpg"></a>
<a id="a_followmod_836614" href="home.php?mod=spacecp&amp;ac=follow&amp;op=add&amp;hash=a86cd33b&amp;fuid=836614" onclick="ajaxget(this.href);doane(event);" class="flw_btn_fo">收听</a>
<h6 class="pbn xs2"><a href="home.php?mod=space&amp;uid=836614" title="gcz860524" class="xi2" c="1" shref="home.php?mod=space&amp;uid=836614">gcz860524</a></h6>
<p class="ptm xg1">
听众: <a href="home.php?mod=follow&amp;do=follower&amp;uid=836614"><strong class="xi2" id="followernum_836614">2</strong></a>人 &nbsp;
收听: <a href="home.php?mod=follow&amp;do=following&amp;uid=836614"><strong class="xi2">4</strong></a>人
</p>
</li>
''';

void main() {
  group('关注/收听列表（52pojie 查询串 uid）', () {
    test('收听列表：uid / 昵称 / 头像 / 统计 / 最近动作', () {
      final r = follow.parseResponse(_page(_followingLi), 200);
      expect(r['success'], true);
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      expect(items, hasLength(1));
      final item = items.first;
      expect(item['uid'], '879080');
      expect(item['username'], '涛之雨');
      expect(item['avatar'], contains('avatar_small.jpg'));
      expect(item['followerCount'], '2298');
      expect(item['followingCount'], '41');
      expect(item['from'], '北京市 延庆县');
      expect(item['recentAction'], 'pdf.js 通用pdf下载教程');
    });

    test('听众列表：无最近动作也能解析出 uid', () {
      final r = follow.parseResponse(_page(_followerLi), 200);
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      final item = items.first;
      expect(item['uid'], '836614');
      expect(item['username'], 'gcz860524');
      expect(item['followerCount'], '2');
      expect(item['followingCount'], '4');
      expect(item.containsKey('recentAction'), false);
    });

    test('uid 取不到时不写入（UI 侧据此禁用跳转）', () {
      const brokenLi =
          '<li class="cl"><h6><a class="xi2" title="某人">某人</a></h6></li>';
      final r = follow.parseResponse(_page(brokenLi), 200);
      final items = (r['items'] as List).cast<Map<String, dynamic>>();
      expect(items.first.containsKey('uid'), false);
    });
  });
}

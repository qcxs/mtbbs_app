import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/parser/thread_parser.dart';
import 'package:mtbbs/core/app/site_store.dart';

void main() {
  setUpAll(() {
    SiteStore.instance.init();
  });
  group('Parser 工厂 - 自动检测', () {
    test('空 HTML 返回空列表', () {
      final result = parseThreadList('');
      expect(result, isEmpty);
    });

    test('无关 HTML 返回空列表', () {
      const html = '<html><body><p>一些无关内容</p></body></html>';
      final result = parseThreadList(html);
      expect(result, isEmpty);
    });

    test('detectThreadListParser 识别空文档', () {
      expect(detectThreadListParser(''), 'NoParser');
    });
  });

  group('Pattern A - 标准 Discuz 表格（52pojie PC）', () {
    // 模拟 52pojie 导读页的一个帖子行
    // <div id="threadlist" class="tl bm bmw">
    //   <table>
    //     <tbody id="normalthread_2118990">
    //       <tr>
    //         <td class="icn"><a><img src="folder_common.gif"></a></td>
    //         <th class="common">
    //           <a class="xst" href="thread-2118990-1-1.html">求一本三年级教辅</a>
    //           <span class="xi1">[悬赏 25 CB]</span>
    //           <a class="xi1">New</a>
    //         </th>
    //         <td class="by"><a href="forum-8-1.html">『悬赏问答区』</a></td>
    //         <td class="by">
    //           <cite><a href="space-uid-1623088.html">liuhelee</a></cite>
    //           <em><span class="xi1">2026-7-24 00:25</span></em>
    //         </td>
    //         <td class="num"><a class="xi2">1</a><em>16</em></td>
    //         <td class="by">
    //           <cite><a>iShareOne</a></cite>
    //           <em><a>2026-7-24 01:57</a></em>
    //         </td>
    //       </tr>
    //     </tbody>
    //   </table>
    // </div>
    test('解析单行表格帖子', () {
      const html =
          ''
          '<div id="threadlist" class="tl bm bmw">'
          '<table>'
          '<tbody id="normalthread_2118990">'
          '<tr>'
          '<td class="icn"><a><img src="folder_common.gif"></a></td>'
          '<th class="common">'
          '<a class="xst" href="thread-2118990-1-1.html">求一本三年级教辅</a>'
          '<span class="xi1">[悬赏 25 CB]</span>'
          '<a class="xi1">New</a>'
          '</th>'
          '<td class="by"><a href="forum-8-1.html">『悬赏问答区』</a></td>'
          '<td class="by">'
          '<cite><a href="space-uid-1623088.html">liuhelee</a></cite>'
          '<em><span class="xi1">2026-7-24 00:25</span></em>'
          '</td>'
          '<td class="num"><a class="xi2">1</a><em>16</em></td>'
          '<td class="by">'
          '<cite><a>iShareOne</a></cite>'
          '<em><a>2026-7-24 01:57</a></em>'
          '</td>'
          '</tr>'
          '</tbody>'
          '</table>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '求一本三年级教辅');
      expect(result[0].threadId, 2118990);
      expect(result[0].nickname, 'liuhelee');
      expect(result[0].boardName, '『悬赏问答区』');
      expect(result[0].comments, 1);
      expect(result[0].views, 16);
      expect(result[0].time, '2026-7-24 00:25');
    });

    test('th.new 标题列（52poujie 板块页有新回复的帖子）', () {
      // 52poujie 板块页：有未读新回复的帖子 th.class = "new" 而非 "common"
      const html =
          ''
          '<div id="threadlist" class="tl bm bmw">'
          '<table id="threadlisttableid">'
          '<tbody id="normalthread_1702042">'
          '<tr>'
          '<td class="icn"><a><img src="folder_new.gif"></a></td>'
          '<th class="new">'
          '<a href="thread-1702042-1-1.html" class="xst">这是一个有新回复的帖子</a>'
          '</th>'
          '<td class="by"><cite><a href="space-uid-1.html">Hmily</a></cite><em><span>1分钟前</span></em></td>'
          '<td class="num"><a class="xi2">65</a><em>4543</em></td>'
          '<td class="by"><cite><a>allspark</a></cite><em><a>2026-11-29 14:29</a></em></td>'
          '</tr>'
          '</tbody>'
          '</table>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '这是一个有新回复的帖子');
      expect(result[0].threadId, 1702042);
      expect(result[0].nickname, 'Hmily');
      expect(result[0].comments, 65);
      expect(result[0].views, 4543);
      expect(result[0].time, '1分钟前');
    });

    test('多行表格帖子', () {
      const html =
          ''
          '<div id="threadlist" class="tl bm bmw">'
          '<table>'
          '<tbody id="normalthread_100">'
          '<tr>'
          '<td class="icn"><a><img src="folder_common.gif"></a></td>'
          '<th class="common"><a class="xst" href="thread-100-1-1.html">帖子A</a></th>'
          '<td class="by"><a href="forum-1-1.html">版块A</a></td>'
          '<td class="by"><cite><a>user1</a></cite><em><span>time1</span></em></td>'
          '<td class="num"><a class="xi2">5</a><em>100</em></td>'
          '<td class="by"><cite><a>user2</a></cite><em><a>time2</a></em></td>'
          '</tr>'
          '</tbody>'
          '<tbody id="normalthread_101">'
          '<tr>'
          '<td class="icn"><a><img src="folder_common.gif"></a></td>'
          '<th class="common"><a class="xst" href="thread-101-1-1.html">帖子B</a></th>'
          '<td class="by"><a href="forum-2-1.html">版块B</a></td>'
          '<td class="by"><cite><a>user3</a></cite><em><span>time3</span></em></td>'
          '<td class="num"><a class="xi2">3</a><em>50</em></td>'
          '<td class="by"><cite><a>user4</a></cite><em><a>time4</a></em></td>'
          '</tr>'
          '</tbody>'
          '</table>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 2);
      expect(result[0].title, '帖子A');
      expect(result[0].threadId, 100);
      expect(result[1].title, '帖子B');
      expect(result[1].threadId, 101);
    });
  });

  group('Pattern B - 克米模板卡片（MT论坛 Mobile）', () {
    // 模拟 MT论坛 移动版的一个帖子卡片
    test('解析完整卡片帖子（含头像、标题、摘要、图片、统计）', () {
      const html =
          ''
          '<ul>'
          '<li class="forumlist_li comiis_znalist bg_f b_t b_b comiis_list_readimgs">'
          '<div class="forumlist_li_top cl">'
          '<a class="wblist_tximg" href="space-uid-117257.html"><img class="top_tximg" src="avatar.jpg"></a>'
          '<h2>'
          '<a class="top_user">smmyou</a>'
          '<span class="top_lev bg_a f_f">Lv.6</span>'
          '</h2>'
          '<div class="forumlist_li_time"><span class="f_d">14分钟前</span></div>'
          '</div>'
          '<div class="mmlist_li_box cl">'
          '<h2><a href="https://bbs.binmt.cc/thread-169736-1-1.html">不知道是不是bug</a></h2>'
          '<div class="list_body cl"><a class="f_b">现代MT搭配AI真的好强大，以下是一些问题...</a></div>'
          '<a><div class="comiis_pyqlist_imgs"><ul><li><img src="https://cdn.example.com/img1.jpg"></li><li><img src="img2.jpg"></li></ul></div></a>'
          '</div>'
          '<div class="comiis_xznalist_bk cl">'
          '<a class="bg_g f_0">建议反馈</a>'
          '</div>'
          '<div class="comiis_xznalist_bottom cl">'
          '<ul><li><span class="comiis_tm">5</span></li><li><span class="comiis_tm">6</span></li><li><span class="comiis_tm">40</span></li></ul>'
          '</div>'
          '</li>'
          '<li class="forumlist_li comiis_znalist bg_f b_t b_b">'
          '<div class="forumlist_li_top cl">'
          '<a class="wblist_tximg" href="space-uid-10063.html"><img src="avatar2.jpg"></a>'
          '<h2>'
          '<a class="top_user">jonepjxh</a>'
          '<span class="top_lev">Lv.5</span>'
          '</h2>'
          '<div class="forumlist_li_time"><span>1小时前</span></div>'
          '</div>'
          '<div class="mmlist_li_box cl">'
          '<h2><a href="https://bbs.binmt.cc/thread-169735-1-1.html">万能服务器Servers Ultimate Pro</a></h2>'
          '</div>'
          '<div class="comiis_xznalist_bottom cl">'
          '<ul><li>0</li><li>3</li><li>18</li></ul>'
          '</div>'
          '</li>'
          '</ul>';
      final result = parseThreadList(html);
      expect(result.length, 2);

      // 第一个帖子
      expect(result[0].nickname, 'smmyou');
      expect(result[0].level, 'Lv.6');
      expect(result[0].time, '14分钟前');
      expect(result[0].uid, 117257);
      expect(result[0].title, '不知道是不是bug');
      expect(result[0].threadId, 169736);
      expect(result[0].summary, '现代MT搭配AI真的好强大，以下是一些问题...');
      expect(result[0].boardName, '建议反馈');
      expect(result[0].likes, 5);
      expect(result[0].comments, 6);
      expect(result[0].views, 40);
      expect(result[0].images, isNotNull);
      expect(result[0].images!.length, 2);
      expect(result[0].images![0], startsWith('http'));

      // 第二个帖子
      expect(result[1].nickname, 'jonepjxh');
      expect(result[1].title, '万能服务器Servers Ultimate Pro');
      expect(result[1].threadId, 169735);
      expect(result[1].views, 18);
    });
  });

  group('Pattern C - 克米模板表格混合（MT论坛 PC 板块）', () {
    test('解析 comiis_postlist 结构', () {
      const html =
          ''
          '<table>'
          '<tbody id="normalthread_169736">'
          '<tr>'
          '<td>'
          '<div class="comiis_postlist cl">'
          '<div class="comiis_listtx">'
          '<a href="space-uid-117257.html"><img src="avatar.jpg"></a>'
          '</div>'
          '<h2 class="cl">'
          '<span class="comiis_common">'
          '<a href="thread-169736-1-1.html">不知道是不是bug</a>'
          '<img src="image_s.gif" alt="attach_img">'
          '</span>'
          '</h2>'
          '<p>'
          '<span class="y">'
          '<em class="km_view">47</em>'
          '<em class="km_reply"><a>7</a></em>'
          '</span>'
          '<em class="km_user"><a href="space-uid-117257.html">smmyou</a></em>'
          '<em><span class="xi1">16分钟前</span> 发表在</em>'
          '<em><a href="forum-38-1.html">BUG反馈</a></em>'
          '<em>最后回复于 <a>25秒前</a></em>'
          '</p>'
          '</div>'
          '</td>'
          '</tr>'
          '</tbody>'
          '</table>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '不知道是不是bug');
      expect(result[0].threadId, 169736);
      expect(result[0].nickname, 'smmyou');
      expect(result[0].uid, 117257);
      expect(result[0].boardName, 'BUG反馈');
      expect(result[0].comments, 7);
      expect(result[0].views, 47);
      expect(result[0].time, '16分钟前');
    });
  });

  group('Pattern D - 空间帖子表格（我的帖子）', () {
    test('解析 MT 论坛的我的帖子行', () {
      const html =
          ''
          '<div class="tl">'
          '<form>'
          '<table>'
          '<tr class="th">'
          '<td class="icn">&nbsp;</td>'
          '<th>主题</th>'
          '<td class="frm">版块/群组</td>'
          '<td class="num">回复/查看</td>'
          '<td class="by"><cite>最后发帖</cite></td>'
          '</tr>'
          '<tr>'
          '<td class="icn"><a><img src="folder_common.gif"></a></td>'
          '<th>'
          '<a href="thread-169295-1-1.html">使用Flutter开发的MT论坛app</a>'
          '<img src="image_s.gif" alt="图片附件">'
          '<span class="tps">...分页...</span>'
          '</th>'
          '<td><a href="forum-42-1.html" class="xg1">编程开发</a></td>'
          '<td class="num"><a class="xi2">151</a><em>1457</em></td>'
          '<td class="by">'
          '<cite><a>228805664</a></cite>'
          '<em><a>昨天 02:55</a></em>'
          '</td>'
          '</tr>'
          '<tr>'
          '<td class="icn"><a><img src="folder_common.gif"></a></td>'
          '<th><a href="thread-169285-1-1.html">论坛积分公式详情</a></th>'
          '<td><a href="forum-40-1.html" class="xg1">休闲灌水</a></td>'
          '<td class="num"><a class="xi2">30</a><em>426</em></td>'
          '<td class="by"><cite><a>青春向上</a></cite><em><a>6天前</a></em></td>'
          '</tr>'
          '</table>'
          '</form>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 2);

      // 第一行
      expect(result[0].title, '使用Flutter开发的MT论坛app');
      expect(result[0].threadId, 169295);
      expect(result[0].boardName, '编程开发');
      expect(result[0].comments, 151);
      expect(result[0].views, 1457);
      expect(result[0].nickname, isNull);
      expect(result[0].time, '昨天 02:55');

      // 第二行
      expect(result[1].title, '论坛积分公式详情');
      expect(result[1].threadId, 169285);
      expect(result[1].boardName, '休闲灌水');
      expect(result[1].comments, 30);
      expect(result[1].views, 426);
    });

    test('解析 52pj 的我的帖子行', () {
      const html =
          ''
          '<div class="tl">'
          '<form><table>'
          '<tr class="th">'
          '<td class="icn">&nbsp;</td><th>主题</th>'
          '<td class="frm">版块/群组</td>'
          '<td class="num">回复/查看</td>'
          '<td class="by"><cite>最后发帖</cite></td>'
          '</tr>'
          '<tr>'
          '<td class="icn"><a><img src="pin_3.gif" alt="全局置顶"></a></td>'
          '<th><a href="thread-2117334-1-1.html">吾爱破解论坛网络诊断修复工具 v3.1</a></th>'
          '<td><a href="forum-13-1.html" class="xg1">『站点公告』</a></td>'
          '<td class="num"><a class="xi2">292</a><em>7850</em></td>'
          '<td class="by"><cite><a>a312167598</a></cite><em><a>2026-7-24 10:13</a></em></td>'
          '</tr>'
          '</table></form>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '吾爱破解论坛网络诊断修复工具 v3.1');
      expect(result[0].threadId, 2117334);
      expect(result[0].boardName, '『站点公告』');
      expect(result[0].comments, 292);
      expect(result[0].views, 7850);
      expect(result[0].nickname, isNull);
      expect(result[0].time, '2026-7-24 10:13');
    });

    test('最近回复页：标题链接含 ptid=，分页 .tps 不被误解析', () {
      // 最近回复的标题链接是 goto=findpost&ptid=169723，而非 thread-169723
      // 分页 .tps 内的 thread- 链接不应被当成标题
      const html =
          ''
          '<div class="tl">'
          '<form><table>'
          '<tr class="th">'
          '<td class="icn">&nbsp;</td><th>帖子</th>'
          '<td class="frm">版块/群组</td>'
          '<td class="num">回复/查看</td>'
          '<td class="by"><cite>最后发帖</cite></td>'
          '</tr>'
          '<tr class="bw0_all">'
          '<td class="icn"><a><img src="folder_lock.gif"></a></td>'
          '<th>'
          '<a href="forum.php?mod=redirect&goto=findpost&ptid=169723&pid=" target="_blank">2026年7月24日签到记录贴</a>'
          '<span class="tps">... <a href="thread-169723-1-1.html">1</a> <a href="thread-169723-2-1.html">2</a> .. <a href="thread-169723-123-1.html">123</a></span>'
          '</th>'
          '<td><a href="forum-69-1.html" class="xg1">签到记录</a></td>'
          '<td class="num"><a class="xi2">1844</a><em>1844</em></td>'
          '<td class="by"><cite><a>玖の君</a></cite><em><a>23秒前</a></em></td>'
          '</tr>'
          '</table></form>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '2026年7月24日签到记录贴');
      expect(result[0].threadId, 169723);
      expect(result[0].boardName, '签到记录');
      expect(result[0].comments, 1844);
      expect(result[0].views, 1844);
      expect(result[0].nickname, isNull);
    });
  });

  group('多模板混合 - 工厂自动选择', () {
    test('同一 HTML 包含三种特征时，ComiisCardParser 优先', () {
      // 同时包含 comiis_znalist、th.common、comiis_postlist
      const html =
          ''
          '<div id="threadlist">'
          '<ul>'
          '<li class="forumlist_li comiis_znalist">'
          '<div class="forumlist_li_top cl"><h2><a class="top_user">user</a></h2><div class="forumlist_li_time"><span>time</span></div></div>'
          '<div class="mmlist_li_box cl"><h2><a href="thread-1-1-1.html">卡片标题</a></h2></div>'
          '<div class="comiis_xznalist_bottom cl"><ul><li>0</li><li>1</li><li>2</li></ul></div>'
          '</li>'
          '</ul>'
          '<table><tbody id="normalthread_2"><tr>'
          '<th class="common"><a class="xst" href="thread-2-1-1.html">表格标题</a></th>'
          '<td class="by">版块</td><td class="by"><cite><a>author</a></cite><em>time</em></td>'
          '<td class="num"><a>0</a><em>0</em></td><td class="by"><cite></cite><em></em></td>'
          '</tr></tbody></table>'
          '</div>';
      final result = parseThreadList(html);
      expect(result.length, 1);
      expect(result[0].title, '卡片标题');
    });

    test('无有效特征时返回空', () {
      const html = '<html><body><p>无效内容</p></body></html>';
      final result = parseThreadList(html);
      expect(result, isEmpty);
    });
  });
}

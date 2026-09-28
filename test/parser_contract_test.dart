import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/forum/viewthread/detail/parse.dart' as detail;
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/models/thread_detail.dart';

/// 站点样本路径 —— **站点数据，不进版本库**。
///
/// 落在 `build/fixtures/`（`/build/` 已被根 .gitignore 覆盖）；仓库里只保留
/// "从哪个 URL 抓"这一份信息，需要时用 [captureCommand] 重新抓。
const fixturePath = 'build/fixtures/mt_thread_detail.html';

/// 样本来源（仓库里唯一记录的站点信息——只是一个地址，不含页面内容）
const fixtureSourceUrl =
    'https://bbs.binmt.cc/forum.php?mod=viewthread&tid=170313&page=1';

/// 生成样本的命令
const captureCommand =
    'flutter test tool/capture_fixture_test.dart --dart-define=tid=170313';

/// 样本缺失时的跳过原因（null = 样本存在，正常执行）。
///
/// 新克隆的仓库、或跑过 `flutter clean` 之后，本地不会有站点样本。
/// 这时相关用例应**跳过**并提示生成命令，而不是报失败。
final fixtureSkipReason = File(fixturePath).existsSync()
    ? null
    : '缺少站点样本（站点数据不进版本库）—— 先运行 `$captureCommand` 生成；'
          '来源 $fixtureSourceUrl';

/// 解析契约测试
///
/// 用**冻结的真实页面样本**（[fixturePath]）锁定「解析器 ↔ 页面结构」的契约：
/// 样本不变则结果必须不变；页面改版时用 [captureCommand] 重抓，失败处就是
/// 「页面到底哪变了」的答案。
///
/// 断言原则：断言语义（字段非空、含关键 BBCode 标记），不断言全文相等
/// （页面含统计/广告等噪声，全文比对必然脆弱）。
void main() {
  setUpAll(() {
    SiteStore.instance.init();
  });

  group('帖子详情契约（真实样本 / PC 表格模板）', () {
    late Map<String, dynamic> result;

    setUpAll(() {
      SiteStore.instance.init();
      if (fixtureSkipReason != null) return; // 样本缺失：本组用例会跳过
      result = detail.parseResponse(File(fixturePath).readAsStringSync(), 200);
    });

    test('整体解析成功', () {
      expect(result['success'], true);
    }, skip: fixtureSkipReason);

    test('帖子基本信息不为空', () {
      expect(result['tid'], '170313');
      expect(result['title'], isNotEmpty);
      expect(result['formhash'], isNotEmpty);
      expect(result['currentPage'], 1);
    }, skip: fixtureSkipReason);

    test('楼主帖关键字段不为空', () {
      final main = result['mainPost'] as Map<String, dynamic>;
      expect(main['pid'], isNotEmpty);
      expect(main['username'], isNotEmpty);
      expect(main['uid'], isNotEmpty);
      expect(main['usergroup'], isNotEmpty);
      expect(main['postTime'], isNotEmpty);
      expect(main['ipLocation'], isNotEmpty);
      expect(main['bbcode'], isNotEmpty);
    }, skip: fixtureSkipReason);

    test('楼主帖正文保留 BBCode 语义（颜色 / 编辑记录 appdata）', () {
      final bbcode = result['mainPost']['bbcode'] as String;
      expect(bbcode, contains('[color=#'));
      expect(bbcode, contains('[appdata]{"type":"pstatus"'));
    }, skip: fixtureSkipReason);

    test('楼层号按 postnum 解析：楼主=1、沙发=2、椅子=3', () {
      expect(result['mainPost']['floor'], 1);
      final posts = result['posts'] as List;
      // 样本冻结，楼层数固定；数量变化即"解析器丢楼"的回归信号
      expect(posts, hasLength(14));
      expect(posts.first['floor'], 2);
      expect(posts.first['floorLabel'], '沙发');
      expect(posts[1]['floor'], 3);
      expect(posts[1]['floorLabel'], '椅子');
    }, skip: fixtureSkipReason);

    test('每个楼层都有 pid 与作者', () {
      final posts = result['posts'] as List;
      for (final p in posts) {
        final m = p as Map<String, dynamic>;
        expect(m['pid'], isNotEmpty);
        expect(m['username'], isNotEmpty);
      }
    }, skip: fixtureSkipReason);

    test('健康自检无告警：关键字段都没有丢', () {
      final health = result['_health'] as Map<String, dynamic>;
      expect(health['parser'], 'discuz_table');
      expect(health['missing'], isEmpty);
    }, skip: fixtureSkipReason);
  });

  // 以下两组用内联 HTML，不依赖站点样本，任何时候都应执行。
  group('页面结构变更时不再静默失败', () {
    test('第 1 页解析不到帖子 table → 明确报错，而不是返回空列表', () {
      // 只有标题、#postlist 整体消失（模拟选择器失效）
      const broken =
          '<html><body>'
          '<a href="forum.php?mod=viewthread&tid=169000">x</a>'
          '<div id="thread_subject">标题还在</div>'
          '</body></html>';
      final r = detail.parseResponse(broken, 200, page: 1);
      expect(r['success'], false);
      // 区别于「tid 也取不到」的兜底文案
      expect(r['message'], contains('页面结构'));
    });

    test('第 2 页没有帖子 → 仍算成功（页码越界属正常）', () {
      const empty =
          '<html><body>'
          '<a href="forum.php?mod=viewthread&tid=169000">x</a>'
          '<div id="thread_subject">标题</div>'
          '<div id="postlist"></div>'
          '</body></html>';
      final r = detail.parseResponse(empty, 200, page: 2);
      expect(r['success'], true);
      expect(r['posts'], isEmpty);
    });
  });

  group('项级失败隔离（一个楼层不拖垮整页）', () {
    test('局部结构缺失的楼层不影响整页解析', () {
      const html =
          '<html><body>'
          '<a href="forum.php?mod=viewthread&tid=169000">x</a>'
          '<div id="thread_subject">标题</div>'
          '<div id="postlist">'
          // 第 1 楼：结构完整
          '<table id="pid1"><tr>'
          '<td class="pls"><div class="pi"><div class="authi">'
          '<a href="home.php?mod=space&uid=1">甲</a>'
          '</div></div></td>'
          '<td class="plc"><a id="postnum1"><em>楼主</em></a>'
          '<div class="t_fsz"><table><tr>'
          '<td class="t_f" id="postmessage_1">正文一</td>'
          '</tr></table></div>'
          '</td>'
          '</tr></table>'
          // 第 2 楼：td.pls / td.plc 整块缺失
          '<table id="pid2"><tr><td>结构缺失</td></tr></table>'
          '</div></body></html>';
      final r = detail.parseResponse(html, 200, page: 1);
      expect(r['success'], true);
      expect(r['mainPost']['bbcode'], '正文一');
      // 坏楼层仍在列表里（保住页形），只是字段全空
      expect(r['posts'] as List, hasLength(1));
    });

    test('降级占位能安全构造 PostItem，楼层号仍可读', () {
      final post = PostItem.fromMap({
        'pid': 'degraded-3',
        'floor': 3,
        'bbcode': '',
        'degraded': true,
      });
      expect(post.degraded, true);
      expect(post.floorText, '#3');
    });
  });
}

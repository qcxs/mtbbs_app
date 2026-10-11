/// 只读场景：会话状态 / 导读 / 版块 / 帖子 / 用户 / 好友 / 消息 / 我的主题
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mtbbs/api/forum/darkroom/export.dart' as darkroom_api;
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forum_api;
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/api/forum/misc/export.dart' as forum_nav_api;
import 'package:mtbbs/api/forum/online/export.dart' as online_api;
import 'package:mtbbs/api/forum/ranklist/export.dart' as ranklist_api;
import 'package:mtbbs/api/forum/rss/export.dart' as rss_api;
import 'package:mtbbs/api/forum/search/export.dart' as search_api;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as thread_api;
import 'package:mtbbs/api/forum/viewthread/viewpid/export.dart' as viewpid_api;
import 'package:mtbbs/api/group/groupindex/export.dart' as group_api;
import 'package:mtbbs/api/home/friend/export.dart' as friend_api;
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/api/home/follow/export.dart' as follow_api;
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/api/home/mythread/export.dart' as mythread_api;
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/api/home/wall/export.dart' as wall_api;
import 'package:mtbbs/api/home/notice/export.dart' as notice_api;
import 'package:mtbbs/api/home/notice_unread/export.dart' as unread_api;
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;
import 'package:mtbbs/api/site/cdn/export.dart' as cdn_api;
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';
import 'scenario_types.dart';

/// 只读场景注册表（命令名 → 场景）
final Map<String, ApiScenario> readScenarios = {
  'session.list': ApiScenario(
    desc: '查看本机已持久化的登录状态（游客 Cookie + 各账号 Cookie）',
    params: {},
    run: (a) async {
      final host = SiteStore.instance.host;
      final dir = await AppPaths.cookiesDirForHost(host);
      return {
        'host': host,
        'baseUrl': SiteStore.instance.baseUrl,
        'cookieDir': dir,
        ...await _scanCookieDir(dir),
      };
    },
  ),
  'session.status': ApiScenario(
    desc: '查看当前会话用户状态（uid/用户名/积分/用户组），uid=0 表示未登录',
    params: {'account': '登录账号名（可空=游客）'},
    run: (a) async {
      final r = await userstatus_api.fetch(ApiService().dio);
      r['account'] = ApiService().activeAccount ?? '(游客)';
      return r;
    },
  ),
  'site.cdn': ApiScenario(
    desc: '自动识别站点 CDN（读 PC 帮助页内联的 STATICURL；失败回退论坛首页）',
    params: {},
    run: (a) => cdn_api.fetchSiteCdn(ApiService().dio),
  ),
  'guide.list': ApiScenario(
    desc: '导读列表（默认移动端 UA）',
    params: {
      'view': 'newthread/newreply/digest（默认 newthread）',
      'page': '页码（默认 1）',
    },
    mobileSupported: true, // 导读：移动卡片 / PC 表格
    run: (a) => guide_api.getThreadList(
      ApiService().dio,
      view: a['view'] ?? 'newthread',
      page: intArg(a, 'page', 1),
    ),
  ),
  'forum.list': ApiScenario(
    desc: '版块帖子列表（默认移动端 UA）',
    params: {
      'fid': '*版块 ID',
      'orderby': 'lastpost/dateline/replies/views（默认空）',
      'filter': 'digest/recommend/...（默认空）',
      'page': '页码（默认 1）',
    },
    mobileSupported: true, // 版块列表：移动克米 / PC 表格，解析器工厂两套通吃
    run: (a) => forum_api.getForumThreads(
      ApiService().dio,
      fid: a['fid'] ?? '',
      orderby: a['orderby'] ?? '',
      filter: a['filter'] ?? '',
      page: intArg(a, 'page', 1),
    ),
  ),
  'ranklist.thread': ApiScenario(
    desc: '帖子排行（PC UA；type=thread）',
    params: {
      'view': 'replies/views/sharetimes/favtimes/heats（默认 heats）',
      'orderby': 'thisweek/thismonth/today/all（默认 thisweek）',
    },
    run: (a) => ranklist_api.getThreadRanklist(
      ApiService().dio,
      view: a['view'] ?? 'heats',
      orderby: a['orderby'] ?? 'thisweek',
    ),
  ),
  'ranklist.member': ApiScenario(
    desc: '用户排行（PC UA；type=member）',
    params: {
      'view':
          'beauty/handsome/credit/friendnum/invite/post/onlinetime（默认 beauty）',
    },
    run: (a) => ranklist_api.getMemberRanklist(
      ApiService().dio,
      view: a['view'] ?? 'beauty',
    ),
  ),
  'ranklist.forum': ApiScenario(
    desc: '版块排行（PC UA；type=forum）',
    params: {'view': 'threads/posts/today（默认 threads）'},
    run: (a) => ranklist_api.getForumRanklist(
      ApiService().dio,
      view: a['view'] ?? 'threads',
    ),
  ),
  'online.list': ApiScenario(
    desc: '在线会员列表与统计（PC 专属页，移动模板通常无实现）',
    params: {},
    run: (a) => online_api.fetchOnlineUsers(ApiService().dio),
  ),
  'rss.list': ApiScenario(
    desc: '站点 RSS 最新条目（标题 / 链接 / 发布时间）',
    params: {},
    run: (a) => rss_api.getRssFeed(ApiService().dio),
  ),
  'darkroom.list': ApiScenario(
    desc: '小黑屋（违规用户与处理记录；PC 专属页），cid=分类（可空）',
    params: {'cid': '分类 ID（可空）'},
    run: (a) => darkroom_api.getList(ApiService().dio, cid: a['cid'] ?? ''),
  ),
  'forum.nav': ApiScenario(
    desc: '论坛导航（版块/子版块列表；App 与 MCP list_forums 的站点缓存即来自它）',
    params: {},
    run: (a) => forum_nav_api.fetchForumNav(ApiService().dio),
  ),
  'group.index': ApiScenario(
    desc: '圈子首页（推荐圈子 + 圈子分类 gid + 积分排行；桌面 UA，游客可访问）',
    params: {},
    run: (a) => group_api.fetchGroupIndex(ApiService().dio),
  ),
  'group.category': ApiScenario(
    desc: '圈子分类下的圈子列表（分页；gid 来自 group.index 的 categories）',
    params: {'gid': '*分类 ID', 'page': '页码（默认 1）'},
    run: (a) => group_api.fetchCategoryGroups(
      ApiService().dio,
      gid: a['gid'] ?? '',
      page: intArg(a, 'page', 1),
    ),
  ),
  'search.list': ApiScenario(
    desc: '站内搜索帖子列表（search.php；UA 随「浏览模式」→ 移动克米 / 桌面 Discuz）',
    params: {
      'kw': '*搜索关键词',
      'page': '页码（默认 1）',
      'searchid': '搜索结果会话 id（翻页用；空=发起新搜索）',
    },
    mobileSupported: true, // 搜索：移动克米 / 桌面 Discuz，两套解析器
    run: (a) => search_api.searchThreads(
      ApiService().dio,
      keyword: a['kw'] ?? '',
      page: intArg(a, 'page', 1),
      searchId: (a['searchid'] ?? '').isEmpty ? null : a['searchid'],
    ),
  ),
  'thread.detail': ApiScenario(
    desc: '帖子详情（楼主 + 各楼层，数据量大会自动截断）',
    params: {'tid': '*帖子 ID', 'page': '页码（默认 1）', 'authorid': '只看作者（可空）'},
    run: (a) => thread_api.getThreadDetail(
      ApiService().dio,
      tid: a['tid'] ?? '',
      page: intArg(a, 'page', 1),
      authorid: (a['authorid'] ?? '').isEmpty ? null : a['authorid'],
    ),
  ),
  'post.byPid': ApiScenario(
    desc: '按 pid 取单个楼层（viewpid 接口；回复成功后追加新楼用的就是它）',
    params: {'tid': '*帖子 ID', 'pid': '*楼层 ID（viewpid）'},
    run: (a) => viewpid_api.getPostByPid(
      ApiService().dio,
      tid: a['tid'] ?? '',
      viewpid: a['pid'] ?? '',
    ),
  ),
  'post.findTid': ApiScenario(
    desc: '按 pid 解析所在帖子 tid（findpost 跳转；供 App 内帖子页定位）',
    params: {'pid': '*楼层 ID'},
    run: (a) {
      final pid = a['pid'] ?? '';
      if (pid.isEmpty) throw Exception('缺少必填参数 pid');
      return viewpid_api.resolveTidByPid(ApiService().dio, pid: pid);
    },
  ),
  'user.info': ApiScenario(
    desc: '用户空间信息（uid/用户名 二选一，空则查自己）',
    params: {'uid': '用户 ID（可空）', 'username': '用户名（可空）'},
    mobileSupported: true, // 用户空间：克米移动 ↔ 标准 PC，parse 按 DOM 分流
    run: (a) => space_api.getUserProfile(
      ApiService().dio,
      uid: a['uid'] ?? '',
      username: a['username'] ?? '',
    ),
  ),
  'wall.list': ApiScenario(
    desc: '用户留言板（uid 空=自己；仅 PC 模板，含 formhash/canPost）',
    params: {'uid': '用户 ID（可空=自己）', 'page': '页码（默认 1）'},
    run: (a) => wall_api.getWall(
      ApiService().dio,
      uid: a['uid'] ?? '',
      page: intArg(a, 'page', 1),
    ),
  ),
  'friend.list': ApiScenario(
    desc: '好友列表（uid 空=自己的好友，指定 uid=查看该用户）',
    params: {'uid': '用户 ID（可空=自己）', 'page': '页码（默认 1）'},
    run: (a) => friend_api.getFriendList(
      ApiService().dio,
      uid: (a['uid'] ?? '').isEmpty ? '' : (a['uid'] ?? ''),
      page: intArg(a, 'page', 1),
    ),
  ),
  'follow.list': ApiScenario(
    desc: '关注/粉丝列表（type=following 关注|follower 粉丝，uid 空=自己）',
    params: {
      'type': '*following/follower',
      'uid': '用户 ID（可空=自己）',
      'page': '页码（默认 1）',
    },
    run: (a) => follow_api.getFollowList(
      ApiService().dio,
      type: a['type'] ?? 'following',
      uid: (a['uid'] ?? '').isEmpty ? '' : (a['uid'] ?? ''),
      page: intArg(a, 'page', 1),
    ),
  ),
  'favorite.list': ApiScenario(
    desc: '收藏列表（需登录，返回含 favid/tid/标题，供删除用）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => favorite_api.fetchFavorites(
      ApiService().dio,
      page: intArg(a, 'page', 1),
    ),
  ),
  'credit.log': ApiScenario(
    desc: '积分记录（当前登录用户的积分变更记录，需登录）',
    params: {
      'page': '页码（默认 1，从最新一页起算）',
      'exttype': '积分类型（1=好评 / 2=金币 / 3=信誉，空/0=不限）',
      'income': '收支（1=收入 / -1=支出，空/0=不限）',
      'optype': '操作类型（如 PRC=帖子被评分 / RSC=帖子评分，空=不限）',
      'starttime': '起始日期（YYYY-MM-DD，可空）',
      'endtime': '结束日期（YYYY-MM-DD，可空）',
    },
    needsLogin: true,
    run: (a) => credit_api.fetchCreditLog(
      ApiService().dio,
      page: intArg(a, 'page', 1),
      exttype: (a['exttype'] ?? '').isEmpty ? '0' : a['exttype']!,
      income: (a['income'] ?? '').isEmpty ? '0' : a['income']!,
      optype: a['optype'] ?? '',
      starttime: a['starttime'] ?? '',
      endtime: a['endtime'] ?? '',
    ),
  ),
  'message.system': ApiScenario(
    desc: '系统提醒列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) =>
        notice_api.getNoticeList(ApiService().dio, page: intArg(a, 'page', 1)),
  ),
  'message.manage': ApiScenario(
    desc: '管理工作提醒列表（需登录；管理员/版主为待办，普通用户仅举报处理反馈）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => notice_api.getNoticeList(
      ApiService().dio,
      page: intArg(a, 'page', 1),
      view: 'manage',
    ),
  ),
  'message.interactive': ApiScenario(
    desc:
        '坛友互动提醒列表（需登录；type 见 noticeConfig：poke/friend/wall/comment/click/sharenotice）',
    params: {'type': '子类型（默认 wall=留言）', 'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => notice_api.getNoticeList(
      ApiService().dio,
      page: intArg(a, 'page', 1),
      view: 'interactive',
      type: (a['type'] ?? '').isEmpty ? 'wall' : a['type']!,
    ),
  ),
  'notice.counts': ApiScenario(
    desc: '未读提醒计数（非破坏性：只读页面 header，不打开通知页、不改变已读状态）',
    params: {},
    needsLogin: true,
    run: (a) => unread_api.getNoticeUnread(ApiService().dio),
  ),
  'message.pm': ApiScenario(
    desc: '私人消息列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => pm_api.getPmList(ApiService().dio, page: intArg(a, 'page', 1)),
  ),
  'message.pm.view': ApiScenario(
    desc: '私信会话详情（与某用户的消息列表；需登录）',
    params: {
      'touid': '*对方 uid（message.pm 返回项里的 uid）',
      'page': '页码（默认 0=最新一页；1=最旧一页，Discuz 从最旧页起算）',
    },
    needsLogin: true,
    run: (a) {
      final touid = a['touid'] ?? '';
      if (touid.isEmpty) throw Exception('缺少必填参数 touid');
      return pm_api.getPmView(
        ApiService().dio,
        touid: touid,
        page: intArg(a, 'page', 0),
      );
    },
  ),
  'message.mypost': ApiScenario(
    desc: '帖子提醒列表（需登录）',
    params: {'type': 'post/at（默认 post）', 'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => mypost_api.getMypostList(
      ApiService().dio,
      page: intArg(a, 'page', 1),
      type: a['type'] ?? 'post',
    ),
  ),
  'my.threads': ApiScenario(
    desc: '我的主题列表（需登录，默认移动端 UA）',
    params: {
      'type': 'thread/reply（可空）',
      'uid': '用户 ID（可空）',
      'page': '页码（默认 1）',
    },
    needsLogin: true,
    mobileSupported: true, // 我的主题/回复：移动 UA 走 SpaceThreadParser
    run: (a) => mythread_api.getMyThreads(
      ApiService().dio,
      page: intArg(a, 'page', 1),
      uid: (a['uid'] ?? '').isEmpty ? null : a['uid'],
      type: (a['type'] ?? '').isEmpty ? null : a['type'],
    ),
  ),
};

/// 扫描指定 Cookie 目录：游客 Cookie 数 + 各账号子目录
///
/// PersistCookieJar(FileStorage) 落盘结构为：
/// - 游客：`{host}/{jar}/...`（jar 目录内含 .index/.domains/{域} 文件）
/// - 账号：`{host}/{account}/{jar}/...`
/// 判定规则：一级子目录内含子目录 → 账号目录；仅含文件 → 游客 jar 目录。
Future<Map<String, dynamic>> _scanCookieDir(String dirPath) async {
  final dir = Directory(dirPath);
  var guest = 0;
  final accounts = <Map<String, dynamic>>[];
  if (await dir.exists()) {
    await for (final e in dir.list()) {
      if (e is File) {
        if (_isCookieFile(e.path)) guest++;
      } else if (e is Directory) {
        final entries = await e.list().toList();
        final subdirs = entries.whereType<Directory>().toList();
        if (subdirs.isNotEmpty) {
          // 账号目录：内部嵌套 jar 目录（如 {account}/ie1_ps1/）
          final n = await _countCookieFiles(subdirs);
          if (n > 0) accounts.add({'name': p.basename(e.path), 'cookies': n});
        } else {
          // 游客 jar 目录（如 {host}/ie1_ps1/）
          guest += entries
              .whereType<File>()
              .where((f) => _isCookieFile(f.path))
              .length;
        }
      }
    }
  }
  return {
    'guestCookies': guest,
    'accounts': accounts,
    'hasAnyCookie': guest > 0 || accounts.isNotEmpty,
  };
}

/// 排除 FileStorage 元数据文件（.index/.domains 等）
bool _isCookieFile(String path) => !p.basename(path).startsWith('.');

Future<int> _countCookieFiles(List<Directory> dirs) async {
  var n = 0;
  for (final d in dirs) {
    await for (final f in d.list()) {
      if (f is File && _isCookieFile(f.path)) n++;
    }
  }
  return n;
}

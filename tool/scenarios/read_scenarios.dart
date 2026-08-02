/// 只读场景：会话状态 / 导读 / 版块 / 帖子 / 用户 / 好友 / 消息 / 我的主题
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forum_api;
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as thread_api;
import 'package:mtbbs/api/home/friend/export.dart' as friend_api;
import 'package:mtbbs/api/home/favorite/export.dart' as favorite_api;
import 'package:mtbbs/api/home/follow/export.dart' as follow_api;
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/api/home/mythread/export.dart' as mythread_api;
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/api/home/system/export.dart' as system_api;
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;
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
  'guide.list': ApiScenario(
    desc: '导读列表（默认移动端 UA）',
    params: {
      'view': 'newthread/newreply/digest（默认 newthread）',
      'page': '页码（默认 1）',
    },
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
    run: (a) => forum_api.getForumThreads(
      ApiService().dio,
      fid: a['fid'] ?? '',
      orderby: a['orderby'] ?? '',
      filter: a['filter'] ?? '',
      page: intArg(a, 'page', 1),
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
  'user.info': ApiScenario(
    desc: '用户空间信息（uid/用户名 二选一，空则查自己）',
    params: {'uid': '用户 ID（可空）', 'username': '用户名（可空）'},
    run: (a) => space_api.getUserProfile(
      ApiService().dio,
      uid: a['uid'] ?? '',
      username: a['username'] ?? '',
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
  'message.system': ApiScenario(
    desc: '系统提醒列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) =>
        system_api.getSystemList(ApiService().dio, page: intArg(a, 'page', 1)),
  ),
  'message.pm': ApiScenario(
    desc: '私人消息列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => pm_api.getPmList(ApiService().dio, page: intArg(a, 'page', 1)),
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

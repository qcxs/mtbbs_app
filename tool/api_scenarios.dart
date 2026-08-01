import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:mtbbs/api/forum/forumdisplay/export.dart' as forum_api;
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as thread_api;
import 'package:mtbbs/api/home/mypost/export.dart' as mypost_api;
import 'package:mtbbs/api/home/mythread/export.dart' as mythread_api;
import 'package:mtbbs/api/home/pm/export.dart' as pm_api;
import 'package:mtbbs/api/home/space/export.dart' as space_api;
import 'package:mtbbs/api/home/friend/export.dart' as friend_api;
import 'package:mtbbs/api/home/system/export.dart' as system_api;
import 'package:mtbbs/api/misc/userstatus/export.dart' as userstatus_api;
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';

/// 探针场景定义
class ApiScenario {
  /// 场景描述（供 AI 理解用途）
  final String desc;

  /// 参数说明（key: 默认值 或 *必填）
  final Map<String, String> params;

  /// 是否必须登录（无 Cookie 时探针会拦截并提示）
  final bool needsLogin;

  /// 原始输出模式：为 true 时结果不做长字符串截断
  /// （调试场景用于展示完整原始响应，由场景自己控制输出长度）
  final bool raw;

  /// 执行函数：args 为参数值（字符串）
  final Future<Map<String, dynamic>> Function(Map<String, String> args) run;

  const ApiScenario({
    required this.desc,
    required this.params,
    this.needsLogin = false,
    this.raw = false,
    required this.run,
  });
}

/// 只读场景注册表（命令名 → 场景）
///
/// 所有命令均不产生写操作（不发帖/不点赞/不登录），
/// 只读请求 + 解析，保证探针安全可重复执行。
final Map<String, ApiScenario> scenarios = {
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
      page: _intArg(a, 'page', 1),
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
      page: _intArg(a, 'page', 1),
    ),
  ),
  'thread.detail': ApiScenario(
    desc: '帖子详情（楼主 + 各楼层，数据量大会自动截断）',
    params: {'tid': '*帖子 ID', 'page': '页码（默认 1）', 'authorid': '只看作者（可空）'},
    run: (a) => thread_api.getThreadDetail(
      ApiService().dio,
      tid: a['tid'] ?? '',
      page: _intArg(a, 'page', 1),
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
      page: _intArg(a, 'page', 1),
    ),
  ),
  'message.system': ApiScenario(
    desc: '系统提醒列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) =>
        system_api.getSystemList(ApiService().dio, page: _intArg(a, 'page', 1)),
  ),
  'message.pm': ApiScenario(
    desc: '私人消息列表（需登录）',
    params: {'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => pm_api.getPmList(ApiService().dio, page: _intArg(a, 'page', 1)),
  ),
  'message.mypost': ApiScenario(
    desc: '帖子提醒列表（需登录）',
    params: {'type': 'post/at（默认 post）', 'page': '页码（默认 1）'},
    needsLogin: true,
    run: (a) => mypost_api.getMypostList(
      ApiService().dio,
      page: _intArg(a, 'page', 1),
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
      page: _intArg(a, 'page', 1),
      uid: (a['uid'] ?? '').isEmpty ? null : a['uid'],
      type: (a['type'] ?? '').isEmpty ? null : a['type'],
    ),
  ),
  'debug.http': ApiScenario(
    desc:
        '调试用：GET 指定路径，输出状态码/响应头/原始正文'
        '（携带当前会话 Cookie，用于 parse 开发时对照 DOM 结构）',
    params: {
      'path': '请求路径（默认 /forum.php，也可传完整 URL）',
      'q': '额外 query 参数，k=v 逗号分隔，如 mod=guide,index=1',
      'n': '正文最多输出字符数（默认 1200）',
    },
    raw: true,
    run: (a) async {
      final dio = ApiService().dio;
      final n = int.tryParse(a['n'] ?? '') ?? 1200;
      // path/n/q 以外的固定键 + q 里的 k=v 共同组成 query 参数。
      // 不用 JSON 是因为引号会被 PowerShell→cmd 传递剥离；
      // 逗号在 PowerShell/cmd 中均无特殊含义，传参零风险。
      final query = <String, String>{
        for (final e in a.entries)
          if (e.key != 'path' &&
              e.key != 'n' &&
              e.key != 'q' &&
              e.value.isNotEmpty)
            e.key: e.value,
      };
      for (final pair in (a['q'] ?? '').split(',')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final k = pair.substring(0, idx).trim();
          final v = pair.substring(idx + 1).trim();
          if (k.isNotEmpty) query[k] = v;
        }
      }
      final uri = Uri.parse(SiteStore.instance.baseUrl)
          .resolve(a['path'] ?? '/forum.php')
          .replace(queryParameters: query.isEmpty ? null : query);
      final resp = await dio.get<String>(uri.toString());
      final body = resp.data ?? '';
      final show = body.length > n
          ? '${body.substring(0, n)}…(+${body.length - n}字符截断)'
          : body;
      return {
        'url': uri.toString(),
        'statusCode': resp.statusCode,
        'contentType': resp.headers.value(Headers.contentTypeHeader),
        'bodyLength': body.length,
        'body': show,
      };
    },
  ),
};

int _intArg(Map<String, String> a, String key, int fallback) =>
    int.tryParse(a[key] ?? '') ?? fallback;

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

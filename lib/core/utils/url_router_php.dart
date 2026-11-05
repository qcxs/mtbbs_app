part of 'url_router.dart';

/// 非当前站点的归属信息（host/name 为空表示当前站点）
typedef _SiteRef = ({String? host, String? name});

/// 带站点归属地构造路由结果
UrlRouteResult _r(_SiteRef site, String label, String? appPath) {
  return UrlRouteResult(
    label: label,
    appPath: appPath,
    siteHost: site.host,
    siteName: site.name,
  );
}

/// 构建帖子路由路径，page > 1 时附加 ?page=N
String _threadPath(String tid, int page) {
  if (page > 1) return '/thread/$tid?page=$page';
  return '/thread/$tid';
}

/// 解析 page 参数。先尝试外部查询参数，失败时使用[fallback]（默认 1）。
int _resolvePage(String? externalPage, {int fallback = 1}) {
  if (externalPage != null) {
    final p = int.tryParse(externalPage);
    if (p != null && p > 1) return p;
  }
  return fallback;
}

/// 用户空间短链：`https://host/?100`（查询串为纯数字，无参数名）→ 用户主页。
///
/// 部分 Discuz 站（如 bbs.binmt.cc）用 `?uid` 的短形式直接进个人空间。
UrlRouteResult? _matchBareUidSpace(Map<String, String> query, _SiteRef site) {
  if (query.length != 1) return null;
  final entry = query.entries.first;
  if (entry.value.isNotEmpty) return null;
  if (!RegExp(r'^\d+$').hasMatch(entry.key)) return null;
  return _r(site, '用户主页', '/user/${entry.key}');
}

/// 解析 forum.php 链接（帖子 / 板块 / 发帖 / 在线用户 / 小黑屋 / 导读）。
UrlRouteResult? _matchForumPhp(Map<String, String> query, _SiteRef site) {
  final mod = query['mod'];

  // 在线用户（PC 专属页）：forum.php?showoldetails=yes
  if (query['showoldetails'] != null) {
    return _r(site, '在线用户', '/online');
  }

  // 小黑屋（PC 专属页）：forum.php?mod=misc&action=showdarkroom
  if (mod == 'misc' && query['action'] == 'showdarkroom') {
    return _r(site, '小黑屋', '/darkroom');
  }

  // 导读：forum.php?mod=guide&view={newthread|hot|new|digest|sofa|my}[&index=N]
  // App 内对应「导读」页；具体 view 由页内 Tab 承载，路由层不带参数，
  // index（页码）同理由页内列表自管。
  if (mod == 'guide') {
    return _r(site, '导读', '/guide');
  }

  if (mod == 'viewthread') {
    final tid = query['tid'];
    if (tid != null && tid.isNotEmpty) {
      final page = _resolvePage(query['page']);
      return _r(site, '帖子详情', _threadPath(tid, page));
    }
    return _r(site, '帖子详情（缺少 tid）', null);
  }

  if (mod == 'redirect') {
    final goto = query['goto'];
    if (goto == 'findpost') {
      final pid = query['pid'];
      final ptid = query['ptid'];
      if (pid != null && pid.isNotEmpty && ptid != null && ptid.isNotEmpty) {
        return _r(site, '帖子详情（定位回复）', '/thread/$ptid?pid=$pid');
      }
    }
    return _r(site, '帖子详情（缺少参数）', null);
  }

  if (mod == 'forumdisplay') {
    final fid = query['fid'];
    if (fid != null && fid.isNotEmpty) {
      final page = _resolvePage(query['page']);
      final pageSuffix = page > 1 ? '&page=$page' : '';
      return _r(site, '板块', '/forum?fid=$fid$pageSuffix');
    }
    return _r(site, '板块（缺少 fid）', null);
  }

  if (mod == 'post') {
    final postResult = _parsePostUrl(query);
    return _r(site, postResult.label, postResult.appPath);
  }

  return null;
}

/// 解析 group.php 链接（圈子分类 / 圈子首页）。
UrlRouteResult _matchGroupPhp(Map<String, String> query, _SiteRef site) {
  final gid = query['gid'];
  if (gid != null && gid.isNotEmpty) {
    return _r(site, '圈子分类', '/groups/category?gid=$gid');
  }
  return _r(site, '圈子', '/groups');
}

/// 解析 home.php 链接（关注/好友/留言板/帖子/收藏/私信/资料/积分记录）。
///
/// 返回 null 表示该 mod 暂未适配，交由后续匹配器继续判断。
UrlRouteResult? _matchHomePhp(Map<String, String> query, _SiteRef site) {
  final mod = query['mod'];

  // 关注/粉丝：home.php?mod=follow&do={following|follower}[&uid=X][&page=N]
  // uid 为空 = 当前用户自己的列表 → /follow?type=...；指定 uid → /follow?type=...&uid=X
  if (mod == 'follow') {
    final String do_ = query['do'] ?? '';
    if (do_ == 'following' || do_ == 'follower') {
      final uid = query['uid'];
      final hasUid = uid != null && uid.isNotEmpty;
      final page = _resolvePage(query['page']);
      final params = <String, String>{
        'type': do_,
        if (hasUid) 'uid': uid,
        if (page > 1) 'page': '$page',
      };
      final qs = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      return _r(
        site,
        hasUid
            ? (do_ == 'following' ? 'TA的关注' : 'TA的粉丝')
            : (do_ == 'following' ? '我的关注' : '我的粉丝'),
        '/follow$qs',
      );
    }
    // do=view 等（广播 feed）暂未适配，走内置浏览器
    return _r(site, '广播', null);
  }
  if (mod == 'space') {
    final uid = query['uid'];
    // 好友列表：home.php?mod=space[&uid=X]&do=friend[&view=me][&page=N]
    // uid 为空（含空 uid= 的“我的好友”写法）→ /friends；指定 uid → /friends?uid=X
    if (query['do'] == 'friend') {
      final hasUid = uid != null && uid.isNotEmpty;
      final page = _resolvePage(query['page']);
      final params = <String, String>{
        if (hasUid) 'uid': uid,
        if (page > 1) 'page': '$page',
      };
      final qs = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      return _r(site, hasUid ? '好友列表' : '我的好友', '/friends$qs');
    }
    // 留言板：home.php?mod=space[&uid=X]&do=wall[&page=N]
    // 注意必须排在下面 `uid 非空 → 用户主页` 之前：do=wall 也带 uid
    if (query['do'] == 'wall') {
      final hasUid = uid != null && uid.isNotEmpty;
      final page = _resolvePage(query['page']);
      final qs = page > 1 ? '?page=$page' : '';
      return _r(
        site,
        hasUid ? '留言板' : '我的留言板',
        '/user/${hasUid ? uid : 'self'}/wall$qs',
      );
    }
    // 我的帖子/回复：home.php?mod=space[&uid=X]&do=thread[&view=me][&type=reply]
    // 注意排在下面 `uid 非空 → 用户主页` 之前：do=thread 也带 uid
    if (query['do'] == 'thread') {
      final hasUid = uid != null && uid.isNotEmpty;
      final isReply = query['type'] == 'reply';
      final params = <String, String>{
        if (isReply) 'type': 'reply',
        if (hasUid) 'uid': uid,
      };
      final qs = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      return _r(
        site,
        hasUid ? 'Ta的帖子' : (isReply ? '最近回复' : '我的帖子'),
        '/my-threads$qs',
      );
    }
    // 我的收藏：home.php?mod=space&do=favorite[&view=me][&type=all|thread|forum]
    if (query['do'] == 'favorite') {
      return _r(site, '我的收藏', '/favorite');
    }
    if (uid != null && uid.isNotEmpty) {
      return _r(site, '用户主页', '/user/$uid');
    }
    // 私人消息：home.php?mod=space&do=pm[&subop=view&touid=X]
    // 会话详情 → 聊天页；消息列表（无 subop）→ 消息 Tab
    if (query['do'] == 'pm') {
      final touid = query['touid'];
      if (query['subop'] == 'view' && touid != null && touid.isNotEmpty) {
        return _r(site, '私信会话', '/pm/chat?touid=$touid');
      }
      return _r(site, '我的消息', '/message');
    }
    // home.php?mod=space&do=profile — 当前用户个人资料页（无 uid）
    if (query['do'] == 'profile') {
      return _r(site, '我的主页', '/user/self');
    }
    return _r(site, '用户主页（缺少 uid）', null);
  }
  // 发私信页：home.php?mod=spacecp&ac=pm&op=showmsg&touid=X → 聊天页
  if (mod == 'spacecp' && query['ac'] == 'pm' && query['op'] == 'showmsg') {
    final touid = query['touid'];
    if (touid != null && touid.isNotEmpty) {
      return _r(site, '发私信', '/pm/chat?touid=$touid');
    }
  }
  // 积分记录：home.php?mod=spacecp&ac=credit&op=log[&exttype=N][&optype=CODE]
  // exttype：1=好评 / 2=金币 / 3=信誉（0/缺省=不限）；optype 为操作类型代码
  if (mod == 'spacecp' && query['ac'] == 'credit' && query['op'] == 'log') {
    final exttype = query['exttype'] ?? '';
    final optype = query['optype'] ?? '';
    final params = <String, String>{
      if (exttype.isNotEmpty && exttype != '0') 'exttype': exttype,
      if (optype.isNotEmpty) 'optype': optype,
    };
    final qs = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    return _r(site, '积分记录', '/credit-log$qs');
  }

  return null;
}

/// 解析 misc.php 链接（用户排行）。
///
/// 用户排行：misc.php?mod=ranklist[&type=member][&view=beauty|handsome|credit|
///   friendnum|invite|post|onlinetime]
/// 无 type（排行榜 hub）与 type=member 都落到 App「用户排行」页；
/// type=thread / type=forum 暂无 App 页面，走内置浏览器。
UrlRouteResult? _matchMiscPhp(Map<String, String> query, _SiteRef site) {
  if (query['mod'] == 'ranklist') {
    final type = query['type'] ?? '';
    if (type.isEmpty || type == 'member') {
      final view = query['view'] ?? '';
      final qs = view.isEmpty ? '' : '?view=$view';
      return _r(site, '用户排行', '/ranklist$qs');
    }
    return _r(site, '排行榜', null);
  }
  return null;
}

/// 解析 forum.php?mod=post 类型的 URL
({String label, String? appPath}) _parsePostUrl(Map<String, String> query) {
  final action = query['action'];
  final tid = query['tid'];
  final pid = query['pid'];
  final fid = query['fid'];

  switch (action) {
    case 'newthread':
      if (fid != null && fid.isNotEmpty) {
        return (label: '发新帖', appPath: '/editor?type=post&fid=$fid');
      }
      return (label: '发新帖（缺少 fid）', appPath: null);

    case 'reply':
      if (tid == null || tid.isEmpty) {
        return (label: '回复帖子（缺少 tid）', appPath: null);
      }
      if (pid != null && pid.isNotEmpty) {
        // 引用回复
        return (
          label: '回复评论',
          appPath: '/editor?type=reply&tid=$tid&pid=$pid',
        );
      }
      // 普通评论
      return (label: '评论帖子', appPath: '/editor?type=comment&tid=$tid');

    case 'edit':
      if (tid != null && tid.isNotEmpty && pid != null && pid.isNotEmpty) {
        return (
          label: '编辑帖子',
          appPath: '/editor?type=editPost&tid=$tid&pid=$pid',
        );
      }
      return (label: '编辑帖子（缺少参数）', appPath: null);

    default:
      return (label: '不支持的页面', appPath: null);
  }
}

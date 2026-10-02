import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 可被内置浏览器「接管回退」的 App 页面注册表 + 开关状态。
///
/// 背景：App 自行实现了一批页面（帖子详情 / 用户主页 / 搜索 / 我的…），
/// 但个别页面可能不合用户口味。设置 → 「页面接管」里可逐页关闭：
/// **默认全部开启 = 走 App 页面；关闭某项 = 该页面无论从哪进入都改用内置浏览器。**
///
/// 落地方式：与 `UrlRouter.resolveTarget` **无关**，唯一生效点在
/// `buildRouter` 的 GoRouter 顶层 `redirect`（`lib/config/router.dart`）——
/// 所有导航（链接点击 / 帖子卡片 / 头像 / 入口 ListTile / 系统入站链接 / 深链）
/// 都要过 redirect，因此**不需要在每个调用点埋判断**，也不会漏掉将来的新入口。
///
/// 为什么开关状态放在模块级变量、而不是只放 Provider：
/// 与 `api_service.dart` 的 `_simulateBrowserHeaders` 同理 —— GoRouter 的
/// redirect 回调没有 Provider 依赖，而 `SettingsProvider.load()` 早于 UI 构建、
/// 启动早期就要写入，模块变量最省依赖（也避免 router ↔ provider 的循环 import）。
class AppPage {
  /// 稳定 id（用于持久化，勿改）
  final String id;

  /// 设置页展示名
  final String label;

  /// 设置页图标
  final IconData icon;

  const AppPage(this.id, this.label, this.icon);
}

/// 页面注册表：顺序即设置页展示顺序
const List<AppPage> appPages = [
  AppPage('thread', '帖子详情', Icons.article_outlined),
  AppPage('user', '用户主页', Icons.person_outline),
  AppPage('forum', '版块帖子列表', Icons.forum_outlined),
  AppPage('search', '站内搜索结果', Icons.search),
  AppPage('myThread', '我的帖子/回复', Icons.history_edu_outlined),
  AppPage('favorite', '我的收藏', Icons.bookmark_border),
  AppPage('friend', '好友列表', Icons.group_outlined),
  AppPage('follow', '关注/粉丝', Icons.people_outline),
  AppPage('online', '在线用户', Icons.online_prediction_outlined),
  AppPage('darkroom', '小黑屋', Icons.gavel_outlined),
  AppPage('pm', '私信会话', Icons.chat_bubble_outline),
  AppPage('editor', '发帖/编辑器', Icons.edit_outlined),
];

final Set<String> _allPageIds = {for (final p in appPages) p.id};

/// 已关闭 App 接管的页面 id（空集合 = 全部走 App 页）
Set<String> _disabledPages = <String>{};

/// 写入开关状态（由 `SettingsProvider` 的 load / setter 调用）。
/// 自动过滤掉已不在注册表内的历史 id，避免"UI 上无处取消、却仍然生效"。
void applyDisabledAppPages(Set<String> ids) {
  _disabledPages = ids.where(_allPageIds.contains).toSet();
}

/// 当前被关闭接管的页面 id（只读副本）
Set<String> get disabledAppPages => Set.unmodifiable(_disabledPages);

/// 该页面是否走 App（默认 true）
bool appPageEnabled(String id) => !_disabledPages.contains(id);

/// 回退到内置浏览器时**强制 PC UA** 的页面。
///
/// 这两页是 Discuz 的 PC 专属功能，移动模板通常没有对应实现（用移动 UA 打开
/// 只会看到残缺/空页），因此回退时直接以 PC UA 渲染；进页后仍可用浏览器的
/// 「桌面模式」菜单手动切回。
const Set<String> _desktopUaPageIds = {'online', 'darkroom'};

/// 终极降级开关：App 整体退化为内置浏览器。
///
/// 用途是"逃生阀"：App 侧页面被反复人机验证 / 防盗链卡住时，一键把所有页面
/// 交给内置浏览器（WebView 能真正过验证码），至少保证论坛可用。
bool _browserOnlyMode = false;

/// 写入终极开关（由 `SettingsProvider` 的 load / setter 调用）
void applyBrowserOnlyMode(bool enabled) {
  _browserOnlyMode = enabled;
}

/// 是否处于"整体退化为内置浏览器"模式
bool get browserOnlyMode => _browserOnlyMode;

/// 降级模式下**放行**的路由：浏览器自身 + 设置（含子路由）。
///
/// 必须放行设置，否则开关只能进不能出——用户会被锁死在浏览器里改不回来。
bool isBrowserOnlyExempt(String location) {
  final path = location.split('?').first;
  return path.startsWith('/browser') || path.startsWith('/settings');
}

/// 内置浏览器兜底路径。带 `intercept=false`：浏览器不再二次拦截，
/// 否则会出现"回退到浏览器 → 又被 App 接管"的往返（见 docs/07 #64）。
/// [desktopUa] 为 true 时附加 `ua=pc`，让浏览器用 PC UA 打开（见 [_desktopUaPageIds]）。
String browserFallbackPath(String url, {bool desktopUa = false}) =>
    '/browser?url=${Uri.encodeComponent(url)}'
    '${desktopUa ? '&ua=pc' : ''}'
    '&intercept=false';

/// 「页面接管」决策 —— **唯一生效点**，由 GoRouter 顶层 `redirect` 调用。
///
/// 返回 null = 放行，正常进 App 页；返回非空 = 改去内置浏览器。
/// 抽成纯函数便于单测（router 本身依赖整棵 Widget 树，不便直接测）。
String? appPageRedirect(String location) {
  final id = featureIdOf(location);
  final desktopUa = id != null && _desktopUaPageIds.contains(id);

  // 终极降级：除浏览器 / 设置外，一律交给内置浏览器。
  // 算不出该页站内地址时退化到站点首页（浏览器至少能打开），不留在 App 页。
  if (_browserOnlyMode) {
    if (isBrowserOnlyExempt(location)) return null;
    return browserFallbackPath(
      siteUrlFor(location) ?? SiteStore.instance.baseUrl,
      desktopUa: desktopUa,
    );
  }

  if (id == null || appPageEnabled(id)) return null; // 非内容页 / 未关闭
  final url = siteUrlFor(location);
  if (url == null) return null; // 算不出对应站内地址 → 保持走 App 页
  return browserFallbackPath(url, desktopUa: desktopUa);
}

/// 由 App 内路径反查页面 id；无对应页面（设置 / 历史 / 顶层 Tab 等）返回 null，
/// 表示**不受开关影响**。
String? featureIdOf(String location) {
  final path = location.split('?').first;
  if (path.startsWith('/thread/')) return 'thread';
  if (path.startsWith('/user/')) return 'user';
  if (path.startsWith('/forum')) return 'forum';
  // 只拦「站内搜索结果」页；`/search` 是搜索中心（站内搜索/Bing/打开链接/找用户/历史
  // 多个功能），整页回退会把其它功能一起废掉，故不纳入开关。
  if (path.startsWith('/search/result')) return 'search';
  if (path.startsWith('/my-threads')) return 'myThread';
  if (path.startsWith('/favorite')) return 'favorite';
  if (path.startsWith('/friends')) return 'friend';
  if (path.startsWith('/follow')) return 'follow';
  if (path.startsWith('/online')) return 'online';
  if (path.startsWith('/darkroom')) return 'darkroom';
  if (path.startsWith('/pm/chat')) return 'pm';
  if (path.startsWith('/editor')) return 'editor';
  return null;
}

/// 由 App 内路径反查**站内 URL**，供 redirect 回退内置浏览器用。
///
/// 与 `UrlRouter.parse`（URL → appPath）互为正反：这里是 appPath → URL。
/// 算不出 URL 时返回 null（如顶层 `/forum` 无 fid、参数缺失）—— 调用方应保持走 App 页，
/// 不要硬凑一个不对应的地址。
String? siteUrlFor(String appPath) {
  final uri = Uri.tryParse(appPath);
  final id = featureIdOf(appPath);
  if (uri == null || id == null) return null;
  final base = SiteStore.instance.baseUrl;
  final q = uri.queryParameters;
  // 路径第 2 段（如 /thread/{tid} 的 tid）
  final seg = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
  final page = int.tryParse(q['page'] ?? '') ?? 1;

  switch (id) {
    case 'thread':
      if (seg.isEmpty) return null;
      return '$base/forum.php?mod=viewthread&tid=$seg'
          '${page > 1 ? '&page=$page' : ''}';

    case 'user':
      if (seg.isEmpty || seg == 'self') {
        return '$base/home.php?mod=space&do=profile';
      }
      return '$base/home.php?mod=space&uid=$seg&do=profile&from=space';

    case 'forum':
      final fid = q['fid'] ?? '';
      if (fid.isEmpty) return null; // 顶层 /forum：无对应单页 URL
      return '$base/forum.php?mod=forumdisplay&fid=$fid'
          '${page > 1 ? '&page=$page' : ''}';

    case 'search':
      // 仅 /search/result 会落到这里（`/search` 入口页不受开关影响）
      final kw = q['kw'] ?? '';
      if (kw.isEmpty) return '$base/search.php?mod=forum';
      return '$base/search.php?mod=forum'
          '&srchtxt=${Uri.encodeQueryComponent(kw)}&searchsubmit=yes';

    case 'myThread':
      final uid = q['uid'] ?? '';
      final type = q['type'] ?? '';
      final buf = StringBuffer('$base/home.php?mod=space&do=thread');
      if (uid.isNotEmpty) buf.write('&uid=$uid');
      if (type.isNotEmpty) buf.write('&type=$type');
      return buf.toString();

    case 'favorite':
      return '$base/home.php?mod=space&do=favorite&view=me';

    case 'friend':
      final uid = q['uid'] ?? '';
      final p = page > 1 ? '&page=$page' : '';
      if (uid.isEmpty) {
        return '$base/home.php?mod=space&do=friend&view=me&from=space$p';
      }
      return '$base/home.php?mod=space&uid=$uid&do=friend&from=space$p';

    case 'follow':
      final type = q['type'] ?? 'following';
      final uid = q['uid'] ?? '';
      final buf = StringBuffer('$base/home.php?mod=follow&do=$type');
      if (uid.isNotEmpty) buf.write('&uid=$uid');
      if (page > 1) buf.write('&page=$page');
      return buf.toString();

    case 'online':
      return '$base/forum.php?showoldetails=yes';

    case 'darkroom':
      return '$base/forum.php?mod=misc&action=showdarkroom';

    case 'pm':
      final touid = q['touid'] ?? '';
      if (touid.isEmpty) return '$base/home.php?mod=space&do=pm';
      return '$base/home.php?mod=space&do=pm&subop=view&touid=$touid';

    case 'editor':
      final type = q['type'] ?? 'post';
      final fid = q['fid'] ?? '';
      final tid = q['tid'] ?? '';
      final pid = q['pid'] ?? '';
      switch (type) {
        case 'comment':
        case 'reply':
          if (tid.isEmpty) return null;
          return '$base/forum.php?mod=post&action=reply&tid=$tid'
              '${pid.isEmpty ? '' : '&pid=$pid'}';
        case 'editPost':
        case 'editReply':
          if (tid.isEmpty || pid.isEmpty) return null;
          return '$base/forum.php?mod=post&action=edit&tid=$tid&pid=$pid';
        default:
          if (fid.isEmpty) return null;
          return '$base/forum.php?mod=post&action=newthread&fid=$fid';
      }
  }
  return null;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/core/app/app_page_gate.dart';
import 'package:mtbbs/widgets/layout/global_shortcuts.dart';
import 'package:mtbbs/widgets/layout/window_title_bar.dart';
import 'package:mtbbs/widgets/layout/app_shell.dart';
import 'package:mtbbs/models/editor_snapshot.dart';
import 'package:mtbbs/pages/home/home_page.dart';
import 'package:mtbbs/pages/guide/guide_page.dart';
import 'package:mtbbs/pages/message/message_page.dart';
import 'package:mtbbs/pages/message/pm_chat_page.dart';
import 'package:mtbbs/pages/community/community_page.dart';
import 'package:mtbbs/pages/group/group_index_page.dart';
import 'package:mtbbs/pages/group/group_category_page.dart';
import 'package:mtbbs/pages/user/my_profile_page.dart';
import 'package:mtbbs/pages/settings/settings_page.dart';
import 'package:mtbbs/pages/settings/settings_search_page.dart';
import 'package:mtbbs/pages/settings/about_page.dart';
import 'package:mtbbs/pages/settings/cache_settings_page.dart';
import 'package:mtbbs/pages/settings/editor_settings_page.dart';
import 'package:mtbbs/pages/settings/history_format_page.dart';
import 'package:mtbbs/pages/settings/models/developer_settings.dart';
import 'package:mtbbs/pages/settings/models/mcp_settings.dart';
import 'package:mtbbs/pages/settings/settings_group_page.dart';
import 'package:mtbbs/pages/thread/thread_view_page.dart';
import 'package:mtbbs/pages/editor/editor_page.dart';
import 'package:mtbbs/pages/editor/editor_history_page.dart';
import 'package:mtbbs/pages/user/user_profile_page.dart';
import 'package:mtbbs/pages/user/my_thread_page.dart';
import 'package:mtbbs/pages/user/credit_log_page.dart';
import 'package:mtbbs/pages/browser/browser_page.dart';
import 'package:mtbbs/pages/search/search_page.dart';
import 'package:mtbbs/pages/search/search_result_page.dart';
import 'package:mtbbs/pages/history/history_page.dart';
import 'package:mtbbs/pages/darkroom/darkroom_page.dart';
import 'package:mtbbs/pages/online/online_page.dart';
import 'package:mtbbs/pages/favorite/favorite_page.dart';
import 'package:mtbbs/pages/friend/friend_page.dart';
import 'package:mtbbs/pages/follow/follow_page.dart';
import 'package:mtbbs/widgets/image_preview/gallery_viewer.dart';

GoRouter buildRouter({
  GlobalKey<NavigatorState>? navigatorKey,
  String initialLocation = '/',
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    // 「页面接管」开关的唯一生效点（设置 → 页面接管）。
    // 放在顶层 redirect 而不是各调用点：所有导航（链接点击、帖子卡片、头像、
    // 入口 ListTile、系统入站链接、深链）都要经过这里，因此天然"全入口覆盖"，
    // 也不会漏掉将来新增的入口。policy 细节见 core/app/app_page_gate.dart。
    redirect: (context, state) => appPageRedirect(state.uri.toString()),
    // 入站链接（Android「打开方式」）不走 GoRouter 的平台初始路由，而是由
    // AppLink 通道解析成 appPath 再 push —— Flutter 自带的 deep link 处理
    // 已在 AndroidManifest 里关掉（flutter_deeplinking_enabled=false），
    // 否则它会把完整论坛 URL 塞进来导致 "no routes for location"。
    routes: [
      ShellRoute(
        // 套一层窗口外壳：Windows 自绘标题栏（含 MCP 状态），不再用原生标题栏。
        // 放在这里而不是 MaterialApp.builder：需要 Theme / Overlay / Material 祖先
        builder: (_, __, child) =>
            WindowChrome(child: GlobalShortcutsWrapper(child: child)),
        routes: [
          ShellRoute(
            builder: (_, __, child) => AppShell(child: child),
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomePage()),
              GoRoute(path: '/guide', builder: (_, __) => const GuidePage()),
              GoRoute(
                path: '/message',
                pageBuilder: (_, __) =>
                    const NoTransitionPage(child: MessagePage()),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfilePage(),
              ),
            ],
          ),
          GoRoute(
            path: '/forum',
            pageBuilder: (_, state) => NoTransitionPage(
              child: CommunityPage(fid: state.uri.queryParameters['fid'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/groups',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: GroupIndexPage()),
          ),
          GoRoute(
            path: '/groups/category',
            pageBuilder: (_, state) {
              final q = state.uri.queryParameters;
              return NoTransitionPage(
                key: ValueKey('group_category_${q['gid'] ?? ''}'),
                child: GroupCategoryPage(
                  gid: q['gid'] ?? '',
                  name: q['name'] ?? '',
                  initialPage: int.tryParse(q['page'] ?? '') ?? 1,
                ),
              );
            },
          ),
          // 圈子内容（只读）：圈子的「讨论区」就是 forumdisplay&fid={gid}
          GoRoute(
            path: '/groups/content',
            pageBuilder: (_, state) {
              final q = state.uri.queryParameters;
              return NoTransitionPage(
                key: ValueKey('group_content_${q['gid'] ?? ''}'),
                child: CommunityPage(
                  fid: q['gid'] ?? '',
                  title: q['name'] ?? '',
                  readOnly: true,
                ),
              );
            },
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
          GoRoute(
            path: '/settings/cache',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: CacheSettingsPage()),
          ),
          GoRoute(
            path: '/settings/search',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsSearchPage()),
          ),
          GoRoute(
            path: '/settings/about',
            pageBuilder: (_, __) => const NoTransitionPage(child: AboutPage()),
          ),
          GoRoute(
            path: '/settings/editor',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: EditorSettingsPage()),
          ),
          // MCP 设置 —— 与设置页「MCP 服务」分组共用同一份声明
          // （`mcpSettings`），供 MCP 快捷弹窗右上角直达
          GoRoute(
            path: '/settings/mcp',
            pageBuilder: (_, __) => NoTransitionPage(
              child: SettingsGroupPage(
                title: 'MCP 服务',
                modelsBuilder: mcpSettings,
              ),
            ),
          ),
          // 开发者选项 —— 入口是「关于页图标连点 7 次」，所以不做成设置页的分组行
          GoRoute(
            path: '/settings/developer',
            pageBuilder: (_, __) => NoTransitionPage(
              child: SettingsGroupPage(
                title: '开发者选项',
                modelsBuilder: developerSettings,
              ),
            ),
          ),
          GoRoute(
            path: '/thread/:tid',
            pageBuilder: (_, state) {
              final tid = state.pathParameters['tid'] ?? '';
              final pageStr = state.uri.queryParameters['page'];
              final pid = state.uri.queryParameters['pid'];
              final authorid = state.uri.queryParameters['authorid'];
              // pid 优先级高于 page，两者不共存
              final initialPage = pid != null && pid.isNotEmpty
                  ? 1
                  : (int.tryParse(pageStr ?? '') ?? 1);
              return NoTransitionPage(
                key: ValueKey(
                  'thread_page_$tid${pid != null ? '_pid$pid' : ''}',
                ),
                child: ThreadViewPage(
                  tid: tid,
                  initialPage: initialPage,
                  pid: pid,
                  authorid: authorid,
                ),
              );
            },
          ),
          GoRoute(
            path: '/editor',
            pageBuilder: (_, state) {
              final typeStr = state.uri.queryParameters['type'] ?? 'post';
              final type = switch (typeStr) {
                'comment' => EditorType.comment,
                'reply' => EditorType.reply,
                'editPost' => EditorType.editPost,
                'editReply' => EditorType.editReply,
                _ => EditorType.post,
              };
              return NoTransitionPage(
                child: EditorPage(
                  type: type,
                  fid: state.uri.queryParameters['fid'] ?? '',
                  tid: state.uri.queryParameters['tid'] ?? '',
                  pid: state.uri.queryParameters['pid'] ?? '',
                ),
              );
            },
          ),
          GoRoute(
            path: '/editor/history',
            pageBuilder: (_, state) => NoTransitionPage(
              child: EditorHistoryPage(
                sessionKey: state.uri.queryParameters['key'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/user/:uid',
            pageBuilder: (_, state) {
              final uid = state.pathParameters['uid'] ?? '';
              return NoTransitionPage(
                key: ValueKey('user_page_$uid'),
                child: UserProfilePage(uid: uid),
              );
            },
          ),
          GoRoute(
            path: '/browser',
            pageBuilder: (_, state) => NoTransitionPage(
              child: BrowserPage(
                initialUrl: state.uri.queryParameters['url'] ?? '',
                enableUrlIntercept:
                    state.uri.queryParameters['intercept'] != 'false',
                // `ua=pc`：以桌面模式（PC UA）打开，供 PC 专属页（在线用户/小黑屋）回退用
                desktopUa: state.uri.queryParameters['ua'] == 'pc',
              ),
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, __) => const NoTransitionPage(child: SearchPage()),
          ),
          GoRoute(
            path: '/search/result',
            pageBuilder: (_, state) => NoTransitionPage(
              child: SearchResultPage(
                keyword: state.uri.queryParameters['kw'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: HistoryPage()),
          ),
          GoRoute(
            path: '/settings/history-format',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: HistoryFormatPage()),
          ),
          GoRoute(
            path: '/darkroom',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: DarkroomPage()),
          ),
          GoRoute(
            path: '/online',
            pageBuilder: (_, __) => const NoTransitionPage(child: OnlinePage()),
          ),
          GoRoute(
            path: '/pm/chat',
            pageBuilder: (_, state) {
              final touid = state.uri.queryParameters['touid'] ?? '';
              final username = state.uri.queryParameters['username'];
              return NoTransitionPage(
                key: ValueKey('pm_chat_$touid'),
                child: PmChatPage(touid: touid, username: username),
              );
            },
          ),
          GoRoute(
            path: '/friends',
            pageBuilder: (_, state) {
              final uid = state.uri.queryParameters['uid'];
              final page =
                  int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 1;
              return NoTransitionPage(
                child: FriendPage(uid: uid, initialPage: page),
              );
            },
          ),
          GoRoute(
            path: '/follow',
            pageBuilder: (_, state) {
              final type = state.uri.queryParameters['type'] ?? 'following';
              final uid = state.uri.queryParameters['uid'];
              final page =
                  int.tryParse(state.uri.queryParameters['page'] ?? '') ?? 1;
              return NoTransitionPage(
                child: FollowPage(type: type, uid: uid, initialPage: page),
              );
            },
          ),
          GoRoute(
            path: '/favorite',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: FavoritePage()),
          ),
          GoRoute(
            path: '/credit-log',
            pageBuilder: (_, state) {
              final q = state.uri.queryParameters;
              final exttype = q['exttype'] ?? '0';
              final optype = q['optype'] ?? '';
              return NoTransitionPage(
                key: ValueKey('credit_log_${exttype}_$optype'),
                child: CreditLogPage(
                  initialExttype: exttype,
                  initialOptype: optype,
                ),
              );
            },
          ),
          GoRoute(
            path: '/my-threads',
            pageBuilder: (_, state) {
              final type = state.uri.queryParameters['type'];
              final uid = state.uri.queryParameters['uid'];
              return NoTransitionPage(
                child: MyThreadPage(type: type, uid: uid),
              );
            },
          ),
          GoRoute(
            path: '/image-viewer',
            pageBuilder: (_, state) {
              final data = state.extra as Map<String, dynamic>?;
              final urls = List<String>.from(data?['urls'] ?? []);
              final index = data?['index'] as int? ?? 0;
              return CustomTransitionPage(
                key: const ValueKey('image-viewer'),
                child: GalleryViewer(imageUrls: urls, initialIndex: index),
                transitionDuration: const Duration(milliseconds: 300),
                transitionsBuilder: (_, animation, __, child) =>
                    FadeTransition(opacity: animation, child: child),
              );
            },
          ),
        ],
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/global_shortcuts.dart';
import '../widgets/app_shell.dart';
import '../pages/home/home_page.dart';
import '../pages/guide/guide_page.dart';
import '../pages/community/community_page.dart';
import '../pages/user/my_profile_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/settings/emoji_management.dart';
import '../pages/settings/editor_settings_page.dart';
import '../pages/settings/history_format_page.dart';
import '../pages/settings/shortcut_settings_page.dart';
import '../pages/settings/mt_image_manage_page.dart';
import '../pages/thread/thread_view_page.dart';
import '../pages/editor/editor_page.dart';
import '../pages/editor/editor_history_page.dart';
import '../pages/user/user_profile_page.dart';
import '../pages/browser/browser_page.dart';
import '../pages/search/search_page.dart';
import '../pages/history/history_page.dart';
import '../pages/darkroom_page.dart';
import '../widgets/image_preview/gallery_viewer.dart';

GoRouter buildRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (_, __, child) => GlobalShortcutsWrapper(child: child),
        routes: [
          ShellRoute(
            builder: (_, __, child) => AppShell(child: child),
            routes: [
              GoRoute(path: '/', builder: (_, __) => const HomePage()),
              GoRoute(path: '/guide', builder: (_, __) => const GuidePage()),
              GoRoute(
                path: '/community',
                builder: (_, __) => const CommunityPage(),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfilePage(),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: SettingsPage()),
          ),
          GoRoute(
            path: '/settings/emoji',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: EmojiManagementPage()),
          ),
          GoRoute(
            path: '/settings/editor',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: EditorSettingsPage()),
          ),
          GoRoute(
            path: '/thread/:tid',
            pageBuilder: (_, state) {
              final pageStr = state.uri.queryParameters['page'];
              final initialPage = int.tryParse(pageStr ?? '') ?? 1;
              return NoTransitionPage(
                child: ThreadViewPage(
                  tid: state.pathParameters['tid'] ?? '',
                  initialPage: initialPage,
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
            pageBuilder: (_, state) => NoTransitionPage(
              child: UserProfilePage(uid: state.pathParameters['uid'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/browser',
            pageBuilder: (_, state) => NoTransitionPage(
              child: BrowserPage(
                initialUrl: state.uri.queryParameters['url'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (_, __) => const NoTransitionPage(child: SearchPage()),
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
          GoRoute(
            path: '/settings/shortcuts',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: ShortcutSettingsPage()),
          ),
          GoRoute(
            path: '/settings/mt-images',
            pageBuilder: (_, __) =>
                const NoTransitionPage(child: MtImageManagePage()),
          ),
        ],
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'auth/providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/history_provider.dart';
import 'providers/search_history_provider.dart';
import 'providers/editor_history_provider.dart';
import 'config/site_config.dart';
import 'config/nav_config.dart';
import 'config/router.dart';
import 'core/emoji_loader.dart';
import 'api/forum/misc/export.dart' as forum_misc;
import 'services/credit_api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化站点配置默认值
  SiteConfig.init();

  final settings = SettingsProvider();
  await settings.load(); // 加载持久化站点列表覆盖默认值

  // 用 settings 中的站点配置初始化 ApiService
  await ApiService().init(baseUrl: SiteConfig.baseUrl);

  final auth = AuthProvider();
  await auth.tryRestore();

  final history = HistoryProvider();
  await history.load();
  // 同步最大记录数
  history.setMaxCount(settings.historyMaxCount);

  final searchHistory = SearchHistoryProvider();
  await searchHistory.load();

  final editorHistory = EditorHistoryProvider();
  // 同步编辑器配置到 EditorHistoryProvider
  editorHistory.minSnapshotWordCount = settings.minSnapshotWordCount;
  editorHistory.autoSaveInterval = Duration(seconds: settings.autoSaveInterval);
  editorHistory.maxAutoSnapshots = settings.maxAutoSnapshots;
  await editorHistory.cleanup(); // 清理过期会话

  // 根据设置初始化路由（默认启动 Tab）
  final router = buildRouter(
    initialLocation:
        navItems[settings.defaultTabIndex.clamp(0, navItems.length - 1)].path,
  );

  runApp(
    MyApp(
      auth: auth,
      settings: settings,
      history: history,
      searchHistory: searchHistory,
      editorHistory: editorHistory,
      router: router,
    ),
  );

  // 设置守卫：UI 启动后后台加载，不阻塞首帧渲染
  _runSettingsGuard(settings);
}

/// 设置守卫 — 启动时检测关键数据是否为空，自动触发刷新。
Future<void> _runSettingsGuard(SettingsProvider settings) async {
  final dio = ApiService().dio;

  final guards =
      <({bool Function() needsRefresh, Future<void> Function() refresh})>[
        (
          needsRefresh: () => !EmojiService().isLoaded,
          refresh: () => EmojiService().load(),
        ),
        (
          needsRefresh: () => SiteConfig.forums.isEmpty,
          refresh: () async {
            final result = await forum_misc.fetchForumNav(dio);
            if (result['success'] == true) {
              final forums =
                  (result['forums'] as Map<String, dynamic>?)?.map(
                    (k, v) => MapEntry(k, v.toString()),
                  ) ??
                  {};
              if (forums.isNotEmpty) {
                await settings.replaceForums(forums);
              }
            }
          },
        ),
        (
          needsRefresh: () =>
              settings.creditFormula == SettingsProvider.defaultFormula,
          refresh: () async {
            final result = await CreditApi.fetch();
            if (result['success'] == true && result['formula'] != null) {
              await settings.setCreditFormula(result['formula'] as String);
            }
          },
        ),
      ];

  for (final guard in guards) {
    if (guard.needsRefresh()) {
      await guard.refresh();
    }
  }
}

class MyApp extends StatelessWidget {
  final AuthProvider auth;
  final SettingsProvider settings;
  final HistoryProvider history;
  final SearchHistoryProvider searchHistory;
  final EditorHistoryProvider editorHistory;
  final GoRouter router;

  const MyApp({
    super.key,
    required this.auth,
    required this.settings,
    required this.history,
    required this.searchHistory,
    required this.editorHistory,
    required this.router,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: searchHistory),
        ChangeNotifierProvider.value(value: editorHistory),
      ],
      child: MaterialApp.router(
        title: 'MTBBS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'sans-serif',
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        routerConfig: router,
      ),
    );
  }
}

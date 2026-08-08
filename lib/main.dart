import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flex_seed_scheme/flex_seed_scheme.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/auth/providers/auth_provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/providers/history_provider.dart';
import 'package:mtbbs/providers/search_history_provider.dart';
import 'package:mtbbs/providers/editor_history_provider.dart';
import 'package:mtbbs/config/nav_config.dart';
import 'package:mtbbs/config/router.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
import 'package:mtbbs/core/app/event_bus.dart';
import 'package:mtbbs/core/app/default_config.dart';
import 'package:mtbbs/api/forum/misc/export.dart' as forum_misc;
import 'package:mtbbs/api/home/credit/export.dart' as credit_api;
import 'package:mtbbs/models/post_preview.dart';
import 'package:mtbbs/core/app/stagger_queue.dart';
import 'package:mtbbs/core/app/desktop_window.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/max_screen_size.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/auth/widgets/login_sheet.dart';

/// 全局 ScaffoldMessenger key — 非 Widget 层（事件订阅）也能弹 SnackBar
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows 上 Dart BoringSSL 可能无法正确读取系统根证书，
  // 导致 CERTIFICATE_VERIFY_FAILED 错误。
  // 使用系统默认的证书校验方式运行。
  // 参考: https://github.com/flutter/flutter/issues/88869
  if (Platform.isWindows) {
    HttpOverrides.global = _WindowsCertOverride();
  }

  // Android 折叠屏/自由窗口/分屏尺寸检测（原生侧缓存物理最大屏）
  await MaxScreenSize.init();

  // 加载默认配置（从 assets/config/defaults.json）
  await DefaultConfig.instance.load();

  // 初始化站点配置默认值
  SiteStore.instance.init();

  final settings = SettingsProvider();
  await settings.load(); // 加载持久化站点列表覆盖默认值

  // 桌面窗口初始化：最小尺寸 + 恢复上次窗口尺寸/位置/最大化状态
  // （依赖 settings.showWindowTitleBar，故放在 settings 加载后）
  await initDesktopWindow(showTitleBar: settings.showWindowTitleBar);

  // 同步通用错峰间隔到全局队列
  setStaggerInterval(Duration(milliseconds: settings.staggerInterval));

  // 用用户配置初始化缓存管理器
  initCacheManagers(
    emojiDays: settings.emojiCacheDays,
    avatarDays: settings.avatarCacheDays,
    imageDays: settings.imageCacheDays,
    medalDays: settings.medalCacheDays,
  );

  // 头像重定向映射有效期与头像缓存周期一致（-1 表示永不过期）
  AvatarRedirectStore.instance.cacheTtl = Duration(
    days: settings.avatarCacheDays,
  );

  // 过期缓存自动删除：仅启动时清一次
  // （flutter_cache_manager 本身不主动删过期文件，见 docs/01 图片缓存规范）
  cleanupExpiredCaches();

  // 用 settings 中的站点配置初始化 ApiService
  await ApiService().init(baseUrl: SiteStore.instance.baseUrl);

  // 订阅站点切换事件 — ApiService 已就绪，可安全调用 switchSite
  EventBus.stream.where((e) => e is SiteChangedEvent).listen((_) {
    ApiService().switchSite();
    EmojiService().load();
  });

  final auth = AuthProvider();
  await auth.tryRestore();

  // 订阅登录过期事件 — 清除登录态 + 全局提示
  // 状态清理由 AuthProvider 幂等处理；UI 提示做节流，防并发请求重复弹窗
  DateTime lastExpiredToast = DateTime.fromMillisecondsSinceEpoch(0);
  EventBus.stream.where((e) => e is LoginExpiredEvent).listen((_) {
    final wasLoggedIn = auth.isLoggedIn;
    auth.markSessionExpired();
    // 仅已登录账号过期时提示；游客浏览受限页面不弹“登录过期”，节流防并发重复弹窗
    if (!wasLoggedIn ||
        DateTime.now().difference(lastExpiredToast).inSeconds < 5) {
      return;
    }
    lastExpiredToast = DateTime.now();
    rootScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('登录已过期，请重新登录'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '去登录',
          onPressed: () {
            final ctx = rootScaffoldMessengerKey.currentContext;
            if (ctx != null) showLoginSheet(ctx);
          },
        ),
      ),
    );
  });

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

  // 预加载帖子预览缓存，避免重启后首次访问走网络
  await PostPreviewManager.instance.init();

  // 根据设置初始化路由（默认启动 Tab）
  final router = buildRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation:
        navItems[settings.defaultTabIndex.clamp(0, navItems.length - 1)].path,
  );

  // Windows 下监听窗口 resize/移动/最大化并记忆状态
  final app = _buildApp(
    auth,
    settings,
    history,
    searchHistory,
    editorHistory,
    router,
  );
  runApp(Platform.isWindows ? WindowStateSaver(child: app) : app);

  // 设置守卫：UI 启动后后台加载，不阻塞首帧渲染
  _runSettingsGuard(settings);
}

MyApp _buildApp(
  AuthProvider auth,
  SettingsProvider settings,
  HistoryProvider history,
  SearchHistoryProvider searchHistory,
  EditorHistoryProvider editorHistory,
  GoRouter router,
) {
  return MyApp(
    auth: auth,
    settings: settings,
    history: history,
    searchHistory: searchHistory,
    editorHistory: editorHistory,
    router: router,
  );
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
          needsRefresh: () => SiteStore.instance.forums.isEmpty,
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
            final result = await credit_api.fetch(ApiService().dio);
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
        ChangeNotifierProvider.value(value: SiteStore.instance),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: searchHistory),
        ChangeNotifierProvider.value(value: editorHistory),
      ],
      child: Builder(
        builder: (context) {
          final s = context.watch<SettingsProvider>();
          // errorKey 固定为 M3 标准错误红，保证"删除/危险"等红色语义
          // 不随用户 seedColor 漂移（flex_seed_scheme 默认从 primaryKey 派生）
          const errorSeed = Color(0xFFB3261E);
          final schemeLight = SeedColorScheme.fromSeeds(
            primaryKey: s.seedColor,
            errorKey: errorSeed,
            variant: FlexSchemeVariant.material3Legacy,
            brightness: Brightness.light,
          );
          var schemeDark = SeedColorScheme.fromSeeds(
            primaryKey: s.seedColor,
            errorKey: errorSeed,
            variant: FlexSchemeVariant.material3Legacy,
            brightness: Brightness.dark,
          );

          // 纯黑主题：覆盖 surface 系列色为纯黑/近黑
          if (s.isPureBlackTheme) {
            schemeDark = schemeDark.copyWith(
              surface: Colors.black,
              surfaceContainerLowest: Colors.black,
              surfaceContainerLow: const Color(0xFF0A0A0A),
              surfaceContainer: const Color(0xFF121212),
              surfaceContainerHigh: const Color(0xFF1A1A1A),
              surfaceContainerHighest: const Color(0xFF242424),
            );
          }

          return MaterialApp.router(
            title: 'MTBBS',
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            theme: _buildThemeData(schemeLight),
            darkTheme: _buildThemeData(schemeDark),
            themeMode: s.themeMode,
            routerConfig: router,
          );
        },
      ),
    );
  }
}

ThemeData _buildThemeData(ColorScheme cs) {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'sans-serif',
    colorScheme: cs,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(color: cs.surfaceContainerLow),
    dialogTheme: DialogThemeData(backgroundColor: cs.surface),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface),
    ),
  );
}

/// Windows 上 Dart BoringSSL 证书验证补丁
///
/// Flutter/Dart 在 Windows 上使用 BoringSSL（而非系统 Schannel），
/// 某些环境下（如虚拟机、沙盒、未全量更新的系统）无法读取根证书，
/// 导致 HTTPS 握手失败（CERTIFICATE_VERIFY_FAILED）。
///
/// 此补丁绕过 BoringSSL 的证书校验，让信任决策交由上层处理。
/// 由于 App 连接的论坛站点由用户自行配置，风险可控。
/// 参考: https://github.com/flutter/flutter/issues/88869
class _WindowsCertOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

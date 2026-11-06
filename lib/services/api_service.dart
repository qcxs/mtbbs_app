import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:charset/charset.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/js_challenge_solver.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/browse_mode.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/core/settings/settings_repository.dart';
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_util.dart';

part 'api_service_client.dart';
part 'api_service_recovery.dart';

/// 请求级标记：本次请求已由拦截页处理器处理过，避免递归触发。
const String kInterstitialHandledFlag = 'mtbbsInterstitialHandled';

/// Discuz「浏览方式」Cookie 的名字后缀 —— `{前缀}_mobile`。
///
/// 前缀（MT 论坛是 `cQWy_2132_`）由站点配置决定，所以按后缀匹配，不写死全名。
const String kBrowseModeCookieSuffix = '_mobile';

/// 拦截页恢复上下文 —— "这次被拦的请求属于哪个客户端 / 罐 / 站点"。
///
/// 无状态化后 Dio 不再唯一（全局 + 各站点作用域），恢复流程不能再从
/// `SiteStore` / `activeCookieJar` 猜；由拦截器显式传入，验证结果才能写回
/// 正确的罐（跨站点页面验证自己的站点，而不是全局活跃罐）。
class InterstitialContext {
  final Dio client;
  final CookieJar jar;
  final String baseUrl;

  /// 这个客户端是否为全局 [ApiService.dio]（而不是站点作用域 Dio）。
  ///
  /// 全局客户端的罐 / baseUrl 会在切账号、切站点时被换掉，验证流程因此要区别
  /// 对待（是否镜像到其它罐、登录 cookie 从 `AuthProvider` 取还是从罐里取）。
  /// 显式标记而不是 `identical(ctx.client, ApiService().dio)`：`dio` 是 `late final`，
  /// 初始化前访问会抛 `LateInitializationError`（见 docs/07 #105）。
  final bool isGlobal;

  const InterstitialContext({
    required this.client,
    required this.jar,
    required this.baseUrl,
    this.isGlobal = false,
  });
}

/// API 服务 — 基于 Dio + CookieManager 的统一 HTTP 客户端
///
/// Cookie 按站点隔离：
/// - 游客：`$appDocDir/cookies/{host}/`
/// - 用户：`$appDocDir/cookies/{host}/{accountName}/`
///
/// 站点切换时通过 [switchSite] 重新创建 guest jar。
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  late final Dio dio;
  PersistCookieJar? _guestJar;

  /// 拦截页处理器 —— 由 app 层注入（见 main.dart 的 `VerificationGate`）。
  ///
  /// 返回 true 表示"已通过人机验证"。做成注入点而不是直接依赖 UI/WebView，
  /// 是为了让 services 层不反向依赖 pages / flutter_inappwebview。
  ///
  /// 无状态化后 Dio 不再唯一（全局 + 各站点作用域），处理器必须知道"这次用的是
  /// 哪个客户端 / 罐 / 站点"，否则验证结果会写进错误的罐。
  Future<bool> Function(RequestOptions options, InterstitialContext ctx)?
  interstitialHandler;

  /// 当前活跃的 CookieJar（游客或当前账号）—— 写入目标
  CookieJar? _activeJar;

  String? _activeAccount;
  String _currentHost = '';
  bool _initialized = false;

  /// 「浏览方式」Cookie 过滤器 —— 必须排在 `CookieManager` **之后**。
  ///
  /// `dio_cookie_manager` 的 `onRequest` 会把罐里的 Cookie 合并成一个
  /// `name=value; name2=value2` 字符串写进 `cookie` 头，没有"过滤某一条"的钩子；
  /// `cookie_jar` 也没有按名删除的接口（4.0.9 的
  /// `delete(uri, [bool withDomainSharedCookie])` 是按 URI 整体删）。
  /// 所以在它之后把该条从请求头里摘掉即可 —— 纯请求级编辑，不碰用户罐里的数据。
  late final InterceptorsWrapper _browseModeFilter = InterceptorsWrapper(
    onRequest: (options, handler) {
      _dropBrowseModeCookie(options);
      handler.next(options);
    },
  );

  /// 当前活跃账号名，null 表示游客
  String? get activeAccount => _activeAccount;

  /// 当前活跃的 CookieJar —— 供 Cookie 反向同步（WebView → Dio）等场景写入。
  ///
  /// Dio 内部通过拦截器持有它，外部拿不到；这里显式暴露一个引用。
  CookieJar? get activeCookieJar => _activeJar ?? _guestJar;

  Future<void> init({String? baseUrl}) async {
    if (_initialized) return;

    _currentHost = SiteStore.instance.host;
    _guestJar = PersistCookieJar(
      storage: FileStorage(await AppPaths.cookiesDirForHost(_currentHost)),
      ignoreExpires: true,
    );
    final url = baseUrl ?? SiteStore.instance.baseUrl;
    dio = _createDio(url, _guestJar!, isGlobal: true);
    _activeJar = _guestJar!;
    _initialized = true;
  }

  // ==================== 站点作用域 Dio（无状态化） ====================

  /// 作用域 Dio 缓存：`{host}|{账号}` → Dio。
  ///
  /// 与全局 [dio] 并列存在：跨站点页面用这里的 Dio 访问目标站点，
  /// 全局 [dio] 的行为与以前完全一致（零迁移成本）。
  final Map<String, Dio> _scopedDios = {};

  /// 作用域 Dio 的 CookieJar（供验证流程 / 图片下载取 Cookie 用）
  final Map<String, CookieJar> _scopedJars = {};

  String _scopeKey(String host, String? account) => '$host|${account ?? ''}';

  /// 获取（必要时创建）绑定到指定站点 + 账号的 Dio。
  ///
  /// [account] 为 null 表示游客罐（`cookies/{host}/`），否则为账号罐
  /// （`cookies/{host}/{account}/`）—— 与全局切换用的是同一套磁盘目录，
  /// 因此登录态、人机验证 Cookie 都是共享的，不存在"两套登录态"。
  Future<Dio> scopedDio({
    required String host,
    required String baseUrl,
    String? account,
  }) async {
    final key = _scopeKey(host, account);
    final cached = _scopedDios[key];
    if (cached != null) return cached;

    final dir = account == null
        ? await AppPaths.cookiesDirForHost(host)
        : await AppPaths.cookiesDirForAccount(host, account);
    final jar = PersistCookieJar(
      storage: FileStorage(dir),
      ignoreExpires: true,
    );
    final d = _createDio(baseUrl, jar);
    _scopedDios[key] = d;
    _scopedJars[key] = jar;
    return d;
  }

  /// 取作用域 CookieJar（图片 / 验证等非 Dio 场景需要带上登录 Cookie）
  CookieJar? scopedJar({required String host, String? account}) =>
      _scopedJars[_scopeKey(host, account)];

  /// 丢弃某站点的全部作用域 Dio（账号登录态变化 / 站点配置变更后重建）
  void dropScopedForHost(String host) {
    final keys = _scopedDios.keys
        .where((k) => k.startsWith('$host|'))
        .toList(growable: false);
    for (final k in keys) {
      _scopedDios.remove(k);
      _scopedJars.remove(k);
    }
  }

  /// 切换站点 — 更新 baseUrl + 重建 guest jar
  Future<void> switchSite() async {
    _currentHost = SiteStore.instance.host;
    final newUrl = SiteStore.instance.baseUrl;
    dio.options.baseUrl = newUrl;
    dio.options.headers['User-Agent'] = Site.uaPc;

    _guestJar = PersistCookieJar(
      storage: FileStorage(await AppPaths.cookiesDirForHost(_currentHost)),
      ignoreExpires: true,
    );
    _replaceCookieManager(_guestJar!);
    _activeAccount = null;
  }

  /// 切换到指定账号的 CookieJar（路径含 host）
  Future<void> switchToAccount(String accountName) async {
    final jar = PersistCookieJar(
      storage: FileStorage(
        await AppPaths.cookiesDirForAccount(_currentHost, accountName),
      ),
      ignoreExpires: true,
    );
    _replaceCookieManager(jar);
    _activeAccount = accountName;
  }

  /// 切换到游客 CookieJar
  Future<void> switchToGuest() async {
    _replaceCookieManager(_guestJar!);
    _activeAccount = null;
  }

  /// 删除指定账号的磁盘 Cookie 文件
  Future<void> deleteAccountJar(String accountName) async {
    final storagePath = await AppPaths.cookiesDirForAccount(
      _currentHost,
      accountName,
    );
    final dir = Directory(storagePath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    if (_activeAccount == accountName) {
      await switchToGuest();
    }
  }

  /// 删除当前站点所有账号的 Cookie 目录
  Future<void> deleteAllAccountJars() async {
    final sitePath = await AppPaths.cookiesDirForHost(_currentHost);
    final siteDir = Directory(sitePath);
    if (await siteDir.exists()) {
      await siteDir.delete(recursive: true);
    }
    _guestJar = PersistCookieJar(
      storage: FileStorage(sitePath),
      ignoreExpires: true,
    );
    _replaceCookieManager(_guestJar!);
    _activeAccount = null;
  }

  void _replaceCookieManager(CookieJar jar) {
    _activeJar = jar;
    dio.interceptors.removeWhere((i) => i is CookieManager);
    dio.interceptors.remove(_browseModeFilter);
    // 顺序有意义：CookieManager 先把罐里的 Cookie 合成请求头，过滤器才能从里面
    // 摘掉「浏览方式」Cookie
    dio.interceptors.insertAll(0, [CookieManager(jar), _browseModeFilter]);
  }
}

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
import 'package:mtbbs/core/utils/formatters.dart';
import 'package:mtbbs/core/utils/logger.dart';

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

  /// 浏览器默认 Accept（模拟浏览器访问时使用）
  static const String _browserAccept =
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

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

  /// 构建绑定指定 baseUrl + CookieJar 的 Dio（含全部拦截器）。
  ///
  /// 全局 [dio] 与跨站点作用域 Dio（见 [scopedDio]）共用同一套拦截器逻辑，
  /// 只有 baseUrl / CookieJar 不同 —— 这样"cookie 绑定在单例上"的限制被解开。
  /// [isGlobal] 标记"这个 Dio 是否就是全局 [dio]" —— 只有它的罐 / baseUrl 会
  /// 在切账号、切站点时被替换，恢复流程需要取实时值。
  Dio _createDio(String baseUrl, CookieJar jar, {bool isGlobal = false}) {
    final d = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // 默认 UA 为 PC 版（Discuz 按 UA 返回不同模板）；
        // 个别接口（导读/版块/我的帖子）按需用 Options 覆盖为站点配置 UA
        headers: {
          // 功能性头：UA 决定 Discuz 返回哪套模板，
          // X-Requested-With 决定是否按 AJAX 格式返回（去掉会拿到整页 HTML）
          'User-Agent': Site.uaPc,
          'X-Requested-With': 'XMLHttpRequest',
          // 浏览器仿真头：按设置开关决定是否携带
          if (_simulateBrowserHeaders) ...{
            'Referer': baseUrl,
            'Accept': _browserAccept,
          },
        },
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseDecoder: (bytes, options, responseBody) {
          try {
            String? charset;
            final ct = responseBody.headers['content-type']?.join(';');
            if (ct != null) {
              final m = RegExp(
                r'charset=([^;\s]+)',
                caseSensitive: false,
              ).firstMatch(ct);
              if (m != null) charset = m.group(1)!.toLowerCase();
            }
            // 响应头指定了编码 → 按指定编码解码
            if (charset != null && !['utf-8', 'utf8'].contains(charset)) {
              if (['gbk', 'gb2312'].contains(charset)) {
                return gbk.decode(bytes);
              }
              final encoding = Encoding.getByName(charset);
              if (encoding != null) return encoding.decode(bytes);
            }
            // 未指定编码 → 先试 UTF-8，若产生替换字符则试 GBK
            final utf8Result = utf8.decode(bytes, allowMalformed: true);
            if (charset == null && utf8Result.contains('\uFFFD')) {
              try {
                final gbkResult = gbk.decode(bytes);
                if (!gbkResult.contains('\uFFFD')) return gbkResult;
              } catch (_) {}
            }
            return utf8Result;
          } catch (_) {
            return utf8.decode(bytes, allowMalformed: true);
          }
        },
      ),
    );

    // 顺序有意义：CookieManager 先把罐里的 Cookie 合成请求头，过滤器才能从里面
    // 摘掉「浏览方式」Cookie
    d.interceptors.add(CookieManager(jar));
    d.interceptors.add(_browseModeFilter);

    // 统一日志 + 错误处理拦截器
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['_start'] = DateTime.now().millisecondsSinceEpoch;
          final path = options.path;
          final method = options.method;
          final qp = options.queryParameters;
          // 查询参数仅显示非空值，且太长时截断
          final queryStr = qp.entries
              .where((e) => e.value != null && e.value.toString().isNotEmpty)
              .map((e) => '${e.key}=${e.value}')
              .join('&');
          final fullPath = queryStr.isNotEmpty ? '$path?$queryStr' : path;
          AppLogger.i('DIO', '$method $fullPath');
          handler.next(options);
        },
        onResponse: (response, handler) async {
          final path = response.requestOptions.path;
          final status = response.statusCode ?? 0;
          final size = (response.data as String?)?.length ?? 0;
          final start = response.requestOptions.extra['_start'] as int?;
          final elapsed = start != null
              ? DateTime.now().millisecondsSinceEpoch - start
              : 0;
          AppLogger.i(
            'DIO',
            '$path → $status (${formatBytes(size)}, ${elapsed}ms)',
          );
          // 通用拦截页（人机验证 / 防火墙）：交由注入的处理器恢复，成功后重放。
          //
          // 全局 Dio 的罐 / baseUrl 在切账号、切站点后会被换掉（见
          // switchToAccount / switchSite），这里必须取**实时值**：上面闭包捕获的
          // 只是创建时的快照，用它会把自解 cookie 写进已被替换的旧罐、或按旧站点
          // 域写入 —— 症状是"验证过了还是被拦"，且因为自解返回成功而不再回退
          // WebView。作用域 Dio 的二者创建后不变，直接用捕获值。
          final liveJar = isGlobal ? (activeCookieJar ?? jar) : jar;
          final liveBaseUrl = isGlobal ? d.options.baseUrl : baseUrl;
          if (await _recoverFromInterstitial(
            response,
            client: d,
            jar: liveJar,
            baseUrl: liveBaseUrl,
            isGlobal: isGlobal,
          )) {
            try {
              handler.resolve(await d.fetch(response.requestOptions));
              return;
            } catch (e) {
              AppLogger.w('DIO', '$path 拦截页重放失败: $e');
            }
          }
          handler.next(response);
        },
        onError: (error, handler) {
          final path = error.requestOptions.path;
          if (error.response != null) {
            final status = error.response!.statusCode ?? 0;
            final size = (error.response!.data as String?)?.length ?? 0;
            if (status == 403) {
              AppLogger.w('DIO', '$path → 403 可能需要重新登录');
            } else if (status == 404) {
              AppLogger.w('DIO', '$path → 404 ($size)');
            } else if (status >= 500) {
              AppLogger.e('DIO', '$path → $status 服务器错误');
            } else {
              AppLogger.w('DIO', '$path → $status ($size)');
            }
          } else {
            AppLogger.e('DIO', '$path 网络错误: ${error.message}');
          }
          handler.next(error);
        },
      ),
    );

    // 请求级「浏览模式」覆盖：仅在处于覆盖态（探针一次运行 / MCP 单次调用）时，
    // 把**每个请求**的 UA 改写为覆盖值 —— 这样"不显式设站点 UA 的接口"
    // （帖子详情/排行/在线/圈子/留言板…）也会一起换成指定模板，
    // 从而让"换 UA 复测所有 API"成立。无覆盖时完全不干预（默认 PC UA 保持）。
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (browseModeOverrideActive()) {
            options.headers['User-Agent'] = resolveRequestUserAgent();
          }
          handler.next(options);
        },
      ),
    );

    return d;
  }

  // ==================== 站点作用域 Dio（无状态化） ====================

  /// 作用域 Dio 缓存：`{host}|{账号}` → Dio。
  ///
  /// 与全局 [dio] 并列存在：跨站点页面用这里的 Dio 访问目标站点，
  /// 全局 [dio] 的行为与以前完全一致（零迁移成本）。
  final Map<String, Dio> _scopedDios = {};

  /// 作用域 Dio 的 CookieJar（供验证流程 / 图片下载取 Cookie 用）
  final Map<String, CookieJar> _scopedJars = {};

  String _scopeKey(String host, String? account) =>
      '$host|${account ?? ''}';

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

  /// 按当前开关状态刷新 Dio 默认头。
  ///
  /// 关闭时只移除 Referer / Accept，User-Agent 与 X-Requested-With 是
  /// 功能性头，始终保留。
  ///
  /// [init] 尚未完成时直接返回 —— 那时模块级开关已是最终值，init 会读它。
  void refreshBrowserHeaders() {
    if (!_initialized) return;
    final all = <Dio>[dio, ..._scopedDios.values];
    for (final d in all) {
      final headers = d.options.headers;
      if (_simulateBrowserHeaders) {
        headers['Referer'] = d.options.baseUrl;
        headers['Accept'] = _browserAccept;
      } else {
        headers.remove('Referer');
        headers.remove('Accept');
      }
    }
  }

  /// 切换站点 — 更新 baseUrl + 重建 guest jar
  Future<void> switchSite() async {
    _currentHost = SiteStore.instance.host;
    final newUrl = SiteStore.instance.baseUrl;
    dio.options.baseUrl = newUrl;
    dio.options.headers['User-Agent'] = Site.uaPc;
    // Referer 要跟着新站点走；开关关闭时这里只会移除它
    refreshBrowserHeaders();

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

  /// 把验证流程新拿到的**客户端级 cookie**（人机验证 / 防火墙）补写到本站点的
  /// **每一个罐**：游客罐 + 其余账号罐。
  ///
  /// 这类 cookie 与登录账号无关（按 IP / UA 下发），而罐按 `{host}/{账号}` 隔离；
  /// 只写活跃罐的话，切账号 / 切游客 / 重启落到别的罐就要重新验证。
  ///
  /// 为什么不是"一个站点共享罐"：那得额外回答三个问题——谁有资格进共享罐（准入）、
  /// 同名时哪个罐的值胜出（优先级）、共享罐何时刷新（服务端只会刷新活跃罐）。
  /// 补写进每个罐，这三个问题都不存在：各自的副本随该罐被激活时由服务端正常刷新。
  /// 代价是**新建账号要多验证一次**。
  ///
  /// [cookies] 取自 `syncWebViewCookiesToJar` 的返回值，已是"活跃罐里原本没有的"
  /// 名字 —— 只含新出现的客户端级 cookie，不会把账号登录态扩散到别的罐。
  Future<void> mirrorToAllJarsForHost(List<Cookie> cookies) async {
    if (cookies.isEmpty) return;
    final uri = Uri.tryParse(SiteStore.instance.baseUrl);
    if (uri == null || uri.host.isEmpty) return;

    // 活跃罐已由回流流程写入，这里只补其它罐
    if (_activeAccount != null) {
      await _mirror(uri, cookies, _guestJar);
    }

    final account = _activeAccount;
    final activeDir = account == null
        ? null
        : (await AppPaths.cookiesDirForAccount(
            _currentHost,
            account,
          )).replaceAll('\\', '/');
    for (final dir in await AppPaths.accountJarDirsForHost(_currentHost)) {
      if (activeDir != null && dir.replaceAll('\\', '/') == activeDir) continue;
      await _mirror(
        uri,
        cookies,
        PersistCookieJar(storage: FileStorage(dir), ignoreExpires: true),
      );
    }
  }

  Future<void> _mirror(Uri uri, List<Cookie> cookies, CookieJar? jar) async {
    if (jar == null) return;
    try {
      await jar.saveFromResponse(uri, cookies);
    } catch (e) {
      AppLogger.w('PAGE', '补写客户端级 cookie 到其它罐失败: $e');
    }
  }

  /// 从请求头里摘掉站点「浏览方式」Cookie（`{前缀}_mobile`），避免它盖过 App 的
  /// 「浏览模式」。
  ///
  /// Discuz 的优先级是 **`*_mobile` Cookie 高于 UA**：站点"该页面无手机版"提示里的
  /// 「继续访问电脑版」链接（`…&mobile=no`）会写下 `{前缀}_mobile=no`，此后**该罐内
  /// 所有请求**都被强制按 PC 模板返回，UA 完全不参与决策。实测同一手机 UA、同一 URL：
  /// 罐里没有它 → 173.5 KB 移动卡片；有它 → 89.0 KB PC 表格。
  ///
  /// 症状之所以"怪"：重新登录不会清它、`Max-Age` 还会被反复续期（表现为「移动版」
  /// 永久失效）；CookieJar 按账号隔离（`cookies/{host}/{账号}/`），所以换一个账号
  /// 就正常。
  ///
  /// App 的「浏览模式」是显式设置，不该被一条历史遗留的服务端偏好悄悄覆盖。
  /// 只改本次请求的头、不删罐里的数据 —— 罐里那条会自然过期（`Max-Age=3600`），
  /// 而只要不发送它，站点就回到按 UA 决策。
  void _dropBrowseModeCookie(RequestOptions options) {
    final key = options.headers.keys.firstWhere(
      (k) => k.toLowerCase() == HttpHeaders.cookieHeader,
      orElse: () => '',
    );
    if (key.isEmpty) return;
    final raw = options.headers[key];
    if (raw is! String || raw.isEmpty) return;

    final parts = raw.split(';');
    final kept = parts
        .where(
          (p) => !p.trim().split('=').first.endsWith(kBrowseModeCookieSuffix),
        )
        .toList();
    if (kept.length == parts.length) return;

    // 与 CookieManager 的写法保持一致：空则置 null（Dio 会省略该头）
    options.headers[key] = kept.isEmpty
        ? null
        : kept.map((p) => p.trim()).join('; ');
    AppLogger.i('DIO', '已剔除请求中的浏览方式 Cookie（它会强制 PC 模板）');
  }

  /// 命中"非论坛页"（人机验证 / 防火墙拦截页）时尝试自动恢复。
  ///
  /// 两级恢复：
  /// 1. **本地自解**——执行挑战页脚本，拿到它写下的 cookie 或它要求跳转的地址，
  ///    与浏览器一样无感（见 [JsChallengeSolver]）；
  /// 2. **人工验证弹窗**——自解不了（滑块 / 点选等交互式验证、脚本结构变化）才
  ///    弹出内置浏览器让用户完成（[VerificationGate]）。
  ///
  /// 返回 true 表示**已通过验证且可以重放本次请求**（打了重放标记）。
  /// 仅 GET 自动重放：写操作（发帖/评论）重放有重复提交风险，验证通过后
  /// 交给用户手动重试。
  Future<bool> _recoverFromInterstitial(
    Response<dynamic> response, {
    required Dio client,
    required CookieJar jar,
    required String baseUrl,
    bool isGlobal = false,
  }) async {
    final options = response.requestOptions;
    if (options.extra[kInterstitialHandledFlag] == true) return false;
    if (response.statusCode != 200) return false;

    final body = response.data;
    if (body is! String || body.isEmpty) return false;
    // Discuz 的 ajax 响应被 `<root><![CDATA[…]]></root>` / `<?xml …?>` 包着，
    // 那是"片段"而不是一个独立页面；WAF 拦截不会包这层壳。
    // 用"是否 CDATA/XML 包装"排除，比按 inajax 参数排除更准 —— 后者会漏掉
    // 同样会被拦截的写操作（发帖/评论）。
    final head = body.trimLeft();
    if (body.contains('<![CDATA[') || head.startsWith('<?xml')) return false;
    if (!looksLikeInterstitialPage(
      body,
      response.headers.value('content-type'),
    )) {
      return false;
    }

    AppLogger.w('DIO', '${options.path} 命中非论坛页（${body.length}B），尝试自动恢复');

    // ① 本地自解（JS 引擎执行挑战页脚本）：成功即与浏览器一样无感
    if (await _solveJsChallengeLocally(
      body,
      options.uri,
      client: client,
      jar: jar,
      baseUrl: baseUrl,
    )) {
      if (options.method != 'GET') {
        AppLogger.i('DIO', '${options.path} 已本地自解验证，但非 GET 请求不自动重放');
        return false;
      }
      AppLogger.i('DIO', '${options.path} 已本地自解验证，重放请求');
      options.extra[kInterstitialHandledFlag] = true;
      return true;
    }

    // ② 自解不了（交互式验证 / 结构变化）→ 交给人工验证弹窗。
    //    把本次请求的客户端 / 罐 / 站点一起传过去：跨站点页面也能验证，
    //    cookie 回流到它自己的罐，而不是"只能回流全局活跃罐故不启用"。
    final recover = interstitialHandler;
    if (recover == null) return false;
    final recovered = await recover(
      options,
      InterstitialContext(
        client: client,
        jar: jar,
        baseUrl: baseUrl,
        isGlobal: isGlobal,
      ),
    );
    if (!recovered) {
      AppLogger.w('DIO', '${options.path} 未通过人机验证，按原样返回');
      return false;
    }
    if (options.method != 'GET') {
      AppLogger.i('DIO', '${options.path} 已通过验证，但非 GET 请求不自动重放');
      return false;
    }
    AppLogger.i('DIO', '${options.path} 已通过验证，重放请求');
    options.extra[kInterstitialHandledFlag] = true;
    return true;
  }

  /// 本地自解 JS 挑战，并让结果生效。
  ///
  /// 两种收尾方式（见 [JsChallengeSolution]）：
  /// - **脚本写了 cookie**（如阿里云 ESA 的 `acw_sc__v2`）：写进当前活跃罐即可。
  ///   同一响应的 `Set-Cookie` 已由 `CookieManager` 落罐（`acw_tc` / `cdn_sec_tc`），
  ///   三者必须配对；**刻意不做跨罐镜像**：`acw_sc__v2` 与"本轮下发的 arg1"绑定，
  ///   复制到别的罐会与那边的 `acw_tc` 错配。
  /// - **脚本要求跳转**（如网宿 WZWS 的 `?wzwschallenge=…`）：用同一个 Dio 把该地址
  ///   请求一次。服务端认可后会 302 回原地址并直接给真实页面，同时把本客户端
  ///   （IP + UA 指纹）标记为已通过——此后普通请求一段时间内不再被挑战，**无需 cookie**。
  ///
  /// 失败（脚本结构变化 / 跳转仍被拦）返回 false，由调用方回退到 WebView。
  Future<bool> _solveJsChallengeLocally(
    String body,
    Uri pageUri, {
    required Dio client,
    required CookieJar jar,
    required String baseUrl,
  }) async {
    final solution = JsChallengeSolver.instance.solve(
      body,
      pageUrl: pageUri.toString(),
    );
    if (solution == null || solution.isEmpty) return false;

    final base = Uri.tryParse(baseUrl);
    if (base == null || base.host.isEmpty) return false;

    if (solution.cookies.isNotEmpty) {
      try {
        await jar.saveFromResponse(
          base,
          solution.cookies.entries
              .map(
                (e) => Cookie(e.key, e.value)
                  ..domain = '.${base.host}'
                  ..path = '/',
              )
              .toList(),
        );
        AppLogger.i('DIO', 'JS 挑战自解：写入 ${solution.cookies.length} 个 cookie');
        return true;
      } catch (e) {
        AppLogger.w('DIO', 'JS 挑战自解 cookie 写入失败: $e');
        return false;
      }
    }

    // 只允许同站点跳转：地址来自挑战页脚本，不能拿它去请求别的主机
    final raw = solution.redirectUrl!;
    final parsed = Uri.tryParse(raw);
    final target = parsed == null
        ? null
        : (parsed.hasScheme ? parsed : base.resolveUri(parsed));
    if (target == null || target.host != base.host) {
      AppLogger.w('DIO', 'JS 挑战自解：忽略跨站跳转 $raw');
      return false;
    }

    try {
      final res = await client.get<String>(
        target.toString(),
        options: Options(
          // 该请求自己也可能被拦，但这里不再递归自解，失败就交给 L2
          extra: {kInterstitialHandledFlag: true},
        ),
      );
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 400) {
        AppLogger.w('DIO', 'JS 挑战自解：跳转返回 $status');
        return false;
      }
      final text = res.data ?? '';
      if (looksLikeInterstitialPage(text, res.headers.value('content-type'))) {
        AppLogger.w('DIO', 'JS 挑战自解：跳转后仍是拦截页');
        return false;
      }
      AppLogger.i('DIO', 'JS 挑战自解：完成跳转验证（${target.path}）');
      return true;
    } catch (e) {
      AppLogger.w('DIO', 'JS 挑战自解跳转失败: $e');
      return false;
    }
  }
}

// ==================== 浏览器仿真头 ====================

/// 是否携带 `Referer` / `Accept` 等"浏览器仿真头"，默认开启。
///
/// 放在模块级而不是 [ApiService] 的实例字段上：`SettingsProvider.load()`
/// 早于 `ApiService.init()` 执行，那时实例还没建好、`dio` 也不存在。
/// init 会读这个值构建请求头，因此设置能在任何时机安全写入。
bool _simulateBrowserHeaders = true;

/// 当前是否携带浏览器仿真头（图片下载等非 Dio 请求共用此状态）
bool browserHeadersEnabled() => _simulateBrowserHeaders;

/// 开关浏览器仿真头，立即作用于后续请求。
void applyBrowserHeaders(bool enabled) {
  _simulateBrowserHeaders = enabled;
  ApiService().refreshBrowserHeaders();
}

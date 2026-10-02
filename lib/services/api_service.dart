import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:charset/charset.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/app_paths.dart';
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
  Future<bool> Function(RequestOptions options)? interstitialHandler;

  /// 当前活跃的 CookieJar（游客或当前账号）
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
    dio = Dio(
      BaseOptions(
        baseUrl: url,
        // 默认 UA 为 PC 版（Discuz 按 UA 返回不同模板）；
        // 个别接口（导读/版块/我的帖子）按需用 Options 覆盖为站点配置 UA
        headers: {
          // 功能性头：UA 决定 Discuz 返回哪套模板，
          // X-Requested-With 决定是否按 AJAX 格式返回（去掉会拿到整页 HTML）
          'User-Agent': Site.uaPc,
          'X-Requested-With': 'XMLHttpRequest',
          // 浏览器仿真头：按设置开关决定是否携带
          if (_simulateBrowserHeaders) ...{
            'Referer': url,
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

    _replaceCookieManager(_guestJar!);
    // 统一日志 + 错误处理拦截器
    dio.interceptors.add(
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
          // 通用拦截页（人机验证 / 防火墙）：交由注入的处理器恢复，成功后重放
          if (await _recoverFromInterstitial(response)) {
            try {
              handler.resolve(await dio.fetch(response.requestOptions));
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

    _initialized = true;
  }

  /// 按当前开关状态刷新 Dio 默认头。
  ///
  /// 关闭时只移除 Referer / Accept，User-Agent 与 X-Requested-With 是
  /// 功能性头，始终保留。
  ///
  /// [init] 尚未完成时直接返回 —— 那时模块级开关已是最终值，init 会读它。
  void refreshBrowserHeaders() {
    if (!_initialized) return;
    final headers = dio.options.headers;
    if (_simulateBrowserHeaders) {
      headers['Referer'] = dio.options.baseUrl;
      headers['Accept'] = _browserAccept;
    } else {
      headers.remove('Referer');
      headers.remove('Accept');
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
  /// 返回 true 表示**已通过验证且可以重放本次请求**（打了重放标记）。
  /// 仅 GET 自动重放：写操作（发帖/评论）重放有重复提交风险，验证通过后
  /// 交给用户手动重试。POST 命中时同样会触发验证弹窗，只是不自动重放。
  Future<bool> _recoverFromInterstitial(Response<dynamic> response) async {
    final recover = interstitialHandler;
    if (recover == null) return false;

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
    final recovered = await recover(options);
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

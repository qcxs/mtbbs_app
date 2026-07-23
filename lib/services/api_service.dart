import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';
import '../config/site_config.dart';
import '../core/site_store.dart';
import '../core/logger.dart';

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
  String? _activeAccount;
  String _currentHost = '';
  bool _initialized = false;

  /// 当前活跃账号名，null 表示游客
  String? get activeAccount => _activeAccount;

  Future<void> init({String? baseUrl}) async {
    if (_initialized) return;

    _currentHost = SiteStore.instance.host;
    final dir = await getApplicationDocumentsDirectory();
    _guestJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/${SiteConfig.cookieDir}/$_currentHost'),
      ignoreExpires: true,
    );

    final url = baseUrl ?? SiteStore.instance.baseUrl;
    dio = Dio(
      BaseOptions(
        baseUrl: url,
        headers: {
          'User-Agent': Site.uaPc,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    dio.interceptors.add(CookieManager(_guestJar!));
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
        onResponse: (response, handler) {
          final path = response.requestOptions.path;
          final status = response.statusCode ?? 0;
          final size = (response.data as String?)?.length ?? 0;
          final start = response.requestOptions.extra['_start'] as int?;
          final elapsed = start != null
              ? DateTime.now().millisecondsSinceEpoch - start
              : 0;
          AppLogger.i(
            'DIO',
            '$path → $status (${AppLogger.bytes(size)}, ${elapsed}ms)',
          );
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

  /// 切换站点 — 更新 baseUrl + 重建 guest jar
  Future<void> switchSite() async {
    _currentHost = SiteStore.instance.host;
    dio.options.baseUrl = SiteStore.instance.baseUrl;

    final dir = await getApplicationDocumentsDirectory();
    _guestJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies/$_currentHost'),
      ignoreExpires: true,
    );
    _replaceCookieManager(_guestJar!);
    _activeAccount = null;
  }

  /// 切换到指定账号的 CookieJar（路径含 host）
  Future<void> switchToAccount(String accountName) async {
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies/$_currentHost/$accountName'),
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
    final dir = await getApplicationDocumentsDirectory();
    final storagePath = '${dir.path}/cookies/$_currentHost/$accountName';
    final dir_ = Directory(storagePath);
    if (await dir_.exists()) {
      await dir_.delete(recursive: true);
    }
    if (_activeAccount == accountName) {
      await switchToGuest();
    }
  }

  /// 删除当前站点所有账号的 Cookie 目录
  Future<void> deleteAllAccountJars() async {
    final dir = await getApplicationDocumentsDirectory();
    final siteDir = Directory('${dir.path}/cookies/$_currentHost');
    if (await siteDir.exists()) {
      await siteDir.delete(recursive: true);
    }
    _guestJar = PersistCookieJar(
      storage: FileStorage('${dir.path}/cookies/$_currentHost'),
      ignoreExpires: true,
    );
    _replaceCookieManager(_guestJar!);
    _activeAccount = null;
  }

  void _replaceCookieManager(CookieJar jar) {
    dio.interceptors.removeWhere((i) => i is CookieManager);
    dio.interceptors.insert(0, CookieManager(jar));
  }

  /// GET 请求
  Future<Response<String>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return dio.get<String>(
      path,
      queryParameters: queryParameters,
      options: Options(
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ),
    );
  }

  /// POST 请求
  Future<Response<String>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) {
    return dio.post<String>(
      path,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: headers,
      ),
    );
  }
}

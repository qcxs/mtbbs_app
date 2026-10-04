import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/utils/url_util.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/services/api_service.dart';

// ==================== 文件服务（忽略服务器 Cache-Control） ====================

/// 忽略服务器 [Cache-Control] 头的文件服务响应。
class IgnoreCacheResponse implements FileServiceResponse {
  final http.Response response;
  final Duration stalePeriod;
  final String _url;
  IgnoreCacheResponse(this.response, this.stalePeriod, this._url);

  @override
  int get statusCode => response.statusCode;

  @override
  int? get contentLength => response.bodyBytes.length;

  @override
  Stream<List<int>> get content => Stream.value(response.bodyBytes);

  @override
  String? get eTag => null;

  @override
  DateTime get validTill => DateTime.now().add(stalePeriod);

  @override
  String get fileExtension {
    final dot = _url.lastIndexOf('.');
    if (dot >= 0) {
      final ext = _url.substring(dot);
      if (ext.length <= 6) return ext;
    }
    return '.png';
  }
}

/// 忽略服务器 [Cache-Control] 头的文件服务。
class IgnoreCacheFileService extends FileService {
  final Duration stalePeriod;
  IgnoreCacheFileService({required this.stalePeriod});

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    AppLogger.i('CACHE', 'download: ${_shortenUrl(url)}');
    // 模拟浏览器行为：携带当前站点的 Referer（受「模拟浏览器请求头」设置控制）
    final reqHeaders = <String, String>{
      if (browserHeadersEnabled()) 'Referer': SiteStore.instance.baseUrl,
      ...?headers,
    };

    try {
      final response = await _getWithWafChallenge(url, reqHeaders);
      // 非 200 也算 CDN 不可用（404/403/5xx），与网络异常走同一条回退分支
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      return IgnoreCacheResponse(response, stalePeriod, url);
    } catch (e, s) {
      final origin = originUrlForCdn(
        url,
        cdn: SiteStore.instance.cdnUrl,
        base: SiteStore.instance.baseUrl,
      );
      // 非 CDN 地址无处可退；是 CDN 地址也只按概率回退——
      // 详见 [_kOriginFallbackChance]
      if (origin == null || _random.nextDouble() >= _kOriginFallbackChance) {
        Error.throwWithStackTrace(e, s);
      }
      AppLogger.w('CACHE', 'CDN 失败，回退原站重试: ${_shortenUrl(origin)}');
      try {
        final retry = await _getWithWafChallenge(origin, reqHeaders);
        return IgnoreCacheResponse(retry, stalePeriod, url);
      } catch (e2) {
        AppLogger.w('CACHE', '回退原站仍失败: $e2');
        // 原站也失败：抛出最初的失败（保持原有错误语义）
        Error.throwWithStackTrace(e, s);
      }
    }
  }
}

// ==================== WAF（阿里云 ESA）挑战处理 ====================

/// 图片下载专用 [HttpClient]（与论坛 Dio 分离：第三方图床域不兼容其请求头）。
final HttpClient _imageHttpClient = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10);

/// 手动跟随跳转的最大次数（与 `package:http` 默认值一致）。
const int _kMaxRedirects = 5;

/// 按 host 缓存的挑战 Cookie（进程内，不持久化）。
///
/// 部分图片域（如 `icdn.binmt.cc`）由阿里云 ESA WAF 保护：直接请求返回
/// `307 Temporary Redirect` + `X-Tengine-Error: denied by http_custom`，并在
/// `Set-Cookie` 里下发 `acw_sc__v2` / `acw_tc` 挑战 Cookie；客户端**必须回传该
/// Cookie** 再请求同一地址，才会拿到图片（实测同一 UA 下有 Cookie → 200 PNG，
/// 无 Cookie → 无限 307）。浏览器能加载、刷新后能加载，正是因为浏览器自带
/// Cookie 罐而 `http`/`HttpClient` 跟随跳转时**不保留 Cookie**。
///
/// 每次冷启动首个请求多一个往返，代价可忽略，故不做持久化。
final Map<String, Map<String, String>> _hostCookies = {};

/// 带 WAF 挑战处理的 GET：手动跟随 3xx 跳转，并在跳转间保留 / 回放 Set-Cookie。
///
/// 用 [HttpClient] 而非 `http.get` 的原因：`package:http` 会把多条 `set-cookie`
/// 用 `,` 合并成一个字符串，而 Cookie 值本身可能含逗号（见 docs/07 #26）；
/// `dart:io` 的 [HttpHeaders] 原样保留多条，解析更可靠。
Future<http.Response> _getWithWafChallenge(
  String url,
  Map<String, String> headers,
) async {
  var uri = Uri.parse(url);
  for (var hop = 0; hop <= _kMaxRedirects; hop++) {
    final request = await _imageHttpClient.getUrl(uri);
    // 手动跟随：自动跟随不带 Cookie，会陷入 WAF 的 307 循环
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    final cookie = _cookieHeaderFor(uri.host);
    if (cookie.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookie);
    }
    final response = await request.close();
    _storeSetCookies(uri.host, response.headers['set-cookie']);

    final code = response.statusCode;
    if (code >= 300 && code < 400) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      // 必须读完响应体才能复用连接
      await response.drain<void>();
      if (location == null) {
        throw HttpException('重定向缺少 Location', uri: uri);
      }
      uri = uri.resolve(location);
      continue;
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return http.Response.bytes(builder.takeBytes(), code);
  }
  throw HttpException('重定向次数过多（$_kMaxRedirects）', uri: uri);
}

/// 拼接指定 host 的 Cookie 请求头（无则返回空串）。
String _cookieHeaderFor(String host) {
  final jar = _hostCookies[host];
  if (jar == null || jar.isEmpty) return '';
  return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// 把响应里的 `Set-Cookie` 存入对应 host 的 Cookie 表。
///
/// 只取 `name=value`（忽略 Path/Domain/Max-Age 等属性，挑战 Cookie 均为 `path=/`）；
/// `value` 为空（含 `Max-Age=0` 的删除指令）时移除该条。
void _storeSetCookies(String host, List<String>? rawCookies) {
  if (rawCookies == null || rawCookies.isEmpty) return;
  final jar = _hostCookies.putIfAbsent(host, () => <String, String>{});
  for (final raw in rawCookies) {
    final semi = raw.indexOf(';');
    final pair = (semi >= 0 ? raw.substring(0, semi) : raw).trim();
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final name = pair.substring(0, eq).trim();
    final value = pair.substring(eq + 1).trim();
    if (value.isEmpty) {
      jar.remove(name);
    } else {
      jar[name] = value;
    }
  }
}

/// CDN 加载失败时**回退原站**的概率。
///
/// 刻意不无条件回退：CDN 抖动时所有客户端一起打回原站，等于把 CDN 的故障
/// 转嫁成原站的压力（严重时被封 IP）。按概率只放出这部分请求，其余交给
/// 下次请求再掷一次——次数一多总会命中，而原站的瞬时压力被压到可接受范围。
const double _kOriginFallbackChance = 0.3;

final Random _random = Random();

/// 日志用的短地址（只保留尾部，够定位即可）
String _shortenUrl(String url) =>
    url.length > 60 ? '...${url.substring(url.length - 60)}' : url;

// ==================== 管理器工厂 ====================

CacheManager? _emojiCacheManager;
CacheManager? _avatarCacheManager;
CacheManager? _imageCacheManager;
CacheManager? _medalCacheManager;

Duration _stalePeriod(int days) =>
    days > 0 ? Duration(days: days) : const Duration(days: 36500);

CacheManager _createEmoji(int days) => CacheManager(
  Config(
    'emoji_cache',
    stalePeriod: _stalePeriod(days),
    maxNrOfCacheObjects: 1500,
    fileService: IgnoreCacheFileService(stalePeriod: _stalePeriod(days)),
  ),
);

CacheManager _createAvatar(int days) => CacheManager(
  Config(
    'avatar_cache',
    stalePeriod: _stalePeriod(days),
    maxNrOfCacheObjects: 500,
    fileService: IgnoreCacheFileService(stalePeriod: _stalePeriod(days)),
  ),
);

CacheManager _createImage(int days) => CacheManager(
  Config(
    'image_cache',
    stalePeriod: _stalePeriod(days),
    maxNrOfCacheObjects: 2000,
    fileService: IgnoreCacheFileService(stalePeriod: _stalePeriod(days)),
  ),
);

CacheManager _createMedal(int days) => CacheManager(
  Config(
    'medal_cache',
    stalePeriod: _stalePeriod(days),
    maxNrOfCacheObjects: 500,
    fileService: IgnoreCacheFileService(stalePeriod: _stalePeriod(days)),
  ),
);

/// 应用启动时调用，用用户的配置初始化缓存管理器。
void initCacheManagers({
  required int emojiDays,
  required int avatarDays,
  required int imageDays,
  required int medalDays,
}) {
  _emojiCacheManager?.dispose();
  _avatarCacheManager?.dispose();
  _imageCacheManager?.dispose();
  _medalCacheManager?.dispose();
  _emojiCacheManager = _createEmoji(emojiDays);
  _avatarCacheManager = _createAvatar(avatarDays);
  _imageCacheManager = _createImage(imageDays);
  _medalCacheManager = _createMedal(medalDays);
}

/// 表情图片缓存管理器
CacheManager get emojiCacheManager => _emojiCacheManager ??= _createEmoji(30);

/// 头像图片缓存管理器
CacheManager get avatarCacheManager => _avatarCacheManager ??= _createAvatar(7);

/// 通用图片缓存管理器（帖子图片、封面图等），默认携带 Referer
CacheManager get imageCacheManager => _imageCacheManager ??= _createImage(30);

/// 勋章图片缓存管理器（默认永不过期）
CacheManager get medalCacheManager => _medalCacheManager ??= _createMedal(-1);

// ==================== 缓存统计与清空 ====================

/// 四个图片缓存管理器的 config key（清理/清空共用）。
const _cacheManagerKeys = [
  'emoji_cache',
  'avatar_cache',
  'image_cache',
  'medal_cache',
];

/// 由缓存 config key 获取对应管理器。
CacheManager _managerByKey(String cacheKey) {
  switch (cacheKey) {
    case 'emoji_cache':
      return emojiCacheManager;
    case 'avatar_cache':
      return avatarCacheManager;
    case 'image_cache':
      return imageCacheManager;
    case 'medal_cache':
      return medalCacheManager;
  }
  throw ArgumentError.value(cacheKey, 'cacheKey', '未知缓存 key');
}

/// 扫描缓存目录，按 [shouldDelete] 判定后删除文件，返回扫描/删除数。
///
/// 自动清理（[cleanupExpiredCaches]）与手动清空（[clearCacheByKey]）共用的
/// 统一文件删除路径：
/// - 有 repo 记录：删除走库公开 API [CacheManager.removeFile]，
///   由库同步清理内存缓存、数据库记录与磁盘文件；
/// - 无记录的孤儿文件（Windows 上库删除文件失败时记录仍会被删，
///   repo 与磁盘脱节）：直接删除文件，库不再引用、无副作用。
///
/// 删除失败的（如 Windows 文件被占用）记日志跳过，不影响其它文件。
Future<({int scanned, int removed})> _scanAndDelete(
  CacheManager manager,
  bool Function(File file, CacheObject? record, DateTime now) shouldDelete,
) async {
  // 必须先等 repo 打开并加载元数据，否则 getAllObjects 拿到空列表：
  // repo.open() 在 CacheStore 构造时异步触发（Windows 上需等 path_provider），
  // 而 getAllObjects 只返回内存缓存，不等待 open。
  await manager.config.repo.open();
  final objects = await manager.config.repo.getAllObjects();
  final byPath = {for (final o in objects) o.relativePath: o};

  final cacheDir = Directory(await AppPaths.cachePath(manager.config.cacheKey));
  if (!cacheDir.existsSync()) return (scanned: 0, removed: 0);
  final now = DateTime.now();
  var scanned = 0;
  var removed = 0;
  await for (final entity in cacheDir.list(recursive: true)) {
    if (entity is! File) continue;
    scanned++;
    // 库的 relativePath 为纯文件名，p.basename 跨平台取磁盘文件名
    final name = p.basename(entity.path);
    final record = byPath[name];
    if (!shouldDelete(entity, record, now)) continue;
    try {
      if (record != null) {
        // 有记录：走库公开 API，同步清理内存/数据库/文件
        await manager.removeFile(record.key);
      } else {
        // 无记录（孤儿文件）：直接删除，库不引用无副作用
        await entity.delete();
      }
      removed++;
    } catch (e) {
      // 文件可能正被占用（Windows），留待下次清理
      AppLogger.w(
        'CACHE',
        'delete expired file failed '
            '(${manager.config.cacheKey}/$name): $e',
      );
    }
  }
  return (scanned: scanned, removed: removed);
}

/// 清理所有已过期缓存，返回清理的文件数。
///
/// 过期判定与 flutter_cache_manager 的读取路径完全一致：
/// 有 repo 记录按 `validTill`；无记录的孤儿文件按文件修改时间 + 过期时长。
/// 头像缓存清理后联动清理过期头像映射（[AvatarRedirectStore.clearExpired]）。
///
/// 每个管理器独立 try/catch：单个失败仅记日志，不影响其它缓存。
Future<int> cleanupExpiredCaches() async {
  var removed = 0;
  AppLogger.i('CACHE', 'cleanup expired caches start');
  for (final cacheKey in _cacheManagerKeys) {
    final manager = _managerByKey(cacheKey);
    try {
      final stale = manager.config.stalePeriod;
      final result = await _scanAndDelete(
        manager,
        (file, record, now) => record != null
            ? !record.validTill.isAfter(now)
            : _isFileExpired(file, stale, now),
      );
      removed += result.removed;
      // 头像缓存过期清理后，同步清理过期头像映射：
      // 否则映射会指向已删除的缓存文件，跳过 HEAD 直接查缓存导致
      // 头像 URL 变化后长期显示旧头像（与缓存管理页清空时的联动一致）。
      if (cacheKey == 'avatar_cache') {
        await AvatarRedirectStore.instance.loadIfNeeded();
        final cleared = AvatarRedirectStore.instance.clearExpired();
        if (cleared > 0) {
          AppLogger.d('AVATAR', 'cleanup expired redirect maps: $cleared');
        }
      }
      // 只在真的清掉东西时打日志：正常启动 4 个缓存目录各刷一行 "removed 0"，
      // 属于无信息量的噪音
      if (result.removed > 0) {
        AppLogger.i(
          'CACHE',
          'cleanup $cacheKey: 扫描 ${result.scanned}，清理 ${result.removed}',
        );
      }
    } catch (e) {
      AppLogger.w('CACHE', 'cleanup expired failed ($cacheKey): $e');
    }
  }
  if (removed > 0) {
    AppLogger.i('CACHE', 'cleanup expired caches done, removed: $removed');
  }
  return removed;
}

/// 判断文件是否按修改时间过期：`修改时间 + 过期时长 < now`。
///
/// 仅用于无 repo 记录（孤儿）文件的兜底判断；无法读取时间戳时保守保留。
bool _isFileExpired(File file, Duration stale, DateTime now) {
  try {
    return file.statSync().modified.add(stale).isBefore(now);
  } catch (_) {
    return false;
  }
}

/// 获取指定缓存 key 对应目录的磁盘占用（字节）和文件数。
///
/// [cacheKey] 是创建 CacheManager 时传入的 Config key（如 'emoji_cache'）。
Future<({int bytes, int files})> getCacheInfo(String cacheKey) async {
  final cacheDir = Directory(await AppPaths.cachePath(cacheKey));
  if (!cacheDir.existsSync()) return (bytes: 0, files: 0);
  int bytes = 0, files = 0;
  await for (final entity in cacheDir.list(recursive: true)) {
    if (entity is File) {
      bytes += await entity.length();
      files++;
    }
  }
  return (bytes: bytes, files: files);
}

/// 清空指定缓存 key 对应的所有文件（含库记录与内存缓存）。
///
/// 有管理器的缓存（[emojiCacheManager]/[avatarCacheManager]/
/// [imageCacheManager]/[medalCacheManager]）走统一的扫描删除
/// [_scanAndDelete] 全部删除，保证库状态一致并覆盖无记录的孤儿文件；
/// 无管理器的目录（如 `file_picker`）直接删除磁盘目录。
Future<void> clearCacheByKey(String cacheKey) async {
  if (_cacheManagerKeys.contains(cacheKey)) {
    await _scanAndDelete(_managerByKey(cacheKey), (file, record, now) => true);
    return;
  }
  final cacheDir = Directory(await AppPaths.cachePath(cacheKey));
  if (cacheDir.existsSync()) {
    await cacheDir.delete(recursive: true);
  }
}

/// 删除 file_picker 复制的临时缓存文件（Android/iOS 特有）
///
/// file_picker 在选取文件时会无条件把文件复制到 App 缓存目录
/// `{tempDir}/file_picker/{时间戳}/{文件名}`（见插件 FileUtils.openFileStream），
/// 上传完成后应主动清理，避免缓存无限膨胀。
/// 仅当路径位于 `{tempDir}/file_picker/` 下才删除，绝不触碰用户原图。
Future<void> deleteFilePickerTempIfAny(String path) async {
  try {
    // 桌面端 file_picker 直接返回原路径、不复制缓存，跳过
    if (Platform.isWindows || Platform.isLinux) return;
    final norm = path.replaceAll('\\', '/');
    final tempRoot =
        '${(await AppPaths.tempDir).replaceAll('\\', '/')}/file_picker/';
    if (!norm.startsWith(tempRoot)) return;
    final f = File(path);
    if (!await f.exists()) return;
    await f.delete();
    // 顺带清理空的时间戳目录
    final parent = f.parent;
    if (parent.existsSync() && parent.listSync().isEmpty) {
      try {
        await parent.delete();
      } catch (_) {}
    }
  } catch (e) {
    AppLogger.w('CACHE', 'delete file_picker temp failed: $e');
  }
}

// ==================== WebView 浏览器缓存 ====================

/// 清除内置浏览器的所有缓存数据（资源缓存、Web 存储、Cookie）
///
/// 使用 [flutter_inappwebview] 的静态 API，无需活动 WebView 实例。
Future<void> clearWebViewCache() async {
  try {
    await InAppWebViewController.clearAllCache(includeDiskFiles: true);
  } catch (e) {
    AppLogger.w('CACHE', 'clearAllCache error: $e');
  }
  try {
    await WebStorageManager.instance().deleteAllData();
  } catch (e) {
    AppLogger.w('CACHE', 'deleteAllData error: $e');
  }
  try {
    await CookieManager.instance().deleteAllCookies();
  } catch (e) {
    AppLogger.w('CACHE', 'deleteAllCookies error: $e');
  }
}

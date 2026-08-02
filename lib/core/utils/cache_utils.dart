import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/core/app/site_store.dart';

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
    final short = url.length > 60
        ? '...${url.substring(url.length - 60)}'
        : url;
    AppLogger.i('CACHE', 'download: $short');
    // 模拟浏览器行为：携带当前站点的 Referer
    final reqHeaders = <String, String>{
      'Referer': SiteStore.instance.baseUrl,
      ...?headers,
    };
    final response = await http.get(Uri.parse(url), headers: reqHeaders);
    return IgnoreCacheResponse(response, stalePeriod, url);
  }
}

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

/// 清空指定缓存 key 对应目录的所有文件。
///
/// 直接删除磁盘目录，比 [CacheManager.emptyCache] 更可靠。
Future<void> clearCacheByKey(String cacheKey) async {
  final cacheDir = Directory(await AppPaths.cachePath(cacheKey));
  if (cacheDir.existsSync()) {
    await cacheDir.delete(recursive: true);
  }
}

/// 清空指定缓存管理器的所有缓存文件。
Future<void> clearCache(CacheManager manager) => manager.emptyCache();

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

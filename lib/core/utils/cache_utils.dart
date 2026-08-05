import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:mtbbs/core/app/app_paths.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';
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
      if (result.scanned > 0) {
        AppLogger.i(
          'CACHE',
          'cleanup scan $cacheKey: '
              '${result.scanned} files, removed ${result.removed}',
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

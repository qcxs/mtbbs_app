import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:mtbbs/core/logger.dart';

/// 忽略服务器 [Cache-Control] 头的文件服务响应。
///
/// flutter_cache_manager 默认会使用服务器的 `max-age` 计算缓存过期时间，
/// 但 CDN 通常返回极短的 max-age 导致缓存频繁失效。
/// 本实现强制使用自定义 [stalePeriod] 计算 [validTill]。
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
///
/// 使用 [http] 包（非 Dio）直接下载，避免论坛 Dio 实例的拦截器、
/// Cookie 和请求头干扰 CDN 请求。
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
    final response = await http.get(Uri.parse(url));
    return IgnoreCacheResponse(response, stalePeriod, url);
  }
}

/// 表情图片缓存管理器。
/// 表情几乎不会变化，使用 30 天有效期。
final emojiCacheManager = CacheManager(
  Config(
    'emoji_cache',
    stalePeriod: Duration(days: 30),
    maxNrOfCacheObjects: 1500,
    fileService: IgnoreCacheFileService(stalePeriod: Duration(days: 30)),
  ),
);

/// 头像缓存管理器。
/// 头像变更不频繁，使用 7 天有效期。
final avatarCacheManager = CacheManager(
  Config(
    'avatar_cache',
    stalePeriod: Duration(days: 7),
    maxNrOfCacheObjects: 500,
    fileService: IgnoreCacheFileService(stalePeriod: Duration(days: 7)),
  ),
);

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/forum/seccode/http.dart' as http;
import 'package:mtbbs/api/forum/seccode/parse.dart' as parse;
import 'package:mtbbs/core/utils/logger.dart';

/// 兜底图片地址。注意 `update` 必须与服务端下发的令牌一致，
/// 自造的时间戳会被判为非法；仅在拿不到 update 响应时使用。
String buildSeccodeImageUrl(String idhash) =>
    'misc.php?mod=seccode&update=${DateTime.now().millisecondsSinceEpoch}'
    '&idhash=$idhash';

/// 拉取验证码图片字节。任何失败都返回 null，由 UI 显示「点击刷新」。
Future<Uint8List?> fetchSeccodeImage(
  Dio dio, {
  required String imageUrl,
}) async {
  try {
    final resp = await http.getSeccodeImage(dio, url: _rooted(imageUrl));
    final data = resp.data;
    final contentType = resp.headers.value('content-type') ?? '';
    if (resp.statusCode != 200 ||
        data == null ||
        data.isEmpty ||
        !contentType.startsWith('image/')) {
      AppLogger.w(
        'PAGE',
        'seccode image failed: ${resp.statusCode} $contentType',
      );
      return null;
    }
    return Uint8List.fromList(data);
  } catch (e) {
    AppLogger.w('PAGE', 'seccode image error: $e');
    return null;
  }
}

/// 换一个验证码并拉取新图片。
///
/// 首次加载与「换一个」都走这里：服务端 `action=update` 会同时把新验证码
/// 写入会话并下发带合法 `update` 令牌的图片地址；直接构造图片地址取不到图。
Future<Uint8List?> refreshSeccodeImage(
  Dio dio, {
  required String idhash,
  String modId = '',
  String fallbackImageUrl = '',
}) async {
  String imageUrl = '';
  try {
    final resp = await http.updateSeccode(
      dio,
      idhash: idhash,
      modId: modId,
    );
    imageUrl = parse.parseUpdatedSeccodeImage(
      safeDecode(resp),
      idhash: idhash,
    );
  } catch (e) {
    AppLogger.w('PAGE', 'seccode update error: $e');
  }
  if (imageUrl.isEmpty) {
    imageUrl = fallbackImageUrl.isNotEmpty
        ? fallbackImageUrl
        : buildSeccodeImageUrl(idhash);
  }
  return fetchSeccodeImage(dio, imageUrl: imageUrl);
}

/// 相对地址补成站点根路径，避免 baseUrl 带路径时解析到子目录。
String _rooted(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return url.startsWith('/') ? url : '/$url';
}

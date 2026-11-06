import 'package:dio/dio.dart';

/// 验证问答（secqaa）请求层。
///
/// 与图片验证码不同，这里没有图片端点：`action=update` 返回的 JS 文本里
/// 同时带着输入框模板和**题面**，直接用文本响应即可。

/// 取新题目。响应是无缓存的 JS 文本（`application/javascript`），
/// 站点是 GBK 时由 Dio 的 responseDecoder 按 content-type 解码。
///
/// [modId] 与图片验证码一致，发帖/回复为 `forum::post`。
Future<Response<String>> updateSecqaa(
  Dio dio, {
  required String idhash,
  String modId = '',
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final mod = modId.isEmpty
      ? ''
      : '&modid=${Uri.encodeQueryComponent(modId)}';
  return dio.get<String>(
    '/misc.php?mod=secqaa&action=update'
    '&idhash=${Uri.encodeQueryComponent(idhash)}$mod&$ts',
    options: Options(headers: {'Cache-Control': 'no-cache'}),
  );
}

import 'package:dio/dio.dart';

/// 验证码（misc.php?mod=seccode）HTTP 请求。

/// 获取验证码图片。验证码每次提交都必须是新的，禁止任何缓存。
///
/// 该端点会校验来源页：没有 `Referer` 时返回 `Access Denied`（text/html），
/// 因此不能依赖设置里的「模拟浏览器请求头」，必须显式带上。
Future<Response<List<int>>> getSeccodeImage(
  Dio dio, {
  required String url,
}) {
  return dio.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      headers: {
        'Cache-Control': 'no-cache',
        'Referer': dio.options.baseUrl,
      },
    ),
  );
}

/// 换一个验证码。Discuz 返回一段 JS 文本，里面带新的图片地址。
///
/// [modId] 必须与提交时的 `seccodemodid` 一致（发帖/回复为 `forum::post`）；
/// 缺省时服务端生成的 `seccodemodid` 为空，提交会因模块不匹配而判为验证码错误。
Future<Response<String>> updateSeccode(
  Dio dio, {
  required String idhash,
  String modId = '',
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final mod = modId.isEmpty
      ? ''
      : '&modid=${Uri.encodeQueryComponent(modId)}';
  return dio.get<String>(
    '/misc.php?mod=seccode&action=update'
    '&idhash=${Uri.encodeQueryComponent(idhash)}$mod&$ts',
    options: Options(headers: {'Cache-Control': 'no-cache'}),
  );
}

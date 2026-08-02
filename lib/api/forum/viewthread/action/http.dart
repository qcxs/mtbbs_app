import 'package:dio/dio.dart';

/// 归一化相对路径：补前导斜杠，避免与 baseUrl 拼接错误
String _normalizePath(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return path.startsWith('/') ? path : '/$path';
}

/// 获取评分弹窗 HTML
Future<Response<String>> getRateDialog(Dio dio, String rateUrl) {
  final separator = rateUrl.contains('?') ? '&' : '?';
  return dio.get<String>('${_normalizePath(rateUrl)}${separator}inajax=1');
}

/// 获取踢帖弹窗 HTML
Future<Response<String>> getKickDialog(Dio dio, String kickUrl) {
  return dio.get<String>(kickUrl);
}

/// 获取收藏弹窗 HTML
Future<Response<String>> getFavoriteDialog(Dio dio, String favUrl) {
  return dio.get<String>(favUrl);
}

/// 提交评分
Future<Response<String>> submitRate(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) {
  final separator = action.contains('?') ? '&' : '?';
  // Discuz 表单校验依赖 $_POST，必须显式声明 form-urlencoded（Dio 不会自动补 Content-Type）
  return dio.post<String>(
    '${_normalizePath(action)}${separator}inajax=1',
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: data,
  );
}

/// 踢帖提交
Future<Response<String>> submitKick(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) {
  final separator = action.contains('?') ? '&' : '?';
  // Discuz 表单校验依赖 $_POST，必须显式声明 form-urlencoded（Dio 不会自动补 Content-Type）
  return dio.post<String>(
    '$action${separator}inajax=1',
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: data,
  );
}

/// 收藏提交
Future<Response<String>> submitFavorite(
  Dio dio,
  String action,
  Map<String, dynamic> data,
) {
  final separator = action.contains('?') ? '&' : '?';
  // Discuz 表单校验依赖 $_POST，必须显式声明 form-urlencoded（Dio 不会自动补 Content-Type）
  return dio.post<String>(
    '$action${separator}inajax=1',
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: data,
  );
}

/// 点赞（直接 GET 提交）
Future<Response<String>> submitRecommend(Dio dio, String recUrl) {
  final separator = recUrl.contains('?') ? '&' : '?';
  return dio.get<String>('$recUrl${separator}inajax=1');
}

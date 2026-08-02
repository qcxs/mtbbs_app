import 'package:dio/dio.dart';

/// 收藏列表 HTTP 请求
Future<Response<String>> getFavorites(Dio dio, {int page = 1}) {
  return dio.get<String>('/home.php?mod=space&do=favorite&view=me&page=$page');
}

/// 收藏（含备注）HTTP 请求
///
/// 手机端收藏表单（Chrome 观察）：
/// ```html
/// <form action="...ac=favorite&type=thread&id={tid}&spaceuid=&mobile=2">
///   <input name="favoritesubmit" value="true">
///   <input name="referer" ...>
///   <input name="formhash" ...>
///   <input name="handlekey" value="favorite_add">
///   <textarea name="description">备注</textarea>
/// </form>
/// ```
/// 电脑端点击收藏链接（无弹窗）会直接 GET 收藏成功，说明收藏仅依赖
/// tid + formhash；备注通过 POST 的 description 字段写入。
/// formhash 由调用方提供（从帖子页联动提取）。
Future<Response<String>> addFavorite(
  Dio dio, {
  required String tid,
  required String formhash,
  String? note,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=favorite&type=thread&id=$tid',
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
    ),
    data: {
      'favoritesubmit': 'true',
      'referer': '',
      'formhash': formhash,
      'handlekey': 'favorite_add',
      'description': note ?? '',
    },
  );
}

/// 删除收藏 HTTP 请求
///
/// 确认表单（Chrome 观察）：
/// ```html
/// <form id="favoriteform_{id}" action="...ac=favorite&op=delete&favid={id}&type=all">
///   <input name="referer" ...> <input name="deletesubmit" value="true">
///   <input name="formhash" ...>
/// </form>
/// ```
/// formhash 由调用方提供（从收藏列表页联动提取）。
Future<Response<String>> deleteFavorite(
  Dio dio, {
  required String favid,
  required String formhash,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=favorite&op=delete&favid=$favid&type=all',
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
      // Discuz 删除成功返回 301 跳转，需放行 3xx 且不自动跟随，
      // 由 parse 层根据 Location/状态码判定成功与否。
      followRedirects: false,
      validateStatus: (s) => s != null && s < 500,
    ),
    data: {'referer': '', 'deletesubmit': 'true', 'formhash': formhash},
  );
}

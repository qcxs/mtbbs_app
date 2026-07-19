import 'package:dio/dio.dart';

/// 我的帖子 HTTP 请求

/// 获取帖子提醒列表
/// [page] 页码，从 1 开始
/// [type] 子类型：post（帖子）/ at（提到我的）
Future<Response<String>> getMypostList(
  Dio dio, {
  int page = 1,
  String type = 'post',
}) {
  final pageParam = page > 1 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=notice&view=mypost&type=$type$pageParam',
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );
}

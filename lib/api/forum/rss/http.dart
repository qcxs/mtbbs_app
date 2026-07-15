import 'package:dio/dio.dart';

/// RSS 订阅 HTTP 请求
///
/// 获取 Discuz 论坛的最新帖子 RSS 订阅。
/// baseUrl 由 Dio 实例的 BaseOptions 提供。
Future<Response<String>> getRssFeed(Dio dio) {
  return dio.get<String>('/forum.php?mod=rss');
}

import 'package:dio/dio.dart';

/// 小黑屋 HTTP 请求

/// 获取小黑屋列表
Future<Response<String>> getList(Dio dio, {String cid = ''}) {
  return dio.get<String>(
    '/forum.php?mod=misc&action=showdarkroom&cid=$cid&ajaxdata=json',
  );
}

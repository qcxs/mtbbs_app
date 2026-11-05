import 'package:dio/dio.dart';

/// 请求 Discuz 的跳转定位接口（楼层 / 回复），**跟随重定向**。
///
/// - 按楼层：`mod=redirect&ptid=TID&authorid=A&postno=N`
/// - 按回复：`mod=redirect&ptid=TID&goto=findpost&pid=PID`
///
/// 跟随重定向是刻意的：WAF 挑战可能先插一段跳转，只取首个 Location
/// 会拿到挑战地址（见 docs/20）。调用方真正需要的是最终落到哪个 `page`。
Future<Response<String>> getRedirect(
  Dio dio, {
  String? tid,
  int? postno,
  String? authorid,
  String? pid,
}) {
  final params = <String>['mod=redirect'];
  if (tid != null && tid.isNotEmpty) params.add('ptid=$tid');
  if (postno != null) {
    params.add('authorid=${authorid ?? '0'}');
    params.add('postno=$postno');
  } else if (pid != null && pid.isNotEmpty) {
    params.add('goto=findpost');
    params.add('pid=$pid');
  }
  return dio.get<String>('/forum.php?${params.join('&')}');
}

import 'package:dio/dio.dart';
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/api/home/notice_unread/http.dart' as http;
import 'package:mtbbs/api/home/notice_unread/parse.dart' as parse;

/// 未读计数（非破坏性）：`{noticeTotal, byGroup, hasNewPm, follower}`
Future<Map<String, dynamic>> getNoticeUnread(Dio dio) async {
  final resp = await http.getNoticeUnreadPage(dio);
  return parseWithLog(resp, parse.parseUnread);
}

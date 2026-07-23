import 'package:dio/dio.dart';

/// 发帖/回复 HTTP 请求 — 使用 Dio 实例的 baseUrl

/// 获取发帖/回复页面的 HTML（用于提取 formhash/posttime 等会话字段）
Future<Response<String>> getNewThreadPage(Dio dio, {required String fid}) {
  return dio.get<String>('/forum.php?mod=post&action=newthread&fid=$fid');
}

/// 获取回复页面的 HTML
Future<Response<String>> getReplyPage(
  Dio dio, {
  required String tid,
  String? repquote,
}) {
  final url = repquote != null
      ? '/forum.php?mod=post&action=reply&fid=2&tid=$tid&repquote=$repquote'
      : '/forum.php?mod=post&action=reply&fid=2&tid=$tid';
  return dio.get<String>(url);
}

/// 提交新帖
Future<Response<String>> submitNewThread(
  Dio dio, {
  required String fid,
  required String formhash,
  required String posttime,
  required String subject,
  required String message,
  Map<String, String> attachNew = const {},
}) {
  return dio.post<String>(
    '/forum.php?mod=post&action=newthread&fid=$fid&topicsubmit=yes&inajax=1',
    options: Options(
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
      },
    ),
    data: {
      'formhash': formhash,
      'posttime': posttime,
      'topicsubmit': 'yes',
      'subject': subject,
      'message': message,
      ...attachNew,
    },
  );
}

/// 提交回复
Future<Response<String>> submitReply(
  Dio dio, {
  required String fid,
  required String tid,
  required String formhash,
  required String posttime,
  required String message,
  String? noticeauthor,
  String? noticetrimstr,
  String? noticeauthormsg,
  String? reppid,
  Map<String, String> attachNew = const {},
}) {
  final data = <String, dynamic>{
    'formhash': formhash,
    'posttime': posttime,
    'message': message,
    'replysubmit': 'yes',
  };
  if (noticeauthor != null && noticeauthor.isNotEmpty) {
    data['noticeauthor'] = noticeauthor;
  }
  if (noticetrimstr != null && noticetrimstr.isNotEmpty) {
    data['noticetrimstr'] = noticetrimstr;
  }
  if (noticeauthormsg != null && noticeauthormsg.isNotEmpty) {
    data['noticeauthormsg'] = noticeauthormsg;
  }
  if (reppid != null && reppid.isNotEmpty) {
    data['reppid'] = reppid;
    data['reppost'] = reppid;
  }
  data.addAll(attachNew);

  return dio.post<String>(
    '/forum.php?mod=post&action=reply&fid=$fid&tid=$tid&replysubmit=yes&inajax=1',
    options: Options(
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
      },
    ),
    data: data,
  );
}

import 'package:dio/dio.dart';
import 'package:mtbbs/core/parser/page_fetcher.dart';

/// 发帖/回复 HTTP 请求 — 使用 Dio 实例的 baseUrl

/// 获取编辑器页面 HTML（发帖/评论/回复/编辑共用）
Future<Response<String>> getEditorPage(
  Dio dio, {
  required String type,
  String fid = '',
  String tid = '',
  String pid = '',
  String? repquote,
}) {
  final url = PageFetcher.buildUrl(
    type: type,
    fid: fid,
    tid: tid,
    pid: pid,
    repquote: repquote,
  );
  return dio.get<String>(url);
}

/// 提交编辑（帖子/回复）。
///
/// 编辑成功后 Discuz 会 301/302 到 viewthread，因此不能跟随重定向——
/// 需要保留状态码与 Location 交给解析层判断。
Future<Response<String>> submitEdit(
  Dio dio, {
  required String fid,
  required String tid,
  required String pid,
  required String formhash,
  required String posttime,
  required String subject,
  required String message,
  String page = '1',
  Map<String, String> attachNew = const {},
}) {
  return dio.post<String>(
    '/forum.php?mod=post&action=edit&fid=$fid&tid=$tid&pid=$pid'
    '&editsubmit=yes&inajax=1&formhash=$formhash',
    options: Options(
      followRedirects: false,
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: {
      'formhash': formhash,
      'posttime': posttime,
      'subject': subject,
      'message': message,
      'fid': fid,
      'tid': tid,
      'pid': pid,
      'page': page,
      'editsubmit': 'yes',
      ...attachNew,
    },
  );
}

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
    // Discuz 表单校验依赖 $_POST，必须显式声明 form-urlencoded（Dio 不会自动补 Content-Type）
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
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
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: data,
  );
}

import 'package:dio/dio.dart';

/// PM 私信 HTTP 请求

/// 获取私人消息列表（会话列表）
/// [page] 页码，从 1 开始
Future<Response<String>> getPmList(Dio dio, {int page = 1}) {
  final pageParam = page > 1 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=pm&filter=privatepm$pageParam',
  );
}

/// 获取与某用户的私信会话详情页（消息列表 + 回复表单）
///
/// [touid] 对方 uid；[page] 为 0/不传表示**最新一页**，
/// 传 1 表示**最旧一页**（Discuz 的 page 从最旧页起算，见 space_pm.php）。
Future<Response<String>> getPmView(
  Dio dio, {
  required String touid,
  int page = 0,
}) {
  final pageParam = page > 0 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=pm&subop=view&touid=$touid$pageParam',
  );
}

/// 获取"发送短消息"页（用于新会话：拿 formhash 与收件人信息）
///
/// 会话为空时 `subop=view` 不渲染回复表单，因此新会话的 formhash 只能从这里取。
Future<Response<String>> getPmComposePage(Dio dio, {required String touid}) {
  return dio.get<String>('/home.php?mod=spacecp&ac=pm&op=showmsg&touid=$touid');
}

/// 提交私信（formhash 由调用方提供）
///
/// 统一走 `touid` 分支：Discuz 的 `op=send` 对 `touid`（收件人）与
/// `pmid`（回复某条）分别处理，1:1 私信按对方 uid 归组，二者等价；
/// 用 touid 可同时覆盖"新会话"和"会话内回复"。
/// `inajax=1` 让服务端返回 XML（succeedhandle_/errorhandle_），可被
/// [parseSubmitResponse] 直接解析。
Future<Response<String>> submitPm(
  Dio dio, {
  required String touid,
  required String formhash,
  required String message,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=pm&op=send&touid=$touid&pmsubmit=yes&inajax=1',
    // Discuz 表单校验依赖 $_POST，Dio 对 Map 不自动补 Content-Type
    options: Options(
      headers: {'Content-Type': Headers.formUrlEncodedContentType},
    ),
    data: {
      'formhash': formhash,
      'touid': touid,
      'pmsubmit': 'true',
      'message': message,
    },
  );
}

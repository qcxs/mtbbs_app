import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';

/// 用户留言板（`home.php?mod=space&uid={uid}&do=wall`）HTTP 请求
///
/// 只考虑 **PC 模板**：解析依赖标准 Discuz PC 的 `#comment_ul > dl[id^=comment_]`
/// 结构（克米移动模板无留言板 tab），因此所有请求显式覆写 `User-Agent` 为
/// [Site.uaPc]，不跟随站点「浏览模式」。
///
/// 提交端点统一为 `home.php?mod=spacecp&ac=comment`（发布/回复）或
/// `...&op=edit|delete`（编辑/删除），`inajax=1` 返回 Discuz XML（succeedhandle_/
/// errorhandle_），交由 [parseSubmitResponse] 解析。handlekey 为可本地推导的
/// 字面串（`qcwall_{uid}` / `{op}commenthk_{cid}`），formhash 由调用方从留言板
/// 页面提取（一页共用一个）。
///
/// 注意：请求**必须**携带 `X-Requested-With: XMLHttpRequest`（ApiService 默认已带），
/// 否则会被阿里云 ESA WAF 拦成挑战页（见 docs/07 #80）。

Options _pcOptions({bool form = false}) => Options(
  headers: {
    'User-Agent': Site.uaPc,
    if (form) 'Content-Type': Headers.formUrlEncodedContentType,
  },
);

/// 留言板 URL（uid 空 = 当前登录用户自己的留言板）
String wallPath(String uid, {int page = 1}) {
  final uidParam = uid.isNotEmpty ? 'uid=$uid&' : '';
  final pageParam = page > 1 ? '&page=$page' : '';
  return '/home.php?mod=space&${uidParam}do=wall$pageParam';
}

/// 留言板页面（含留言列表 + formhash）
Future<Response<String>> getWallPage(Dio dio, {String uid = '', int page = 1}) {
  return dio.get<String>(wallPath(uid, page: page), options: _pcOptions());
}

/// 发布留言（在 [uid] 的留言板上留一条）
Future<Response<String>> submitWallComment(
  Dio dio, {
  required String uid,
  required String formhash,
  required String message,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=comment&inajax=1',
    options: _pcOptions(form: true),
    data: {
      'referer': wallPath(uid),
      'id': uid,
      'idtype': 'uid',
      'handlekey': 'qcwall_$uid',
      'commentsubmit': 'true',
      'quickcomment': 'true',
      'message': message,
      'commentsubmit_btn': 'true',
      'formhash': formhash,
    },
  );
}

/// 回复某条留言（引用 [cid]）
Future<Response<String>> submitWallReply(
  Dio dio, {
  required String uid,
  required String cid,
  required String formhash,
  required String message,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=comment&inajax=1',
    options: _pcOptions(form: true),
    data: {
      'referer': wallPath(uid),
      'id': uid,
      'idtype': 'uid',
      'cid': cid,
      'handlekey': 'replycommenthk_$cid',
      'commentsubmit': 'true',
      'message': message,
      'commentsubmit_btn': 'true',
      'formhash': formhash,
    },
  );
}

/// 编辑自己的留言 [cid]
Future<Response<String>> submitWallEdit(
  Dio dio, {
  required String uid,
  required String cid,
  required String formhash,
  required String message,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=comment&op=edit&cid=$cid&inajax=1',
    options: _pcOptions(form: true),
    data: {
      'referer': wallPath(uid),
      'editsubmit': 'true',
      'handlekey': 'editcommenthk_$cid',
      'formhash': formhash,
      'message': message,
      'editsubmit_btn': 'true',
    },
  );
}

/// 删除留言 [cid]（墙主可删任意一条，作者可删自己的）
Future<Response<String>> submitWallDelete(
  Dio dio, {
  required String cid,
  required String formhash,
}) {
  return dio.post<String>(
    '/home.php?mod=spacecp&ac=comment&op=delete&cid=$cid&inajax=1',
    options: _pcOptions(form: true),
    data: {
      'deletesubmit': 'true',
      'formhash': formhash,
      'handlekey': 'delcommenthk_$cid',
      'deletesubmitbtn': 'true',
    },
  );
}

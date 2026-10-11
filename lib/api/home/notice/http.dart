import 'package:dio/dio.dart';

/// 站内「提醒」列表 HTTP 请求（`do=notice` 各视图通用）
///
/// [view] 对应 `home.php?mod=space&do=notice&view=*` 的提醒视图（见
/// `lib/config/notice_config.dart` 的 [NoticeGroup.id]）：
/// - `system` — 系统提醒
/// - `manage` — 管理工作（管理员/版主的待办；普通用户仅在举报被处理时有条目）
/// - `interactive` — 坛友互动（配合 [type]）
/// - `mypost` — 我的帖子（配合 [type]；该视图另有 `mypost/` 模块做预览）
///
/// [type] 子类型（仅 `mypost` / `interactive` 使用；留空则服务端取默认子类型）。
/// `system` / `manage` 不看 type，一次返回全量。
///
/// 各视图是**同一张模板**、同一套 DOM（`dl[id^="notice_"]` + `dd.ntc_body`），
/// 因此共用同一份解析（见 parse.dart）。
Future<Response<String>> getNoticeList(
  Dio dio, {
  int page = 1,
  String view = 'system',
  String type = '',
}) {
  final typeParam = type.isNotEmpty ? '&type=$type' : '';
  final pageParam = page > 1 ? '&page=$page' : '';
  return dio.get<String>(
    '/home.php?mod=space&do=notice&view=$view$typeParam$pageParam',
  );
}

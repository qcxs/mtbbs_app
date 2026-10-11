import 'package:dio/dio.dart';
import 'package:mtbbs/core/app/browse_mode.dart';

/// 站内搜索 HTTP 请求（`search.php?mod=forum`）— 基于 Dio
///
/// 只负责发请求，不做 print 或解析。
/// UA 使用站点配置（受「浏览模式」控制）：移动 UA → 克米模板；桌面 UA → 标准 Discuz 模板。
///
/// ⚠️ 刻意**不带 `&inajax=1`**：inajax 只返回 XML/CDATA 包裹的列表片段，
/// 没有页面骨架与分页信息（与导读的 AJAX 分支不同）。搜索需要完整 HTML 才能拿到
/// 分页栏与 searchid 跳转。
///
/// Discuz 流程：首次 GET（带 srchtxt）→ 服务端建搜索索引并 302 到
/// `search.php?mod=forum&searchid={id}&...` → Dio 跟随重定向后即为结果第 1 页；
/// 后续翻页只需回传 searchid。

/// 构造搜索请求路径（不含 baseUrl）
///
/// [searchId] 为空表示发起新搜索（带 srchtxt / srchfilter）；非空表示翻页/复用已有结果。
/// [srchFilter] 为搜索结果过滤范围（如 `digest` = 全站精华）；无关键词时仅按它过滤，
/// Discuz 的 `submitcheck('searchsubmit', 1)` 允许"只过滤、无关键词"的搜索。
String searchPath({
  required String keyword,
  int page = 1,
  String? searchId,
  String srchFilter = '',
}) {
  final sid = searchId?.trim() ?? '';
  final buf = StringBuffer('/search.php?mod=forum&searchsubmit=yes');
  if (sid.isNotEmpty) {
    // 已拿到 searchid → 走分页端点（Discuz 靠 common_searchindex 的 searchid 翻页）
    buf.write('&searchid=$sid&orderby=lastpost&ascdesc=desc');
    if (page > 1) buf.write('&page=$page');
  } else {
    // 首次搜索：纯 GET 即可。submitcheck('searchsubmit', 1) 的 allowget 分支
    // 不校验 formhash（见 Discuz 源码 helper_form::submitcheck），无需 POST。
    if (keyword.isNotEmpty) {
      buf.write('&srchtxt=${Uri.encodeQueryComponent(keyword)}');
    }
    if (srchFilter.isNotEmpty) {
      buf.write('&srchfilter=$srchFilter');
    }
  }
  return buf.toString();
}

/// 发起搜索 / 翻页
///
/// [keyword]    搜索关键词（首次搜索用；与 [srchFilter] 至少需有一个）
/// [page]       页码，从 1 开始
/// [searchId]   搜索结果会话 id；为空表示发起新搜索，非空表示翻页
/// [srchFilter] 搜索结果过滤范围（如 `digest` = 全站精华）
Future<Response<String>> searchThreads(
  Dio dio, {
  required String keyword,
  int page = 1,
  String? searchId,
  String srchFilter = '',
}) {
  return dio.get<String>(
    searchPath(
      keyword: keyword,
      page: page,
      searchId: searchId,
      srchFilter: srchFilter,
    ),
    options: Options(headers: {'User-Agent': resolveRequestUserAgent()}),
  );
}

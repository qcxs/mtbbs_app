import 'package:dio/dio.dart';

/// 圈子（Discuz 群组 `group.php`）HTTP 请求 — 基于 Dio
///
/// 只负责发请求，不做解析或日志。baseUrl / 请求头由 ApiService 统一提供。
///
/// **UA 决策**：不覆写 UA，走 ApiService 默认的桌面 UA。
/// MT 移动克米模板（`group.php` 标题为「圈子」）的圈子列表由 JS 动态加载，
/// 静态 HTML 内没有圈子数据，无法解析；桌面模板（`comiis_wide`，标题「群组」）
/// 才是服务端直出、结构稳定的版本（与 viewthread 等同样走桌面 UA）。

/// 圈子首页：推荐圈子 + 圈子分类 + 积分排行
Future<Response<String>> getGroupIndex(Dio dio) {
  return dio.get<String>('/group.php?hot=yes');
}

/// 某个圈子分类下的圈子列表（分页）
///
/// [gid]  分类 ID（来自首页「圈子分类」的 `group.php?gid=N`）
/// [page] 页码，从 1 开始
Future<Response<String>> getCategoryGroups(
  Dio dio, {
  required String gid,
  int page = 1,
}) {
  return dio.get<String>('/group.php?gid=$gid&page=$page');
}

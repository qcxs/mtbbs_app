import 'package:dio/dio.dart';
import 'package:mtbbs/config/site_config.dart';

/// 版块帖子列表 HTTP 请求（forumdisplay）— 基于 Dio
/// 只负责发请求，不做 print 或解析。
///
/// baseUrl 由 Dio 实例的 BaseOptions 提供

/// 获取指定版块的帖子列表
///
/// [fid]      版块 ID（必传）
/// [orderby]  排序方式：
///   lastpost   — 按最后回复时间（默认）
///   dateline   — 按发布时间
///   replies    — 按回复数
///   views      — 按浏览次数
///   recommends — 按推荐数
///   heats      — 按热度
/// [filter]   筛选条件：
///   digest     — 精华帖
///   recommend  — 推荐帖
///   sortall    — 全部分类
///   typeid     — 按主题类型
///   sortid     — 按分类信息
///   dateline   — 按发布时间
///   heat       — 热门
///   hot        — 热门
///   lastpost   — 最新
/// [page]     页码，从 1 开始（默认 1）
Future<Response<String>> getForumThreads(
  Dio dio, {
  required String fid,
  String orderby = '',
  String filter = '',
  int page = 1,
}) {
  final buf = StringBuffer(
    '/forum.php?mod=forumdisplay&fid=$fid&page=$page&mobile=2',
  );
  if (orderby.isNotEmpty) buf.write('&orderby=$orderby');
  if (filter.isNotEmpty) buf.write('&filter=$filter');

  return dio.get<String>(
    buf.toString(),
    options: Options(headers: {'User-Agent': Site.uaAndroid}),
  );
}

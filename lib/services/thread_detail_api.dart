import '../api/forum/viewthread/detail/export.dart' as detail_api;
import '../models/thread_detail.dart';
import 'api_service.dart';

/// 帖子详情 API — 委托给 lib/api/forum/viewthread/detail/
class ThreadDetailApi {
  static Future<ThreadViewData?> fetch(String tid, {int page = 1}) async {
    final dio = ApiService().dio;
    final result = await detail_api.getThreadDetail(dio, tid: tid, page: page);

    if (result['success'] != true) {
      throw Exception(result['message']?.toString() ?? '加载失败');
    }

    final _fromJson = (dynamic p) =>
        PostItem.fromMap(p as Map<String, dynamic>);

    final mainPost = (result['mainPost'] as Map<String, dynamic>?)?.let(
      (m) => _fromJson(m),
    );

    final posts =
        (result['posts'] as List<dynamic>?)
            ?.map((p) => _fromJson(p))
            .toList() ??
        [];

    return ThreadViewData(
      title: result['title']?.toString() ?? '',
      tid: result['tid']?.toString() ?? tid,
      currentPage: result['currentPage'] as int? ?? 1,
      totalPages: result['totalPages'] as int? ?? 1,
      mainPost: mainPost,
      posts: posts,
      formhash: result['formhash']?.toString() ?? '',
    );
  }
}

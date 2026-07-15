import '../api/forum/guide/export.dart' as guide_api;
import '../models/thread_item.dart';
import 'api_service.dart';

/// 导读 API — 委托给 lib/api/forum/guide/
class GuideApi {
  static Future<List<ThreadItem>> fetch({
    String view = 'newthread',
    int page = 1,
  }) async {
    final dio = ApiService().dio;
    final result = await guide_api.getThreadList(dio, view: view, page: page);

    final threads =
        (result['threads'] as List<dynamic>?)
            ?.map((j) => ThreadItem.fromJson(j as Map<String, dynamic>))
            .toList() ??
        [];

    return threads;
  }
}

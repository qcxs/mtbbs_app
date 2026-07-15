import '../api/forum/darkroom/export.dart' as darkroom_api;
import 'api_service.dart';

/// 小黑屋 API — 委托给 lib/api/forum/darkroom/
class DarkroomApi {
  static Future<Map<String, dynamic>> fetch({String cid = ''}) async {
    final dio = ApiService().dio;
    return darkroom_api.getList(dio, cid: cid);
  }
}

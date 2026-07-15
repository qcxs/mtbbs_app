import '../api/home/space/export.dart' as space_api;
import '../models/user_profile.dart';
import 'api_service.dart';

/// 用户空间 API — 委托给 lib/api/home/space/
class SpaceApi {
  /// 获取用户个人资料
  ///
  /// 查询优先级：[uid] > [username] > 当前登录用户自己
  /// 失败时返回 null。
  static Future<UserProfile?> fetch({
    String uid = '',
    String username = '',
  }) async {
    final dio = ApiService().dio;
    final result = await space_api.getUserProfile(
      dio,
      uid: uid,
      username: username,
    );
    if (result['success'] != true) return null;
    final profile = result['profile'] as Map<String, dynamic>?;
    if (profile == null) return null;
    return UserProfile.fromMap(profile);
  }
}

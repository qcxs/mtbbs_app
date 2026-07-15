import '../api/home/credit/export.dart' as credit_api;
import 'api_service.dart';

/// 积分公式 API — 委托给 lib/api/home/credit/
class CreditApi {
  static Future<Map<String, dynamic>> fetch() async {
    final dio = ApiService().dio;
    return credit_api.fetch(dio);
  }
}

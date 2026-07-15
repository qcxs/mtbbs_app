import 'package:dio/dio.dart';

/// 积分公式 HTTP 请求 — 基于 Dio
///
/// 需要已登录状态。Android UA 由 Dio 实例的 BaseOptions 提供。

/// 获取积分公式页面
Future<Response<String>> getCreditFormula(Dio dio) {
  return dio.get<String>('/home.php?mod=spacecp&ac=credit');
}

import 'package:dio/dio.dart';
import 'package:mtbbs/core/site_store.dart';

/// 获取 Discuz 表情缓存 JS
///
/// 路径优先使用 CDN（如 https://cdn-bbs.mt2.cn），
/// 未配置 CDN 时回退到站点 baseUrl。
Future<Response<String>> getSmiliesJs(Dio dio) {
  return dio.get<String>(
    '${SiteStore.instance.cdnUrl}/data/cache/common_smilies_var.js',
  );
}

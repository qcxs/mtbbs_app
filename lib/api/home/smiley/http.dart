import 'package:dio/dio.dart';
import 'package:mtbbs/core/app/site_store.dart';

/// 获取 Discuz 表情缓存 JS
///
/// 走站点 baseUrl（原站）：该文件在 `data/cache/` 下，CDN 只镜像 `static/`，
/// 请求原站最稳妥。JS 里只有文件名，图片 URL 由解析层按识别到的 CDN 拼接。
Future<Response<String>> getSmiliesJs(Dio dio) {
  return dio.get<String>(
    '${SiteStore.instance.baseUrl}/data/cache/common_smilies_var.js',
  );
}

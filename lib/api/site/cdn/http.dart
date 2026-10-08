import 'package:dio/dio.dart';

/// 站点 CDN 探测页（PC 版完整 HTML 页）。
///
/// Discuz 在**每个完整 HTML 页**的模板头部内联输出静态资源前缀：
/// `var STYLEID = …, STATICURL = 'https://cdn.example.com/static/', IMGDIR = …`
/// （值来自 `config_global.php` 的 `$_config['output']['staticurl']`，
/// 见 `discuz_application.php` 的 `define('STATICURL', …)`）。
/// 因此任取一个完整页面即可读出站点当前使用的 CDN。
///
/// 选帮助页（`misc.php?mod=faq`）作为首选：标准 Discuz 路径、游客可见、
/// 体积最小（MT 论坛实测 13KB，首页 55KB）。取不到时回退论坛首页。
///
/// 注意：**不要用移动端（克米模板）页面**——该模板跨站点不通用；
/// 而 `STATICURL` 是标准 Discuz 模板通用输出，PC 页更可靠。
/// 也不用 `inajax=1` 片段与 `data/cache/*.js`（都不含模板头部）。
const String kCdnProbePath = '/misc.php?mod=faq';

/// 探测失败时的回退页面
const String kCdnProbeFallbackPath = '/forum.php';

/// 请求探测页（相对路径，基于 [Dio.options.baseUrl]，即当前站点）
Future<Response<String>> fetchCdnPage(Dio dio, String path) =>
    dio.get<String>(path);

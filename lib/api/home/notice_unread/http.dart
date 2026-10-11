import 'package:dio/dio.dart';

/// 未读计数探测：拉一个**轻量且必定存在**的登录页，只为读页面头部的提醒菜单。
///
/// 为什么不用通知页本身：`do=notice` 一打开就会把未读置为已读
/// （`source/include/space/space_notice.php` 的 `ignore()` + `update_newprompt()`），
/// 拿它轮询会让徽标永远归零、用户永远看不到"新"。而 Discuz 在**每个**登录页的
/// 头部都渲染 `#myprompt_menu`（各分组计数）与 `#myprompt`（总数）
/// （`template/default/common/header.htm` + `header_userstatus.htm`），
/// 且不改变已读状态——这是唯一非破坏性的计数来源。
///
/// 选 `forum.php`：各站点必然存在，体积可控（实测测试站约 16KB）。
/// 站点若装了 Discuz 移动插件，`mobile.php?module=...&submodule=checkpost`
/// 也能给 JSON 计数，但插件可选，不作依赖。
Future<Response<String>> getNoticeUnreadPage(Dio dio) =>
    dio.get<String>('/forum.php');

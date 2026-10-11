import 'package:mtbbs/api/helpers.dart';

/// 解析页面头部的提醒计数（见 http.dart 的说明）。
///
/// 依赖的 DOM（Discuz 全局 header，跨模板稳定）：
/// ```html
/// <a href="home.php?mod=space&do=notice" id="myprompt" class="a showmenu new">提醒(3)</a>
/// <ul id="myprompt_menu" class="p_pop" style="display: none;">
///   <li><a href="home.php?mod=space&do=pm" id="pm_ntc"><em class="prompt_news_0"></em>消息</a></li>
///   <li><a href="home.php?mod=follow&do=follower"><em class="prompt_follower_0"></em>新听众</a></li>
///   <li><a href="...&do=notice&view=mypost"><em class="notice_mypost"></em>我的帖子(<span class="rq">1</span>)</a></li>
///   …
/// </ul>
/// ```
Map<String, dynamic> parseUnread(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final byGroup = <String, int>{};
  var hasNewPm = false;
  var follower = 0;

  final menu = doc.getElementById('myprompt_menu');
  if (menu != null) {
    for (final a in menu.querySelectorAll('li a')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('do=pm')) {
        // `<em class="prompt_news_0">` 的 `_0` 表示无未读
        final emCls = a.querySelector('em')?.className ?? '';
        if (emCls.isNotEmpty && !emCls.endsWith('_0')) hasNewPm = true;
        continue;
      }
      if (href.contains('do=follow')) {
        follower = _trailingCount(a.text);
        continue;
      }
      final view = RegExp(r'view=(\w+)').firstMatch(href)?.group(1);
      if (view != null) byGroup[view] = _trailingCount(a.text);
    }
  }

  // 头部顶栏的 `#pm_ntc` 带 `new` 类也表示有未读私信（部分模板不渲染菜单 em）
  if (!hasNewPm && doc.querySelector('#pm_ntc.new') != null) hasNewPm = true;

  return {
    'success': true,
    // 提醒总数 = 各分组之和（Discuz 的 newprompt 即各 category_num 之和）
    'noticeTotal': byGroup.values.fold<int>(0, (a, b) => a + b),
    'byGroup': byGroup,
    'hasNewPm': hasNewPm,
    'follower': follower,
  };
}

/// 取菜单文案尾部的 `(N)`（模板既有 `<span class="rq">N</span>` 也有纯文本 `(N)`）
int _trailingCount(String text) {
  final m = RegExp(r'\((\d+)\)\s*$').firstMatch(text.trim());
  return m == null ? 0 : int.parse(m.group(1)!);
}

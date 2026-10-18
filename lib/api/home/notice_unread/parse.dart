import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';

/// 解析页面头部的提醒计数（见 http.dart 的说明）。
///
/// 两套模板：
///
/// **原生 Discuz** —— `#myprompt_menu` 菜单：
/// ```html
/// <a href="home.php?mod=space&do=notice" id="myprompt" class="a showmenu new">提醒(3)</a>
/// <ul id="myprompt_menu" class="p_pop" style="display: none;">
///   <li><a href="home.php?mod=space&do=pm" id="pm_ntc"><em class="prompt_news_0"></em>消息</a></li>
///   <li><a href="home.php?mod=follow&do=follower"><em class="prompt_follower_0"></em>新听众</a></li>
///   <li><a href="...&do=notice&view=mypost"><em class="notice_mypost"></em>我的帖子(<span class="rq">1</span>)</a></li>
///   …
/// </ul>
/// ```
///
/// **克米 PC（MT 论坛）** —— 没有上面的菜单，计数在顶部导航链接的 `title` 里，
/// 且只渲染有未读的分组：
/// ```html
/// <a href="...do=notice" title="2条新提醒" class="new">提醒</a>
/// <a href="...do=notice&view=system" title="1条系统提醒">系统提醒</a>
/// <a href="...do=notice&view=interactive" title="1条坛友互动">坛友互动</a>
/// ```
/// 详见 docs/07 #96。
Map<String, dynamic> parseUnread(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final byGroup = <String, int>{};
  var hasNewPm = false;
  var follower = 0;
  // 顶部「提醒」入口自己带的计数（`title="2条新提醒"`）。克米模板只渲染
  // **有未读**的分组链接，拿不到分组明细时可退化为这个总数。
  int? explicitTotal;

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
  } else {
    // 克米 PC 模板（MT 论坛）：没有 `#myprompt_menu`，未读计数写在顶部导航
    // 各个链接的 `title` 属性里（实测）：
    //   <a href="...do=notice" title="2条新提醒" class="new">提醒</a>
    //   <a href="...view=system" title="1条系统提醒">系统提醒</a>
    //   <a href="...view=interactive" title="1条坛友互动">坛友互动</a>
    // 且**只渲染有未读的分组**，未出现的分组即 0。
    for (final a in doc.querySelectorAll('a[href*="view="]')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('do=notice')) continue;
      final view = RegExp(r'[?&]view=(\w+)').firstMatch(href)?.group(1);
      if (view == null || view.isEmpty) continue;
      byGroup[view] = _countOfLink(a);
    }
    for (final a in doc.querySelectorAll(
      'a[href*="do=follow"], a[href*="mod=follow"]',
    )) {
      final count = _countOfLink(a);
      if (count > follower) follower = count;
    }
    // 「提醒」总入口：title 形如 `2条新提醒`（没有分组链接时也能给出总数）
    for (final a in doc.querySelectorAll('a[href*="do=notice"]')) {
      final href = a.attributes['href'] ?? '';
      if (RegExp(r'[?&]view=\w+').hasMatch(href)) continue;
      final count = _countFromTitle(a.attributes['title'] ?? '');
      if (count != null && (explicitTotal == null || count > explicitTotal)) {
        explicitTotal = count;
      }
    }
  }

  // 未读私信：原生模板看菜单 em，克米模板看「消息」链接的 new 类 / title。
  if (!hasNewPm) {
    if (doc.querySelector('#pm_ntc.new') != null) {
      hasNewPm = true;
    } else {
      for (final a in doc.querySelectorAll('a[href*="do=pm"]')) {
        final title = a.attributes['title'] ?? '';
        final count = _countFromTitle(title);
        if (count != null) {
          if (count > 0) hasNewPm = true;
          continue;
        }
        final cls = a.className.split(RegExp(r'\s+'));
        final emCls = a.querySelector('em')?.className ?? '';
        if (cls.contains('new') ||
            title.contains('新消息') ||
            (emCls.isNotEmpty && !emCls.endsWith('_0'))) {
          hasNewPm = true;
        }
      }
    }
  }

  return {
    'success': true,
    // 提醒总数：优先用「提醒」入口的 title（Discuz 的 newprompt 是各分组之和，
    // 与分组明细等价）；模板没给时再求和。
    'noticeTotal':
        explicitTotal ?? byGroup.values.fold<int>(0, (a, b) => a + b),
    'byGroup': byGroup,
    'hasNewPm': hasNewPm,
    'follower': follower,
  };
}

/// 取链接的未读数：优先 `title="1条系统提醒"`，其次文案尾部的 `(N)`。
int _countOfLink(dom.Element a) =>
    _countFromTitle(a.attributes['title'] ?? '') ?? _trailingCount(a.text);

/// `N条…` → N（克米模板的 title 写法）；没有该模式返回 null
int? _countFromTitle(String title) {
  final m = RegExp(r'(\d+)\s*条').firstMatch(title);
  return m == null ? null : int.parse(m.group(1)!);
}

/// 取菜单文案尾部的 `(N)`（模板既有 `<span class="rq">N</span>` 也有纯文本 `(N)`）
int _trailingCount(String text) {
  final m = RegExp(r'\((\d+)\)\s*$').firstMatch(text.trim());
  return m == null ? 0 : int.parse(m.group(1)!);
}

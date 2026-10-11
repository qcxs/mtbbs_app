/// `do=notice` 各视图（system / manage / mypost / interactive）**共用**的条目解析。
///
/// 背景：Discuz 的提醒正文（`dd.ntc_body`）由**几十套消息模板**生成
/// （`source/language/lang_notification.php`），形态各异：
/// - 纯文本 + `<a>`（帖子/用户/板块/圈子/相册/任务/道具/管理后台…）
/// - `<div class="quote"><blockquote>理由</blockquote></div>`
/// - `<p class="summary">附注</p>`（系统通知、积分转账、交易所…）
/// - `<br />` 换行（举报反馈、"警告"类通知）
///
/// 因此这里做**递归 + 未知块级降级**，保证任何一种模板都不会丢内容；
/// 并给链接打上 `kind` 便于 UI 后续细分（当前 UI 仍按 user / 链接两类渲染）。
library;

import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/app/page_helper.dart';

/// 从 `dl[id^="notice_"]` 的头像格子里取对方 uid。
///
/// 有 `authorid` 时模板渲染的是对方头像链接（`home.php?mod=space&uid=X` 或
/// `space-uid-X.html`），无 authorid 时是 `systempm.png` 系统图标 → 返回空串。
String noticeAvatarUid(dom.Element dl) {
  final href = dl.querySelector('dd.avt a')?.attributes['href'] ?? '';
  return RegExp(r'uid[=-](\d+)').firstMatch(href)?.group(1) ?? '';
}

/// 是否为「同类型提醒被折叠」的条目（Discuz 渲染一行
/// `<dd class="xg1 xw0">忽略相同通知…`）。
bool noticeHasFromNum(dom.Element dl) {
  for (final dd in dl.querySelectorAll('dd')) {
    final cls = dd.className;
    if (cls.contains('ntc_body') || cls.contains('avt')) continue;
    if ((cls.contains('xg1') && cls.contains('xw0')) &&
        dd.text.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

/// 时间（相对时间文本 + 绝对时间 title）
({String text, String title}) noticeTime(dom.Element dl) {
  final el = dl.querySelector('dt .xg1.xw0 span[title]');
  if (el == null) return (text: '', title: '');
  return (
    text: el.text.trim().replaceAll('\u00A0', ' '),
    title: el.attributes['title'] ?? '',
  );
}

/// 链接归类：用于 UI 图标/标签，不影响是否可点。
String noticeLinkKind(String href) {
  if (href.contains('admin.php')) return 'admin';
  if (href.contains('do=wall')) return 'wall';
  if (href.contains('do=blog')) return 'blog';
  if (href.contains('mod=group')) return 'group';
  if (href.contains('mod=forumdisplay')) return 'forum';
  if (href.contains('goto=findpost')) return 'post';
  if (href.contains('mod=viewthread') || href.contains('thread-')) {
    return 'thread';
  }
  if (href.contains('mod=trade')) return 'trade';
  if (href.contains('mod=collection')) return 'collection';
  if (href.contains('mod=task') ||
      href.contains('mod=magic') ||
      href.contains('mod=medal')) {
    return 'tool';
  }
  if (href.contains('mod=spacecp')) return 'action';
  return 'other';
}

/// 解析提醒页面自带的导航（侧栏视图列表 + 顶部子类型栏）。
///
/// **为什么必须要它**：站点会按权限与配置增删视图/子类型（Discuz 源码依据）——
/// - 非管理员在 `space_notice.php` 开头就被 `unset($_G['notice_structure']['manage'])`，
///   于是 `view=manage` 不合法 → 服务端降级成 `all`，拿回的是**全部提醒**（看着像帖子）
/// - `type` 只在 `notice_structure` 里才生效，否则**静默回退默认子类型**——
///   站点没有 `rate` 时，`type=rate` 拿回的就是 `post` 的数据
///
/// 因此 Tab 与子类型不能写死，要用这份导航裁剪。
/// 返回：
/// - `views: [{id, label, count}]` — 侧栏里站点**实际**有的视图（`li.a` 即当前视图），
///   `count` 是**服务端置已读之后**的组级未读数（权威，可用来直接更新徽标）
/// - `activeView` — 当前视图
/// - `hasSubBar` — 页面是否渲染了子类型栏（区分"没有子类型"与"模板解析不到"）
/// - `subtypes: [{id, label, count}]` — 子类型及其未读数
/// - `activeSubtype` — 站点本次实际打开的子类型（不传 `type` 时即"第一个有未读的"）
Map<String, dynamic> parseNoticeNav(dom.Document doc) {
  final views = <Map<String, dynamic>>[];
  var activeView = '';

  // 侧栏（home/space_prompt_nav）：
  // <div class="tbn"><ul><li class="a"><a href="...view=X">中文(N)</a></li>…</ul></div>
  final nav = doc.querySelector('div.tbn');
  if (nav != null) {
    for (final li in nav.querySelectorAll('li')) {
      final a = li.querySelector('a');
      final href = a?.attributes['href'] ?? '';
      if (!href.contains('do=notice')) continue;
      final id = RegExp(r'view=(\w+)').firstMatch(href)?.group(1);
      if (id == null) continue;
      views.add({
        'id': id,
        'label': _navLabel(a!.text),
        'count': _navCount(a.text),
      });
      // $opactives 把当前视图标成 li class="a"
      if (li.className.split(RegExp(r'\s+')).contains('a')) activeView = id;
    }
  }

  // 顶部子类型栏：
  // <ul class="tb cl"><li class="a"><a href="...view=X&type=Y">中文(N)</a></li>…</ul>
  // 「筛选设置」那条没有 type= → 天然被过滤
  final tb = doc.querySelector('ul.tb');
  final subtypes = <Map<String, dynamic>>[];
  var activeSubtype = '';
  if (tb != null) {
    for (final li in tb.querySelectorAll('li')) {
      final a = li.querySelector('a');
      final href = a?.attributes['href'] ?? '';
      final id = RegExp(r'type=(\w+)').firstMatch(href)?.group(1);
      if (a == null || id == null) continue;
      subtypes.add({
        'id': id,
        'label': _navLabel(a.text),
        'count': _navCount(a.text),
      });
      if (li.className.split(RegExp(r'\s+')).contains('a')) activeSubtype = id;
    }
  }

  return {
    'views': views,
    'activeView': activeView,
    'hasSubBar': tb != null,
    'subtypes': subtypes,
    'activeSubtype': activeSubtype,
  };
}

/// 去掉导航文案尾部的计数 `(N)`
String _navLabel(String text) =>
    text.replaceAll(RegExp(r'\(\d+\)\s*$'), '').trim();

/// 取导航文案尾部的计数 `(N)`（没有则为 0）
int _navCount(String text) {
  final m = RegExp(r'\((\d+)\)\s*$').firstMatch(text.trim());
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// 把 `dd.ntc_body` 拆成结构化段落。
///
/// 段落类型：
/// - `text`  — 普通文本
/// - `user`  — 指向用户主页的链接（带 `uid`）
/// - `thread`— 其余链接（带 `url` 与 `kind`；由 UI 交给 UrlRouter 决定落点）
/// - `br`    — 显式换行
/// - `quote` — `blockquote` / `.quote` 容器（理由、被引内容）
List<Map<String, dynamic>> extractNoticeSegments(dom.Element bodyEl) {
  final segments = <Map<String, dynamic>>[];
  _walk(bodyEl, segments);
  return segments;
}

/// 已知的块级标签：递归出入时补换行，避免块内容黏在一起
const _blockTags = <String>{
  'p',
  'div',
  'ul',
  'ol',
  'li',
  'table',
  'tr',
  'td',
  'dl',
  'dd',
  'dt',
  'section',
  'article',
};

void _walk(dom.Node node, List<Map<String, dynamic>> out) {
  if (node is dom.Text) {
    _addText(out, node.text);
    return;
  }
  if (node is! dom.Element) return;

  final tag = node.localName;
  final cls = node.className;

  if (cls.contains('quote') || tag == 'blockquote') {
    _addQuote(out, node.text);
    return;
  }
  if (tag == 'br') {
    _addBr(out);
    return;
  }
  if (tag == 'a') {
    _addLink(out, node);
    return;
  }
  // 图片/脚本等与正文无关
  if (tag == 'img' || tag == 'script' || tag == 'style') return;

  // 未知容器：块级补换行后再递归，保证不丢内容
  final isBlock = _blockTags.contains(tag);
  if (isBlock) _addBr(out);
  for (final child in node.nodes) {
    _walk(child, out);
  }
}

void _addBr(List<Map<String, dynamic>> out) {
  if (out.isEmpty) return;
  if (out.last['type'] == 'br') return;
  out.add({'type': 'br'});
}

void _addText(List<Map<String, dynamic>> out, String raw) {
  final text = raw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ');
  if (text.trim().isEmpty) return;
  // 与上一段同类合并，减少碎段
  if (out.isNotEmpty && out.last['type'] == 'text') {
    out.last['text'] = '${out.last['text']} ${text.trim()}';
    return;
  }
  out.add({'type': 'text', 'text': text.trim()});
}

void _addQuote(List<Map<String, dynamic>> out, String raw) {
  final text = raw
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return;
  out.add({'type': 'quote', 'text': text});
}

void _addLink(List<Map<String, dynamic>> out, dom.Element a) {
  final href = a.attributes['href'] ?? '';
  final text = sanitizeText(a.text);
  if (text.isEmpty) return;
  if (href.contains('space-uid-') || href.contains('space.php?uid=')) {
    out.add({
      'type': 'user',
      'text': text,
      'uid': RegExp(r'uid[=-](\d+)').firstMatch(href)?.group(1) ?? '',
    });
    return;
  }
  out.add({
    'type': 'thread',
    'text': text,
    'url': href,
    'kind': noticeLinkKind(href),
  });
}

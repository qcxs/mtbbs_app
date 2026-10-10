import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/utils/logger.dart';

// ============================================================
// Discuz 页面错误检测（统一入口）
// ============================================================

/// 页面错误检测结果
class PageCheckResult {
  final bool isError;
  final bool loginRequired;
  final String? message;

  const PageCheckResult({
    required this.isError,
    this.loginRequired = false,
    this.message,
  });
}

/// 检测 Discuz HTML 页面是否包含错误信息（统一入口）。
///
/// 仅使用语义 DOM 选择器检测已知的错误页 HTML 结构。
/// 不依赖字符串关键词匹配，避免与正常帖子标题/正文内容误判。
/// 在 [statusCode] == 200 但 HTML 内容实际为错误页的情况下使用。
/// 检测顺序（从前到后，优先高可信度模式）：
/// 1. `div.comiis_password_top > p.f_c` — 克米模板错误（主题不存在/被删除/被审核）
/// 2. `#messagetext`                      — Discuz 标准消息提示
/// 3. `#message li`                       — Discuz Mobile System Error
/// 4. `input[name="loginsubmit"]`         — Discuz 登录页
PageCheckResult checkPageError(dom.Document doc, String rawHtml) {
  // 1. 克米模板密码保护 / 错误提示
  //    <div class="comiis_password_top"><p class="f_c">...</p></div>
  final passwordTop = doc.querySelector('div.comiis_password_top');
  if (passwordTop != null) {
    final msgEl = passwordTop.querySelector('p.f_c');
    final text = msgEl?.text.trim() ?? '';
    if (text.isNotEmpty) {
      AppLogger.w('PAGE_CHECK', 'comiis_password_top → "$text"');
      return PageCheckResult(isError: true, message: text);
    }
  }

  // 2. Discuz 标准消息提示
  //    <div id="messagetext"><p>...</p></div>
  final msgText = doc.getElementById('messagetext');
  if (msgText != null) {
    final text = extractElementText(msgText);
    if (text.isNotEmpty) {
      AppLogger.w('PAGE_CHECK', '#messagetext → "$text"');
      return PageCheckResult(isError: true, message: text);
    }
  }

  // 3. Discuz Mobile System Error
  //    <div id="message"><ul><li>...</li></ul></div>
  final sysError = doc.querySelector('#message li, .bodytext#message li');
  if (sysError != null) {
    final text = extractElementText(sysError);
    if (text.isNotEmpty) {
      AppLogger.w('PAGE_CHECK', '#message li → "$text"');
      return PageCheckResult(isError: true, message: text);
    }
  }

  // 4. Discuz 登录页
  //    特征：<input name="loginsubmit" type="submit" ...>
  final loginBtn = doc.querySelector('input[name="loginsubmit"]');
  if (loginBtn != null) {
    AppLogger.w('PAGE_CHECK', 'login page detected');
    return PageCheckResult(
      isError: true,
      loginRequired: true,
      message: '需要先登录',
    );
  }

  return const PageCheckResult(isError: false);
}

/// 从 DOM 元素提取纯净文本（剔除 script/style），合并空白并 trim。
///
/// 与 [sanitizeText] 配合：本函数负责“取元素干净文本”，
/// [sanitizeText] 负责“清洗字符串”。
String extractElementText(dom.Element? el) {
  if (el == null) return '';
  final clone = el.clone(true);
  clone.querySelectorAll('script, style').forEach((e) => e.remove());
  return clone.text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// 清洗 DOM 解析文本：移除不可见字符、字体图标、合并多余空格。
///
/// 所有通过 `element.text` 或 `element.text.trim()` 提取的文本
/// 都应经过此函数处理，避免 Discuz HTML 中的以下干扰：
/// - `&nbsp;`（`\u00a0`）非断行空格
/// - 零宽空格/双向文本标记/连接符（`\u200b-\u200f`, `\u2060-\u2064`）
/// - 控制字符
/// - 字体图标（克米模板私有区域 `\ue000-\uf8ff`）
String sanitizeText(String? text) {
  if (text == null || text.isEmpty) return '';
  return text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[\u200b-\u200f\u2060-\u2064\ufeff]'), '')
      .replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]'), '')
      .replaceAll(RegExp(r'[\ue000-\uf8ff]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

/// 从页面 DOM 中提取分页信息
///
/// 解析 Discuz 移动端的分页下拉框：
/// ```html
/// <div class="comiis_page bg_f">
///   <select id="dumppage">
///     <option value="1" selected>第1页</option>
///     <option value="N">第N页</option>
///   </select>
/// </div>
/// ```
///
/// 返回 `{currentPage: int, totalPages: int}`。
/// 如果没有分页控件，返回 `{currentPage: 1, totalPages: 1}`。
Map<String, int> extractPagination(dom.Document doc) {
  // 优先尝试下拉框分页
  final select = doc.querySelector('.comiis_page select#dumppage');
  if (select != null) {
    final options = select.querySelectorAll('option');
    if (options.isNotEmpty) {
      final lastValue = options.last.attributes['value'] ?? '1';
      final totalPages = int.tryParse(lastValue) ?? 1;
      int currentPage = 1;
      for (final opt in options) {
        if (opt.attributes['selected'] != null) {
          currentPage = int.tryParse(opt.attributes['value'] ?? '1') ?? 1;
          break;
        }
      }
      return {'currentPage': currentPage, 'totalPages': totalPages};
    }
  }

  // 尝试从 .pg 分页栏提取（桌面版 Discuz 通用格式）
  //   <div class="pg">
  //     <strong>1</strong>                    ← 当前页
  //     <a href="...2...">2</a>
  //     ...
  //     <label><span title="共 11 页">/ 11 页</span></label>  ← 总页数
  //     <a href="...2..." class="nxt">下一页</a>
  //   </div>
  final pgDiv = doc.querySelector('.pg');
  if (pgDiv != null) {
    // 当前页：<strong> 的文本内容
    final strong = pgDiv.querySelector('strong');
    final currentPage = int.tryParse(strong?.text.trim() ?? '') ?? 1;

    // 总页数：<span title="共 N 页"> 或 label 文本 "/ N 页"
    int totalPages = 1;
    final span = pgDiv.querySelector('span[title]');
    if (span != null) {
      final m = RegExp(
        r'共\s*(\d+)\s*页',
      ).firstMatch(span.attributes['title'] ?? '');
      if (m != null) totalPages = int.tryParse(m.group(1)!) ?? 1;
    }
    if (totalPages <= 1) {
      // 兜底：从 label 文本提取 "/ N 页"
      final label = pgDiv.querySelector('label');
      if (label != null) {
        final m = RegExp(r'/\s*(\d+)\s*页').firstMatch(label.text);
        if (m != null) totalPages = int.tryParse(m.group(1)!) ?? 1;
      }
    }

    return {'currentPage': currentPage, 'totalPages': totalPages};
  }

  // 兜底：从 <a> 分页链接提取（thread-161119-2-1.html 格式或 ?page=N 格式）
  return extractPaginationFromLinks(doc);
}

/// 从 `<a>` 分页链接中提取分页信息
///
/// 解析 Discuz 的两种分页链接格式：
/// ```html
/// <a href="...&page=2">2</a>
/// ```
/// 或 thread URL 格式：
/// ```html
/// <a href="thread-161119-2-1.html">2</a>
/// ```
/// 通过 "下一页" 判断还有更多页。
///
/// **必须排除正文/楼层区内的链接**：用户发的帖子可能引用别的帖子
/// （如 `...?tid=174230&page=2`），若把这类链接也算进分页，单页帖子会被
/// 误判成多页（见下方 [_isInsidePostContent]）。
///
/// 返回 `{currentPage: int, totalPages: int}`。
Map<String, int> extractPaginationFromLinks(dom.Document doc) {
  const defaults = <String, int>{'currentPage': 1, 'totalPages': 1};

  // 收集所有分页链接（?page=N 或 thread-TID-PAGE-1.html）
  final pageLinks = doc.querySelectorAll(
    'a[href*="page="], a[href*="thread-"]',
  );
  if (pageLinks.isEmpty) return defaults;

  int maxPage = 0;
  int? prevPage; // "上一页" 指向的页码
  int? nextPage; // "下一页" 指向的页码

  for (final a in pageLinks) {
    // 正文/楼层里的链接是用户内容（可能带 page=N），不属于分页
    if (_isInsidePostContent(a)) continue;
    final href = a.attributes['href'] ?? '';
    final text = a.text.trim();
    int? p;
    // 尝试 ?page=N 格式
    final m1 = RegExp(r'[?&]page=(\d+)').firstMatch(href);
    if (m1 != null) {
      p = int.tryParse(m1.group(1)!);
    } else {
      // 尝试 thread-TID-PAGE-1.html 格式
      final m2 = RegExp(r'thread-\d+-(\d+)-\d+\.html').firstMatch(href);
      if (m2 != null) p = int.tryParse(m2.group(1)!);
    }
    if (p == null || p <= 0) continue;
    if (p > maxPage) maxPage = p;
    if (text == '上一页' || text.contains('上页')) prevPage = p;
    if (text == '下一页' || text.contains('下页')) nextPage = p;
  }

  int currentPage;
  if (nextPage != null && nextPage > 0) {
    // 有"下一页" → 当前页 = nextPage - 1
    currentPage = nextPage - 1;
  } else if (prevPage != null && prevPage > 0) {
    // 有"上一页"但无"下一页" → 当前页为最后一页
    currentPage = maxPage;
  } else {
    currentPage = 1;
  }

  // totalPages: 如果当前页 < maxPage 则取 maxPage，否则当前页就是最大页
  final totalPages = currentPage < maxPage ? maxPage : currentPage;

  return {'currentPage': currentPage, 'totalPages': totalPages};
}

/// 判断链接是否位于帖子正文 / 楼层区内（用户内容）。
///
/// 帖子页里这两处都可能出现带 `page=N` 的链接（引用其它帖子、跳转按钮），
/// 它们是"内容"而非"分页栏"，必须排除，否则单页帖子会被误判成多页：
/// - `#postlist`：楼层表格容器（标准 Discuz 与克米模板共用）
/// - `td.t_f` / `.t_fsz`：楼层正文单元格
bool _isInsidePostContent(dom.Element a) {
  var node = a.parent;
  while (node != null) {
    if (node.id == 'postlist') return true;
    final cls = node.className;
    if (cls == 't_f' || cls == 't_fsz') return true;
    node = node.parent;
  }
  return false;
}

/// 从 Discuz 帖子 URL 中提取 tid 和 page。
///
/// 支持两种 URL 格式：
/// - `thread-{tid}-{page}-{ordertype}.html`
/// - `forum.php?mod=viewthread&tid={tid}&page={page}`
///
/// 返回 `{tid: int, page: int}`，page 默认为 1。
Map<String, int> parseThreadUrl(String url) {
  // 格式 1: thread-169015-1-1.html
  final m1 = RegExp(r'thread-(\d+)(?:-(\d+))?').firstMatch(url);
  if (m1 != null) {
    return {
      'tid': int.tryParse(m1.group(1)!) ?? 0,
      'page': int.tryParse(m1.group(2) ?? '') ?? 1,
    };
  }

  // 格式 2: forum.php?mod=viewthread&tid=8&page=2
  final tidMatch = RegExp(r'tid=(\d+)').firstMatch(url);
  if (tidMatch != null) {
    final pageMatch = RegExp(r'[?&]page=(\d+)').firstMatch(url);
    return {
      'tid': int.tryParse(tidMatch.group(1)!) ?? 0,
      'page': int.tryParse(pageMatch?.group(1) ?? '') ?? 1,
    };
  }

  return {'tid': 0, 'page': 1};
}

// ============================================================
// 通用拦截页检测（人机验证 / 防火墙，与厂商无关）
// ============================================================

/// 判定上限：真实 Discuz 页面远大于此（实测帖子页 ~160KB），
/// 而验证/跳转桩通常在几 KB 量级。
const int _kInterstitialMaxBodyLength = 64 * 1024;

/// 判断响应是否"不是一个能用的论坛页"——通用拦截页（人机验证 / 防火墙 / WAF）。
///
/// **刻意不做厂商特征匹配**（不认 `acw_sc__v2`、不认具体验证码厂商），
/// 只判断"结构"：真实 Discuz 页面必然有 `<body>`，且必然带论坛骨架痕迹。
/// 因此任何新出现的人机验证页，只要它同样"不是一个能用的论坛页"，就会被命中，
/// 无需逐家适配。
///
/// 实测样本（阿里云 ESA JS 挑战页）：`<html><script>var arg1='…'`，
/// 4321 字节、无 `<body>`、无 DOCTYPE —— 命中。
/// 实测样本（真实帖子页）：含 `<body>`、`Discuz! X3.4`、`formhash` —— 不命中。
///
/// 两道门槛用于排除误判：
/// - `content-type` 必须含 `text/html`（JSON / 图片等接口天然排除）
/// - 必须含 `<html`（Discuz 的 `inajax=1` 响应是 XML/CDATA 包装，天然排除）
bool looksLikeInterstitialPage(String body, String? contentType) {
  if (body.isEmpty) return false;
  if (!(contentType ?? '').toLowerCase().contains('text/html')) return false;
  if (body.length > _kInterstitialMaxBodyLength) return false;

  final lower = body.toLowerCase();
  if (!lower.contains('<html')) return false;

  // 有 <body>：可能是"带 body 的验证页"——仅当完全没有论坛痕迹且正文极少时才判定
  if (lower.contains('<body')) {
    if (_hasDiscuzSkeleton(lower)) return false;
    return _visibleTextLength(body) < 256;
  }

  // 无 <body> 的完整文档：脚本挑战 / 跳转桩（当前阿里云 WAF 即此类）
  return lower.contains('<script') || lower.contains('<meta');
}

/// 论坛页骨架痕迹——任一命中即认为"这是论坛页"，不是拦截页。
///
/// 这些是 Discuz 的全局骨架（跨模板、跨页面稳定），比 `#postlist` 之类的
/// 页面级选择器更通用：列表页、空间页、消息页同样命中。
///
/// 注意：骨架判定必须"宁可判成论坛页"——把正常页误判成拦截页会平白弹出
/// 浏览器（用户可感知的打扰），而漏判只是回到既有的"页面结构可能已变更"提示。
bool _hasDiscuzSkeleton(String lowerBody) {
  if (lowerBody.contains('discuz') ||
      lowerBody.contains('formhash') ||
      lowerBody.contains('comiis')) {
    return true;
  }
  // 布局骨架 id：`#ct` / `#hd` / `#ft`，以及页面骨架 id
  return RegExp(
    r'''id\s*=\s*["']?(ct|hd|ft|postlist|thread_subject)\b''',
  ).hasMatch(lowerBody);
}

/// 粗略统计可见文本长度（剔除 script/style 与标签），用于判断"内容极少"。
int _visibleTextLength(String html) {
  final text = html
      .replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return text.trim().length;
}

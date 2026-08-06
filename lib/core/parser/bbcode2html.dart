import 'dart:convert';

import 'package:mtbbs/core/utils/string_utils.dart';

/// BBCode → HTML 转换器
///
/// 将 BBCode 字符串转换为 HTML，由 [flutter_html] 渲染为 Flutter Widget。
/// 参考 docs/BBCode2Html.js 的转换逻辑实现。
///
/// 转换策略：
/// 1. 先保护 [code] 块（替换为占位符，避免内部 BBCode 被误转换）
/// 2. 逐一遍历 BBCode 标签替换为对应 HTML
/// 3. 解析 [appdata] 自定义标签
/// 4. 表情文本替换为 <img>
/// 5. 新行替换为 <br>
/// 6. 恢复 [code] 占位符
class BBCode2Html {
  final Map<String, String>? _emojiMap;
  final Map<String, String>? _smilieIdMap;
  final Set<String>? _disabledTags;
  final String? _baseUrl;
  final bool _autoDetectUrls;
  final bool _emitCodePlaceholder;
  final bool _emitTablePlaceholder;

  /// [convert] 后填充的 [code] 块内容（索引对应 HTML 中的
  /// `data-code-index`）。供渲染层在 flutter_html extension 中取出
  /// 原始代码文本，交给代码高亮组件渲染。
  final List<String> codeBlocks = [];

  /// [convert] 后填充的 [table] 块内容（索引对应 HTML 中的
  /// `data-table-index`，值为含 [table]...[/table] 标签的原始 BBCode）。
  /// flutter_html 核心不支持 `<table>` 渲染，渲染层须将其替换为
  /// BbcodeTableWidget（Flutter 原生 Table）。
  final List<String> tableBlocks = [];

  BBCode2Html({
    Map<String, String>? emojiMap,
    Map<String, String>? smilieIdMap,
    Set<String>? disabledTags,
    String? baseUrl,
    bool autoDetectUrls = true,
    bool emitCodePlaceholder = false,
    bool emitTablePlaceholder = false,
  }) : _emojiMap = emojiMap,
       _smilieIdMap = smilieIdMap,
       _disabledTags = disabledTags,
       _baseUrl = baseUrl,
       _autoDetectUrls = autoDetectUrls,
       _emitCodePlaceholder = emitCodePlaceholder,
       _emitTablePlaceholder = emitTablePlaceholder;

  /// 归一化/校验颜色值。
  ///
  /// flutter_html 对 4 位 hex（如 `#ff00`）解析会产生 alpha=0 的异常色
  /// （表现为文字透明/发白）。网页中 `<font color="#ff00">` 按 HTML 属性
  /// legacy 语义解析为 `#ff0000`（红色），这里对齐网页语义：
  /// - 4 位 `#RRGG` → `#RRGG00`（R2 + G2，B 补 0）
  /// - 3 位 `#RGB` → `#RRGGBB`（标准 CSS 翻倍）
  /// - 6/8 位 hex 校验通过后原样返回
  /// - 非法 hex（如 `#FFYYTT`）返回空串：flutter_html 的 stringToColor
  ///   会对非法 hex 抛 FormatException 导致整段渲染失败，调用点据此省略样式
  /// - rgb()/rgba()、命名色 flutter_html 均能正确解析，原样返回
  static final _hex3 = RegExp(r'^#[0-9a-fA-F]{3}$');
  static final _hex4 = RegExp(r'^#[0-9a-fA-F]{4}$');
  static final _hex6 = RegExp(r'^#[0-9a-fA-F]{6}$');
  static final _hex8 = RegExp(r'^#[0-9a-fA-F]{8}$');

  static String _normalizeColor(String v) {
    final s = v.trim();
    if (s.startsWith('#')) {
      if (_hex4.hasMatch(s)) {
        return '#${s.substring(1, 3)}${s.substring(3, 5)}00';
      }
      if (_hex3.hasMatch(s)) {
        final c = s.substring(1);
        return '#${c[0]}${c[0]}${c[1]}${c[1]}${c[2]}${c[2]}';
      }
      if (_hex6.hasMatch(s) || _hex8.hasMatch(s)) return s;
      return '';
    }
    return v;
  }

  /// 转换主入口
  String convert(String input) {
    var html = htmlEscape(input);
    final appdataList = <String>[];
    // codeBlocks/tableBlocks 为公开输出字段，每次转换前清空；
    // codeBlocks 在保护 [code] 时即填充（_convertTables 需用它还原占位符）
    codeBlocks.clear();
    tableBlocks.clear();

    // ========== 0. 保护 [appdata] 块（JSON 不应被 HTML 转义） ==========
    html = html.replaceAllMapped(
      RegExp(r'\[appdata\]([\s\S]*?)\[/appdata\]', caseSensitive: false),
      (m) {
        final raw = m.group(1) ?? '';
        // 此时 raw 已被 htmlEscape 转义过，需要还原才能解析 JSON
        final json = raw
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'")
            .replaceAll('&#x27;', "'")
            .replaceAll('&#x2F;', '/');
        appdataList.add(_renderAppdata(json));
        return '\x00APPDATA${appdataList.length - 1}\x00';
      },
    );

    // ========== 1. 预处理器：闭合列表标签 ==========
    // 将 [*]item\n 转换为 <li>item</li>，避免 \n→<br> 后 <li> 内残留 <br>
    html = _preprocessListItems(html);

    // ========== 2. 移除被禁用的标签（保留内容） ==========
    if (_disabledTags != null && _disabledTags.isNotEmpty) {
      html = _stripDisabledTags(html);
    }

    // ========== 3. 保护 [code] 块 ==========
    html = html.replaceAllMapped(
      RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false),
      (m) {
        // 存原始代码文本（codeBlocks 供高亮组件使用，还原时才转 HTML）。
        // 注意：此处的 m.group(1) 已被开头 htmlEscape 转义，须反转义还原，
        // 否则渲染模式（高亮组件不经 flutter_html 实体解码）会显示
        // &gt;/&lt; 等实体原文。
        codeBlocks.add(_unescapeHtml(m.group(1)!));
        return '\x00CODE${codeBlocks.length - 1}\x00';
      },
    );

    // ========== 3. 替换 BBCode 标签 ==========

    // 字体尺寸 [size=N] — 1~9 映射到 CSS px，支持直接写 xxpx
    html = _replaceTag(html, 'size', (_, v) {
      final trimmed = v.trim();
      if (trimmed.endsWith('px')) {
        return '<span style="font-size:$trimmed">';
      }
      final px = switch (trimmed) {
        '1' => '10',
        '2' => '12',
        '3' => '14',
        '4' => '18',
        '5' => '24',
        '6' => '32',
        '7' => '48',
        '8' => '64',
        '9' => '80',
        _ => trimmed,
      };
      return '<span style="font-size:${px}px">';
    }, '</span>');

    // 颜色 [color=...]
    // 使用 <span style="color:..."> 而非 <font color="...">，因为 flutter_html
    // 对 <font color> 属性中的 rgb()/rgba() 格式支持不完整，而 inline style 是 CSS 标准
    // 非法颜色值（_normalizeColor 返回空串）时省略样式，避免 flutter_html 抛异常
    html = _replaceTag(html, 'color', (_, v) {
      final c = _normalizeColor(v);
      return c.isEmpty ? '<span>' : '<span style="color:$c">';
    }, '</span>');

    // 背景色 [backcolor=...]
    html = _replaceTag(html, 'backcolor', (_, v) {
      final c = _normalizeColor(v);
      return c.isEmpty ? '<span>' : '<span style="background-color:$c">';
    }, '</span>');

    // 对齐 [align=...]
    // 使用 CSS text-align 而非 HTML align 属性，因为 flutter_html 不支持 align 属性
    html = _replaceTag(
      html,
      'align',
      (_, v) => '<div style="text-align:$v">',
      '</div>',
    );

    // 粗体
    html = html.replaceAllMapped(
      RegExp(r'\[b\]', caseSensitive: false),
      (_) => '<strong>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\/b\]', caseSensitive: false),
      (_) => '</strong>',
    );

    // 斜体
    html = html.replaceAllMapped(
      RegExp(r'\[i\]', caseSensitive: false),
      (_) => '<i>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\/i\]', caseSensitive: false),
      (_) => '</i>',
    );

    // 字体 [font=xxx]
    html = _replaceTag(
      html,
      'font',
      (_, v) => '<span style="font-family:${v.trim()}">',
      '</span>',
    );

    // 下划线
    html = html.replaceAllMapped(
      RegExp(r'\[u\]', caseSensitive: false),
      (_) => '<u>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\/u\]', caseSensitive: false),
      (_) => '</u>',
    );

    // 删除线
    html = html.replaceAllMapped(
      RegExp(r'\[s\]', caseSensitive: false),
      (_) => '<strike>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\/s\]', caseSensitive: false),
      (_) => '</strike>',
    );

    // 分割线
    html = html.replaceAllMapped(
      RegExp(r'\[hr\]', caseSensitive: false),
      (_) => '<hr>',
    );

    // 引用 [quote]...[/quote]
    html = html.replaceAllMapped(
      RegExp(r'\[quote\]([\s\S]*?)\[/quote\]', caseSensitive: false),
      (m) => '<blockquote>${m.group(1)!.trim()}</blockquote>',
    );

    // 免费信息 [free]...[/free]
    html = html.replaceAllMapped(
      RegExp(r'\[free\]([\s\S]*?)\[/free\]', caseSensitive: false),
      (m) =>
          '<blockquote class="bbcode-free">${m.group(1)!.trim()}</blockquote>',
    );

    // 隐藏内容 [hide]...[/hide]（支持 [hide=参数]）
    html = html.replaceAllMapped(
      RegExp(r'\[hide(?:=[^\]]*)?\]([\s\S]*?)\[/hide\]', caseSensitive: false),
      (m) =>
          '<blockquote>${_labelBlock('隐藏内容', m.group(1)!.trim())}</blockquote>',
    );

    // 列表 [list] / [list=1] / [list=a]
    html = html.replaceAllMapped(
      RegExp(r'\[list=1\]', caseSensitive: false),
      (_) => '<ol type="1">',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[list=a\]', caseSensitive: false),
      (_) => '<ol type="a">',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[list\]', caseSensitive: false),
      (_) => '<ul>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\/list\]', caseSensitive: false),
      (_) => '</ul>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[\*\]', caseSensitive: false),
      (_) => '<li>',
    );

    // email
    html = html.replaceAllMapped(
      RegExp(r'\[email=([^\]]+)\]([\s\S]*?)\[\/email\]', caseSensitive: false),
      (m) => '<a href="mailto:${m.group(1)}">${m.group(2)}</a>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[email\]([\s\S]*?)\[\/email\]', caseSensitive: false),
      (m) => '<a href="mailto:${m.group(1)}">${m.group(1)}</a>',
    );

    // QQ
    html = html.replaceAllMapped(
      RegExp(r'\[qq\](\d+)\[\/qq\]', caseSensitive: false),
      (m) =>
          '<a href="http://wpa.qq.com/msgrd?v=3&uin=${m.group(1)}&site=discuz&from=discuz&menu=yes" target="_blank">QQ: ${m.group(1)}</a>',
    );

    // 表格（嵌套安全）：栈式匹配最外层 [table]，td 内容递归处理嵌套表格
    html = _convertTables(html);

    // [media] / [audio] / [flash] → 统一占位符 [标签] 内容
    String _placeholder(String label, String content) =>
        '<a href="$content" target="_blank">[$label] $content</a>';

    html = html.replaceAllMapped(
      RegExp(
        r'\[media(?:=[^\]]+)?\]([\s\S]+?)\[\/media\]',
        caseSensitive: false,
      ),
      (m) => _placeholder('视频', m.group(1)!.trim()),
    );

    html = html.replaceAllMapped(
      RegExp(r'\[audio\]([\s\S]*?)\[\/audio\]', caseSensitive: false),
      (m) => _placeholder('音频', m.group(1)!.trim()),
    );

    html = html.replaceAllMapped(
      RegExp(r'\[flash\]([\s\S]*?)\[\/flash\]', caseSensitive: false),
      (m) => _placeholder('Flash', m.group(1)?.trim() ?? ''),
    );

    // [img=W,H]...[/img] 和 [img]...[/img]
    html = html.replaceAllMapped(
      RegExp(r'\[img(?:=([^\]]*))?\]([\s\S]*?)\[\/img\]', caseSensitive: false),
      (m) {
        var src = m.group(2)?.trim() ?? '';
        final dims = m.group(1);
        var width = '';
        if (dims != null) {
          final parts = dims.split(',');
          if (parts.isNotEmpty) {
            final w = parts[0].trim();
            if (w.isNotEmpty && double.tryParse(w) != null) {
              width = ' width="$w"';
            }
          }
        }
        return '<img src="$src"$width />';
      },
    );

    // URL [url=href]text[/url] 和 [url]href[/url]
    html = html.replaceAllMapped(
      RegExp(r'\[url(?:=([^\]]*))?\]([\s\S]*?)\[\/url\]', caseSensitive: false),
      (m) {
        final href = (m.group(1) ?? m.group(2) ?? '').trim();
        final text = (m.group(2) ?? '').trim();
        return '<a href="$href" target="_blank">$text</a>';
      },
    );

    // 背景色 background
    html = _replaceTag(html, 'background', (_, v) {
      final c = _normalizeColor(v);
      return c.isEmpty ? '<span>' : '<span style="background-color:$c">';
    }, '</span>');

    // ========== 4. 表情替换 ==========
    html = _replaceEmoji(html);

    // ========== 5. 换行 ==========
    html = html.replaceAll('\n', '<br>');

    // 折叠连续 3+ 的 <br> 为最多 2 个，防止因格式化换行导致大量空白
    html = html.replaceAll(
      RegExp(r'(<br>\s*){3,}', caseSensitive: false),
      '<br><br>',
    );

    // 清理块级 HTML 容器前后的格式化 <br>
    html = _removeAdjacentLineBreaks(html);

    // ========== 6. 自动识别纯文本 URL ==========
    if (_autoDetectUrls) {
      html = _autoLinkUrls(html);
    }

    // ========== 7. 恢复 [code] 块 ==========
    for (int i = 0; i < codeBlocks.length; i++) {
      html = html.replaceFirst(
        '\x00CODE$i\x00',
        _emitCodePlaceholder
            // 占位元素：保持容器结构完整，由 flutter_html extension
            // 按 data-code-index 原地替换为代码高亮组件
            ? '<div class="bbcode-code" data-code-index="$i"></div>'
            : _codeToHtml(codeBlocks[i]),
      );
    }

    // ========== 7. 恢复 [appdata] 块 ==========
    for (int i = 0; i < appdataList.length; i++) {
      html = html.replaceFirst('\x00APPDATA$i\x00', appdataList[i]);
    }

    return html;
  }

  /// 渲染 [appdata] JSON 为 HTML
  String _renderAppdata(String rawJson) {
    try {
      final data = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = data['type'] as String?;
      switch (type) {
        case 'attach':
          return _renderAttach(data);
        case 'image_attach':
          return _renderImageAttach(data);
        case 'locked':
          final msg = htmlEscape(data['message'] as String? ?? '');
          return '<div class="bbcode-locked"><span class="bbcode-reward-icon">🔒</span>$msg</div>';
        case 'pstatus':
          final msg = htmlEscape(data['message'] as String? ?? '');
          return '<div class="bbcode-pstatus">$msg</div>';
        case 'reward':
          final amount = htmlEscape(data['amount'] as String? ?? '');
          final unit = htmlEscape(data['unit'] as String? ?? '');
          return '<div class="bbcode-reward"><span class="bbcode-reward-icon">🎁</span>回帖奖励 <span class="bbcode-reward-amount">$amount</span> $unit</div>';
        case 'bounty':
          final amount = htmlEscape(data['amount'] as String? ?? '');
          final unit = htmlEscape(data['unit'] as String? ?? '');
          return '<div class="bbcode-reward"><span class="bbcode-reward-icon">💰</span>悬赏 <span class="bbcode-reward-amount">$amount</span> $unit</div>';
        case 'poll':
          final pollType = htmlEscape(data['pollType'] as String? ?? '');
          final voterCount = htmlEscape(data['voterCount'] as String? ?? '');
          final options =
              (data['options'] as List<dynamic>?)?.cast<String>() ?? <String>[];
          final status = htmlEscape(data['status'] as String? ?? '');
          final optionsHtml = options
              .asMap()
              .entries
              .map(
                (e) =>
                    '<div style="padding:4px 0">${e.key + 1}. ${htmlEscape(e.value)}</div>',
              )
              .join();
          final statusHtml = status.isNotEmpty
              ? '<div style="padding:4px 0;color:#999">$status</div>'
              : '';
          return '<div class="bbcode-poll"><div>📊 $pollType · $voterCount 人参与</div>$optionsHtml$statusHtml</div>';
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  /// 渲染附件类型 appdata
  String _renderAttach(Map<String, dynamic> data) {
    final name = htmlEscape(data['name'] as String? ?? '附件');
    final size = data['size'] as String? ?? '';
    final downloads = data['downloads'] as String? ?? '';
    final url = data['url'] as String? ?? '';

    final buf = StringBuffer();
    // 使用与 bbcode-attach 相同 class 的卡片样式
    buf.write(
      '<div class="bbcode-attach" style="display:flex;align-items:center;gap:8px;padding:8px 12px;background:#E3F2FD;border-radius:6px;border:1px solid #BBDEFB;">',
    );
    buf.write('<span style="font-size:18px;">📎</span>');
    buf.write('<div style="flex:1;min-width:0;">');
    buf.write(
      '<div style="font-weight:500;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">$name</div>',
    );
    if (size.isNotEmpty || downloads.isNotEmpty) {
      buf.write('<div style="font-size:12px;color:#666;">');
      if (size.isNotEmpty) buf.write('大小: $size');
      if (downloads.isNotEmpty) buf.write(' · 下载 $downloads 次');
      buf.write('</div>');
    }
    buf.write('</div>');
    if (url.isNotEmpty) {
      final resolvedUrl = _resolveUrl(url);
      buf.write(
        '<a href="$resolvedUrl" target="_blank" style="color:#1565C0;text-decoration:none;font-size:13px;white-space:nowrap;">下载</a>',
      );
    }
    buf.write('</div>');
    return buf.toString();
  }

  /// 渲染图片附件类型 appdata
  ///
  /// 不输出 width/height：图片布局由渲染层统一控制（窄屏占满、宽屏封顶）。
  String _renderImageAttach(Map<String, dynamic> data) {
    final url = data['url'] as String? ?? '';
    if (url.isEmpty) return '';
    final resolvedUrl = _resolveUrl(url);
    final escapedUrl = htmlEscape(resolvedUrl);
    return '<img src="$escapedUrl" style="max-width:100%;" />';
  }

  /// 将相对 URL 解析为绝对 URL
  String _resolveUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final baseUrl = _baseUrl;
    if (baseUrl == null || url.isEmpty) return url;
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return url.startsWith('/') ? '$base${url.substring(1)}' : '$base$url';
  }

  /// 自动识别纯文本中的 http(s) URL 并转为可点击链接
  ///
  /// 保护已有 <a> 和 <img> 标签，避免二次包裹。
  String _autoLinkUrls(String html) {
    // 保护已有 HTML 标签
    final tags = <String>[];
    html = html.replaceAllMapped(
      RegExp(r'<a[\s\S]*?</a>|<img[\s\S]*?/>', caseSensitive: false),
      (m) {
        tags.add(m.group(0)!);
        return '\x00TAG${tags.length - 1}\x00';
      },
    );

    // 替换剩余纯文本中的 http(s) URL
    // 要求 URL 以字母/数字/`/` 结尾，自然排除尾部标点
    html = html.replaceAllMapped(
      RegExp(
        r'https?://[a-zA-Z0-9][a-zA-Z0-9./_~:?#@!$&()*+,;=%\[\]-]*[a-zA-Z0-9/]',
        caseSensitive: false,
      ),
      (m) {
        final url = m.group(0)!;
        return '<a href="$url" target="_blank">$url</a>';
      },
    );

    // 恢复保护的标签
    for (int i = 0; i < tags.length; i++) {
      html = html.replaceFirst('\x00TAG$i\x00', tags[i]);
    }
    return html;
  }

  /// [code] 内容转 HTML（保留缩进和格式）
  String _codeToHtml(String code) {
    // code 内容：空格保留、换行转 <br>；HTML 标签须转义（codeBlocks 现为
    // 原始代码文本），由 flutter_html 解码实体后显示，避免 < > 破坏结构
    code = htmlEscape(code);
    final lines = code
        .split('\n')
        .map((l) => '<li>${l.isEmpty ? '<br>' : l}<br></li>')
        .join('');
    return '<pre><code><ol>$lines</ol></code></pre>';
  }

  /// 反转义 htmlEscape 的输出（[code] 保护时还原原始代码用）。
  ///
  /// 顺序：非 `&amp;` 实体先还原、`&amp;` 最后——保证代码中的字面
  /// `&lt;`（转义后 `&amp;lt;`）还原为 `&lt;` 而非被二次解码成 `<`。
  static String _unescapeHtml(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/')
      .replaceAll('&amp;', '&');

  /// 移除被禁用的 BBCode 标签（保留标签内的内容）
  /// 例如禁用 "color" 时，[color=red]text[/color] → text
  /// 不涉及嵌套问题，只需删除所有匹配的 [tag]、[tag=xxx]、[/tag] 标记
  String _stripDisabledTags(String html) {
    // 标签名 → BBCode 实际标签名的映射
    const tagMapping = {
      'bold': 'b',
      'italic': 'i',
      'underline': 'u',
      'strikethrough': 's',
    };
    // 次标签：禁用一个主标签时连带屏蔽的同义词
    const secondaryMapping = {
      'backcolor': ['background'],
    };
    for (final tag in _disabledTags!) {
      final bbcodeTag = tagMapping[tag] ?? tag;
      html = _stripTag(html, bbcodeTag);
      // 连带屏蔽同义词
      final secondaries = secondaryMapping[tag];
      if (secondaries != null) {
        for (final sec in secondaries) {
          html = _stripTag(html, sec);
        }
      }
    }
    return html;
  }

  /// 删除全部 [tag]、[tag=xxx]、[/tag]
  String _stripTag(String html, String tag) {
    return html.replaceAllMapped(
      RegExp('\\[$tag(?:=[^\\]]*)?\\]|\\[/$tag\\]', caseSensitive: false),
      (_) => '',
    );
  }

  /// 替换带值标签 [tag=value]...[/tag]
  String _replaceTag(
    String html,
    String tag,
    String Function(String match, String value) openReplacer,
    String closeTag,
  ) {
    var result = html;
    // 开标签 [tag=value]
    result = result.replaceAllMapped(
      RegExp('\\[$tag=([^\\]]+)\\]', caseSensitive: false),
      (m) => openReplacer(m.group(0)!, m.group(1)!),
    );
    // 关标签 [/tag]
    result = result.replaceAllMapped(
      RegExp('\\[/$tag\\]', caseSensitive: false),
      (_) => closeTag,
    );
    return result;
  }

  /// 替换表情文本为 <img>
  String _replaceEmoji(String html) {
    final map = _emojiMap;
    if (map == null || map.isEmpty) return html;

    // 构建解析映射：insertText → imageUrl
    final resolved = <String, String>{};

    // 1. 直接从 _emojiMap 获取（insertText → imageUrl）
    for (final entry in map.entries) {
      resolved[entry.key] = entry.value;
    }

    // 2. 通过 _smilieIdMap 补充 [emoji_N] 格式映射
    if (_smilieIdMap != null && _smilieIdMap.isNotEmpty) {
      for (final entry in _smilieIdMap.entries) {
        final smilieId = entry.key;
        final insertText = entry.value;
        final imageUrl = map[insertText];
        if (imageUrl != null) {
          resolved['[emoji_$smilieId]'] = imageUrl;
        }
      }
    }

    // 3. 按长度降序替换（避免短匹配先行）
    final sortedEntries = resolved.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

    for (final entry in sortedEntries) {
      final escapedKey = RegExp.escape(entry.key);
      html = html.replaceAllMapped(
        RegExp(escapedKey),
        (_) =>
            '<img src="${entry.value}" data-type="emoji" style="height:20px;vertical-align:middle;" />',
      );
    }

    return html;
  }

  /// 预处理器：将 `[*]item\n` 转换为闭合的 `<li>item</li>`。
  ///
  /// BBCode 中列表项没有 `[/li]` 关闭标签，原有的 `[*]`→`<li>` 转换
  /// 产生未闭合的 `<li>`，后续 `\n`→`<br>` 会在 `<li>` 内生成多余空行。
  ///
  /// 预处理在 `\n`→`<br>` 之前执行，捕获 `[*]` 后的内容并闭合 `<li>`。
  /// 之后主流程中的 `[*]`→`<li>` 因 `[*]` 已被替换而自动失效。
  String _preprocessListItems(String html) {
    return html.replaceAllMapped(
      RegExp(r'\[\*\]\s*([^\n]*?)\s*\n', caseSensitive: false),
      (m) => '<li>${m.group(1)}</li>',
    );
  }

  /// 内容块标识 — 橙色标签 + 换行 + 内容
  /// 用于 quote / free / hide 等块级 BBCode
  String _labelBlock(String label, String content) {
    return '<span style="color:#FF9900">$label:</span><br>$content';
  }

  /// 移除块级 HTML 容器前后多余的 `<br>`。
  ///
  /// BBCode 原文中常有排版用的换行和缩进，例如：
  /// ```bbcode
  /// [font=...]
  ///   [hide]
  ///     [appdata]{...}[/appdata]
  ///   [/hide]
  /// [/font]
  /// ```
  /// 或列表：
  /// ```bbcode
  /// [list]
  ///   [*]item
  /// [/list]
  /// ```
  /// 在 `\n` → `<br>` 阶段，这些排版换行也被转成了 `<br>`，
  /// 出现在块级容器周围。块级容器自身已产生段落换行，
  /// 其前后的 `<br>` 没有语义含义，只增加空白。
  ///
  /// 通用规则：移除与块级标签紧邻（中间仅空白）的 `<br>`，四个方向：
  /// 开标签前 / 闭标签后 / 闭标签前 / 开标签后。
  /// 未来新增块级标签，同步加入以下四个正则的标签组即可。
  /// [code] 占位符（\x00CODE\d+\x00）还原后是 <pre> 块级容器，也视为边界；
  /// 其还原后的内部 `<li><br></li>`（代码行尾换行）在清理之后生成，不受影响。
  static final RegExp _brBeforeOpen = RegExp(
    r'<br>\s*(?=<(?:div|blockquote|ul|ol|li|table|tr|td|pre|hr)(?:\s|>)|\x00CODE\d+\x00)',
    caseSensitive: false,
  );
  static final RegExp _brAfterClose = RegExp(
    r'((?:</(?:div|blockquote|ul|ol|li|table|tr|td|pre)>|\x00CODE\d+\x00))\s*<br>',
    caseSensitive: false,
  );
  static final RegExp _brBeforeClose = RegExp(
    r'<br>\s*(?=</(?:div|blockquote|ul|ol|li|table|tr|td|pre)>)',
    caseSensitive: false,
  );
  static final RegExp _brAfterOpen = RegExp(
    r'(<(?:div|blockquote|ul|ol|li|table|tr|td|pre)(?:\s[^>]*)?>)\s*<br>',
    caseSensitive: false,
  );

  String _removeAdjacentLineBreaks(String html) {
    // 开标签前的 <br>（如 text\n[list]、[/quote]\n[list]）
    html = html.replaceAll(_brBeforeOpen, '');
    // 闭标签后的 <br>（如 [/list]\n[list]）。
    // 注意：Dart 的 replaceAll 不展开 $1 组引用，须用 replaceAllMapped 取组。
    html = html.replaceAllMapped(_brAfterClose, (m) => m[1]!);
    // 闭标签前的 <br>（如 [/appdata]\n[/list]，本次修复的核心场景）
    html = html.replaceAll(_brBeforeClose, '');
    // 开标签后的 <br>（如 [list]\n 起始、[align=center]\n）
    html = html.replaceAllMapped(_brAfterOpen, (m) => m[1]!);
    return html;
  }

  /// 将 [table] BBCode 转换为 HTML（嵌套安全）。
  ///
  /// 按最外层 [table] 块处理，保证 table 套 table、table 内任意标签互套
  /// 时结构完整。非渲染模式递归解析 tr/td 输出 `<table>` HTML；
  /// 渲染模式（[BBCode2Html.emitTablePlaceholder]）下每个最外层 table 块
  /// 转为占位元素并存入 [tableBlocks]（flutter_html 核心不支持 `<table>`，
  /// 由渲染层 extension 原地替换为 BbcodeTableWidget，含 hide/quote 容器内
  /// 及嵌套表格，均可正确渲染）。
  String _convertTables(String html) {
    final result = StringBuffer();
    var lastEnd = 0;
    for (final block in outerBlocks(html, 'table')) {
      if (block.start > lastEnd) {
        result.write(html.substring(lastEnd, block.start));
      }
      if (_emitTablePlaceholder) {
        // 还原块内 code 占位符为 [code]...[/code]，使 tableBlocks 为纯
        // BBCode，供 BbcodeTableWidget 递归转换（占位符无法跨 converter 传递）
        final blockText = html
            .substring(block.start, block.end)
            .replaceAllMapped(
              RegExp(r'\x00CODE(\d+)\x00'),
              (m) => '[code]${codeBlocks[int.parse(m.group(1)!)]}[/code]',
            );
        tableBlocks.add(blockText);
        result.write(
          '<div class="bbcode-table" data-table-index="${tableBlocks.length - 1}"></div>',
        );
      } else {
        result.write(_renderTableBlock(html.substring(block.start, block.end)));
      }
      lastEnd = block.end;
    }
    result.write(html.substring(lastEnd));
    return result.toString();
  }

  /// 渲染单个最外层 [table]...[/table] 块
  String _renderTableBlock(String block) {
    final content = block.substring(7, block.length - 8); // 去 [table]/[/table]
    final rows = <String>[];
    for (final tr in outerBlocks(content, 'tr')) {
      final trBlock = content.substring(tr.start, tr.end);
      final trInner = trBlock.substring(4, trBlock.length - 5); // 去 [tr]/[/tr]
      final tds = <String>[];
      for (final td in outerBlocks(trInner, 'td')) {
        final tdBlock = trInner.substring(td.start, td.end);
        final tdInner = tdBlock.substring(
          4,
          tdBlock.length - 5,
        ); // 去 [td]/[/td]
        tds.add(_renderTd(tdInner));
      }
      rows.add('<tr style="border:1px solid #E3EDF5;">${tds.join()}</tr>');
    }
    return '<table style="width:100%;border:1px solid #E3EDF5;border-collapse:collapse;">${rows.join()}</table>';
  }

  String _renderTd(String content) {
    // 递归转换 td 内嵌套的 [table]
    final inner = _convertTables(content);
    // 检测 td 内容是否被 <div align="XXX">...</div> 包裹
    // 将 text-align 直接加到 td 样式上，避免 flutter_html 对 td 内块级元素的渲染问题
    final trimmed = inner.trim();
    if (trimmed.startsWith('<div align="') && trimmed.endsWith('</div>')) {
      final attrMatch = RegExp(
        r'^<div\s+align="([^"]+)"\s*>',
      ).firstMatch(trimmed);
      if (attrMatch != null) {
        final align = attrMatch.group(1)!;
        final innermost = trimmed.substring(attrMatch.end, trimmed.length - 6);
        return '<td style="border:1px solid #E3EDF5;padding:4px 8px;text-align:$align">$innermost</td>';
      }
    }
    return '<td style="border:1px solid #E3EDF5;padding:4px 8px;">$inner</td>';
  }
}

/// 栈式匹配所有最外层 `[tag]...[/tag]` 块（含标签本身）。
///
/// 返回完整区间列表（start 为开标签位置、end 为闭标签之后）。
/// 与正则非贪婪匹配不同，这里按栈配对，天然支持嵌套
/// （如 table 套 table、tr 内嵌 table），不会被内层闭标签截断。
/// 未配对的残留标签会被忽略。
List<({int start, int end})> outerBlocks(String input, String tag) {
  final result = <({int start, int end})>[];
  // 注意：不能用 r'...' 原始字符串，否则 $tag 不插值
  final regex = RegExp('\\[/?$tag\\]', caseSensitive: false);
  var depth = 0;
  var start = -1;
  for (final m in regex.allMatches(input)) {
    if (m.group(0)!.toLowerCase() == '[$tag]') {
      if (depth == 0) start = m.start;
      depth++;
    } else {
      depth--;
      if (depth == 0 && start != -1) {
        result.add((start: start, end: m.end));
        start = -1;
      }
    }
  }
  return result;
}

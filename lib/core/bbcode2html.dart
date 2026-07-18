import 'dart:convert';

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

  BBCode2Html({
    Map<String, String>? emojiMap,
    Map<String, String>? smilieIdMap,
    Set<String>? disabledTags,
    String? baseUrl,
    bool autoDetectUrls = true,
  }) : _emojiMap = emojiMap,
       _smilieIdMap = smilieIdMap,
       _disabledTags = disabledTags,
       _baseUrl = baseUrl,
       _autoDetectUrls = autoDetectUrls;

  /// 转换主入口
  String convert(String input) {
    var html = _escapeHtml(input);
    final codes = <String>[];
    final appdataList = <String>[];

    // ========== 0. 保护 [appdata] 块（JSON 不应被 HTML 转义） ==========
    html = html.replaceAllMapped(
      RegExp(r'\[appdata\]([\s\S]*?)\[/appdata\]', caseSensitive: false),
      (m) {
        final raw = m.group(1) ?? '';
        // 此时 raw 已被 _escapeHtml 转义过，需要还原才能解析 JSON
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

    // ========== 1. 移除被禁用的标签（保留内容） ==========
    if (_disabledTags != null && _disabledTags.isNotEmpty) {
      html = _stripDisabledTags(html);
    }

    // ========== 2. 保护 [code] 块 ==========
    html = html.replaceAllMapped(
      RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false),
      (m) {
        final code = m.group(1)!;
        // code 内容不转义，保持原始文本
        final escaped = _codeToHtml(code);
        codes.add(escaped);
        return '\x00CODE${codes.length - 1}\x00';
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
    html = _replaceTag(html, 'color', (_, v) => '<font color="$v">', '</font>');

    // 背景色 [backcolor=...]
    html = _replaceTag(
      html,
      'backcolor',
      (_, v) => '<span style="background-color:$v">',
      '</span>',
    );

    // 对齐 [align=...]
    html = _replaceTag(html, 'align', (_, v) => '<div align="$v">', '</div>');

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
      (m) => '<blockquote>${_labelBlock('引用', m.group(1)!)}</blockquote>',
    );

    // 免费信息 [free]...[/free]
    html = html.replaceAllMapped(
      RegExp(r'\[free\]([\s\S]*?)\[/free\]', caseSensitive: false),
      (m) => '<blockquote>${_labelBlock('免费内容', m.group(1)!)}</blockquote>',
    );

    // 隐藏内容 [hide]...[/hide]（支持 [hide=参数]）
    html = html.replaceAllMapped(
      RegExp(r'\[hide(?:=[^\]]*)?\]([\s\S]*?)\[/hide\]', caseSensitive: false),
      (m) => '<blockquote>${_labelBlock('隐藏内容', m.group(1)!)}</blockquote>',
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

    // 表格
    html = html.replaceAllMapped(
      RegExp(r'\[td\]([\s\S]*?)\[\/td\]', caseSensitive: false),
      (m) {
        var content = m.group(1)!;
        // 检测 td 内容是否被 <div align="XXX">...</div> 包裹
        // 将 text-align 直接加到 td 样式上，避免 flutter_html 对 td 内块级元素的渲染问题
        final trimmed = content.trim();
        if (trimmed.startsWith('<div align="') && trimmed.endsWith('</div>')) {
          final attrMatch = RegExp(
            r'^<div\s+align="([^"]+)"\s*>',
          ).firstMatch(trimmed);
          if (attrMatch != null) {
            final align = attrMatch.group(1)!;
            final inner = trimmed.substring(attrMatch.end, trimmed.length - 6);
            return '<td style="border:1px solid #E3EDF5;padding:4px 8px;text-align:$align">$inner</td>';
          }
        }
        return '<td style="border:1px solid #E3EDF5;padding:4px 8px;">$content</td>';
      },
    );
    html = html.replaceAllMapped(
      RegExp(r'\[tr\]([\s\S]*?)\[\/tr\]', caseSensitive: false),
      (m) => '<tr style="border:1px solid #E3EDF5;">${m.group(1)}</tr>',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[table\]([\s\S]*?)\[\/table\]', caseSensitive: false),
      (m) =>
          '<table style="width:100%;border:1px solid #E3EDF5;border-collapse:collapse;">${m.group(1)}</table>',
    );

    // Media（仅解析 B站，其余转链接）
    html = html.replaceAllMapped(
      RegExp(
        r'\[media(?:=[^\]]+)?\]([\s\S]+?)\[\/media\]',
        caseSensitive: false,
      ),
      (m) {
        var url = m.group(1)!.trim();
        // 提取 B站 BV/AV
        final bvMatch = RegExp(
          r'bilibili\.com/video/(BV[a-zA-Z0-9]+)',
          caseSensitive: false,
        ).firstMatch(url);
        final avMatch = RegExp(
          r'bilibili\.com/video/av(\d+)',
          caseSensitive: false,
        ).firstMatch(url);
        final b23Match = RegExp(
          r'b23\.tv/(BV[a-zA-Z0-9]+)',
          caseSensitive: false,
        ).firstMatch(url);
        if (bvMatch != null) {
          return '<iframe src="https://player.bilibili.com/player.html?bvid=${bvMatch.group(1)}&high_quality=1" width="100%" height="400" frameborder="0" allowfullscreen></iframe>';
        }
        if (avMatch != null) {
          return '<iframe src="https://player.bilibili.com/player.html?bvid=${avMatch.group(1)}&high_quality=1" width="100%" height="400" frameborder="0" allowfullscreen></iframe>';
        }
        if (b23Match != null) {
          return '<iframe src="https://player.bilibili.com/player.html?bvid=${b23Match.group(1)}&high_quality=1" width="100%" height="400" frameborder="0" allowfullscreen></iframe>';
        }
        return '<a href="$url" target="_blank">$url</a>';
      },
    );

    // [audio] → 音频占位
    html = html.replaceAllMapped(
      RegExp(r'\[audio\]([\s\S]*?)\[\/audio\]', caseSensitive: false),
      (m) => '<a href="${m.group(1)}" target="_blank">[音频] ${m.group(1)}</a>',
    );

    // 附件 [attach]...[/attach]
    html = html.replaceAllMapped(
      RegExp(r'\[attach\]([\s\S]+?)\[\/attach\]', caseSensitive: false),
      (m) => '<div class="bbcode-attach">附件: ${m.group(1)}</div>',
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
    html = _replaceTag(
      html,
      'background',
      (_, v) => '<span style="background-color:$v">',
      '</span>',
    );

    // ========== 4. 表情替换 ==========
    html = _replaceEmoji(html);

    // ========== 5. 换行 ==========
    html = html.replaceAll('\n', '<br>');

    // ========== 6. 自动识别纯文本 URL ==========
    if (_autoDetectUrls) {
      html = _autoLinkUrls(html);
    }

    // ========== 7. 恢复 [code] 块 ==========
    for (int i = 0; i < codes.length; i++) {
      html = html.replaceFirst('\x00CODE$i\x00', codes[i]);
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
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  /// 渲染附件类型 appdata
  String _renderAttach(Map<String, dynamic> data) {
    final name = _escapeHtml(data['name'] as String? ?? '附件');
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
  String _renderImageAttach(Map<String, dynamic> data) {
    final url = data['url'] as String? ?? '';
    if (url.isEmpty) return '';
    final width = data['width'] as String? ?? '';
    final resolvedUrl = _resolveUrl(url);
    final escapedUrl = _escapeHtml(resolvedUrl);
    final w = width.isNotEmpty ? ' width="$width"' : '';
    return '<img src="$escapedUrl"$w style="max-width:100%;" />';
  }

  /// HTML 转义
  String _escapeHtml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
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
    // code 内容：空格保留、换行转 <br>、HTML 标签不转义
    final lines = code
        .split('\n')
        .map((l) => '<li>${l.isEmpty ? '<br>' : l}<br></li>')
        .join('');
    return '<pre><code><ol>$lines</ol></code></pre>';
  }

  /// 移除被禁用的 BBCode 标签（保留标签内的内容）
  /// 例如禁用 "color" 时，[color=red]text[/color] → text
  String _stripDisabledTags(String html) {
    for (final tag in _disabledTags!) {
      // 匹配 [tag=任意值]...[/tag] 和 [tag]...[/tag]
      html = html.replaceAllMapped(
        RegExp(
          '\\[$tag(?:=[^\\]]+)?\\]([\\s\\S]*?)\\[/$tag\\]',
          caseSensitive: false,
        ),
        (m) => m.group(1) ?? '',
      );
    }
    return html;
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
            '<img src="${entry.value}"  style="height:20px;vertical-align:middle;" />',
      );
    }

    return html;
  }

  /// 内容块标识 — 橙色标签 + 换行 + 内容
  /// 用于 quote / free / hide 等块级 BBCode
  String _labelBlock(String label, String content) {
    return '<span style="color:#FF9900">$label:</span><br>$content';
  }
}

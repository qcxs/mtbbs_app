part of 'bbcode2html.dart';

/// [BBCode2Html.convert] 的实现（命名扩展，跨库可用）。
///
/// 匿名扩展不会被导出，外部 `import bbcode2html.dart` 后需能直接调用
/// `converter.convert(...)`，因此这里必须显式命名。
extension BBCode2HtmlConvert on BBCode2Html {
  /// 转换主入口
  String convert(String input) {
    var html = htmlEscape(input);
    final appdataList = <String>[];
    // codeBlocks / imageUrls 为公开输出字段，每次转换前清空
    codeBlocks.clear();
    imageUrls.clear();
    _imageSlots.clear();

    // ========== 0. 保护 [appdata] 块（JSON 不应被 HTML 转义） ==========
    html = html.replaceAllMapped(
      RegExp(r'\[appdata\]([\s\S]*?)\[/appdata\]', caseSensitive: false),
      (m) {
        final raw = m.group(1) ?? '';
        // 此时 raw 已被 htmlEscape 转义过，需要还原才能解析 JSON
        final json = unescapeHtml(raw);
        appdataList.add(_renderAppdata(json));
        return '\x00APPDATA${appdataList.length - 1}\x00';
      },
    );

    // ========== 1. 移除被禁用的标签（保留内容） ==========
    if (_disabledTags != null && _disabledTags.isNotEmpty) {
      html = _stripDisabledTags(html);
    }

    // ========== 3. 保护 [code] 块 ==========
    html = html.replaceAllMapped(
      RegExp(r'\[code\]([\s\S]*?)\[/code\]', caseSensitive: false),
      (m) {
        // 存原始代码文本（codeBlocks 供高亮组件使用，还原时才转 HTML）。
        // 注意：此处的 m.group(1) 已被开头 htmlEscape 转义，须反转义还原，
        // 否则占位元素分支（高亮组件不经 HTML 实体解码）会显示
        // &gt;/&lt; 等实体原文。
        codeBlocks.add(unescapeHtml(m.group(1)!));
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
    // 使用 <span style="color:..."> 而非 <font color="...">：
    // inline style 是 CSS 标准，且能统一承载 _normalizeColor 的归一化结果
    // 非法颜色值（_normalizeColor 返回空串）时省略样式，避免渲染器解析异常
    html = _replaceTag(html, 'color', (_, v) {
      final c = BBCode2Html._normalizeColor(v);
      return c.isEmpty ? '<span>' : '<span style="color:$c">';
    }, '</span>');

    // 背景色 [backcolor=...]
    html = _replaceTag(html, 'backcolor', (_, v) {
      final c = BBCode2Html._normalizeColor(v);
      return c.isEmpty ? '<span>' : '<span style="background-color:$c">';
    }, '</span>');

    // 对齐 [align=...]
    // 使用 CSS text-align 而非已废弃的 HTML align 属性
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

    // 列表 [list] / [list=1] / [list=a] → 带内联前缀的段落（见 _convertLists）
    html = _convertLists(html);

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
        final tag = '<img src="$src"$width />';
        // src 在开头 htmlEscape 时已被转义，数据层负责还原成可直接使用的
        // URL 交给渲染层（渲染层不碰实体解码）
        return src.isEmpty ? tag : _emitContentImage(unescapeHtml(src), tag);
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
      final c = BBCode2Html._normalizeColor(v);
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
            // 占位元素：保持容器结构完整，由渲染层
            // 按 data-code-index 原地替换为代码高亮组件
            ? '<div class="bbcode-code" data-code-index="$i"></div>'
            : _codeToHtml(codeBlocks[i]),
      );
    }

    // ========== 7. 恢复 [appdata] 块 ==========
    for (int i = 0; i < appdataList.length; i++) {
      html = html.replaceFirst('\x00APPDATA$i\x00', appdataList[i]);
    }

    // ========== 8. 落地正文图片（按文档顺序编号） ==========
    html = _resolveContentImages(html);

    return html;
  }
}

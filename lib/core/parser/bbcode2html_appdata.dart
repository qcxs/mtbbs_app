part of 'bbcode2html.dart';

extension on BBCode2Html {
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
  ///
  /// 用**纯块级布局**，不用 `display:flex`：渲染器的 flex 不支持 `flex:1`
  /// 收缩（`min-width:0` 同样无效），而文件名是不可断行的长串，一旦横向
  /// 排布就会撑破容器，报 `RenderHtmlFlex overflowed`。
  /// 卡片外观（底色 / 圆角 / 内边距）由渲染层 `.bbcode-attach` 样式按主题提供。
  String _renderAttach(Map<String, dynamic> data) {
    final name = htmlEscape(data['name'] as String? ?? '附件');
    final size = data['size'] as String? ?? '';
    final downloads = data['downloads'] as String? ?? '';
    final url = data['url'] as String? ?? '';

    final meta = <String>[
      if (size.isNotEmpty) '大小: $size',
      if (downloads.isNotEmpty) '下载 $downloads 次',
    ].join(' · ');

    final buf = StringBuffer();
    buf.write('<div class="bbcode-attach">');
    // 第一行：图标 + 文件名（允许换行，长文件名不会溢出）
    buf.write('<div>📎 $name</div>');
    // 第二行：大小 / 下载次数 + 下载链接
    if (meta.isNotEmpty || url.isNotEmpty) {
      buf.write('<div>');
      if (meta.isNotEmpty) {
        buf.write('<span style="font-size:12px;color:#666666;">$meta</span>');
      }
      if (url.isNotEmpty) {
        final resolvedUrl = _resolveUrl(url);
        if (meta.isNotEmpty) buf.write(' &nbsp; ');
        // 与正文图片同一约定：写进属性的值必须转义（`&` → `&amp;`），
        // 否则带参地址会被渲染器解析成非法 HTML 属性
        buf.write(
          '<a href="${htmlEscape(resolvedUrl)}" target="_blank">下载</a>',
        );
      }
      buf.write('</div>');
    }
    buf.write('</div>');
    return buf.toString();
  }

  /// 渲染图片附件类型 appdata
  ///
  /// 不输出 width/height：图片布局由渲染层统一控制（BbcodeImage 按可用宽/封顶宽收缩，
  /// 且不超过图片原始像素宽）。
  String _renderImageAttach(Map<String, dynamic> data) {
    final url = data['url'] as String? ?? '';
    if (url.isEmpty) return '';
    // resolvedUrl 是补全域名后的真实地址（此处尚未转义），直接作为
    // 渲染层的可用 URL 记录，无需再从生成的 HTML 里回读解码
    final resolvedUrl = _resolveUrl(url);
    return _emitContentImage(
      resolvedUrl,
      '<img src="${htmlEscape(resolvedUrl)}" style="max-width:100%;" />',
    );
  }
}

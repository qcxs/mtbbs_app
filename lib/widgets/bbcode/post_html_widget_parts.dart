part of 'post_html_widget.dart';

/// Color → CSS 颜色串（`#rrggbbaa`，flutter_widget_from_html 按 CSS 规范解析）
String _cssColor(Color c) {
  final argb = c.toARGB32();
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final alpha = ((argb >> 24) & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#$rgb$alpha';
}

/// BBCode 各容器/元素的主题样式（对应 flutter_html 时代的 `style` map）
///
/// 列表（`[list]`）在转换层已展开为带前缀的普通段落，不产生 `ul/ol/li`。
Map<String, String>? _stylesFor(dom.Element element, ColorScheme cs) {
  final classes = element.classes;

  // 容器类（由 BBCode2Html 输出的 class 决定）
  if (classes.contains('bbcode-free')) {
    return {'background-color': _cssColor(cs.quoteBg), 'padding': '8px'};
  }
  if (classes.contains('bbcode-attach')) {
    return {
      'background-color': _cssColor(cs.attachBgColor),
      'padding': '8px 12px',
      'border-radius': '6px',
    };
  }
  if (classes.contains('bbcode-locked')) {
    return {
      'background-color': _cssColor(cs.lockedBgColor),
      'padding': '8px 12px',
    };
  }
  if (classes.contains('bbcode-reward')) {
    return {'background-color': _cssColor(cs.quoteBg), 'padding': '8px 12px'};
  }
  if (classes.contains('bbcode-pstatus')) {
    return {
      'font-size': '12px',
      'text-align': 'center',
      'color': _cssColor(cs.pstatusTextColor),
    };
  }

  switch (element.localName) {
    case 'a':
      return {'color': _cssColor(cs.linkColor), 'text-decoration': 'underline'};
    case 'blockquote':
      return {
        'background-color': _cssColor(cs.quoteBg),
        'padding': '8px 12px',
        'margin': '0',
      };
    case 'table':
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'margin': '0',
        'padding': '0',
      };
    case 'td':
      // 不设 text-align：单元格内 [align] 已被 BBCode2Html 转成
      // `<div style="text-align:...">`，由内层元素自行对齐
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'padding': '4px 8px',
      };
    case 'hr':
      return {
        'height': '1px',
        'background-color': _cssColor(cs.outlineVariant),
        'margin': '8px 0',
      };
  }
  return null;
}

/// 内联表情图片（跟随文字基线行走）
class _EmojiImage extends StatelessWidget {
  final String url;
  const _EmojiImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: emojiCacheManager,
      width: 20,
      height: 20,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => Icon(
        Icons.emoji_emotions_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

/// 帖子正文图片（块级，独占一行）
///
/// 不挂 `onTap`：点击需冒泡给外层 `[url]` 链接，挂 tap 会消费掉。
/// 右上角有一个独立的"看大图"按钮（见 [_ImageZoomButton]）——它自身
/// 消费点击，不覆盖图片本体，因此不违反上述冒泡约定。
///
/// 多图：`galleryUrls` 为**本帖/本楼**的全部正文图片，长按菜单与右上角
/// 按钮都进入同一画廊，可左右滑动切换（不跨帖、不跨楼层）。
///
/// 职责边界（docs/02「数据层 ↔ 渲染层职责边界」）：URL 由转换层产出为
/// **可直接使用**的地址，本组件原样消费——不解码实体、不拼域名、不猜格式；
/// 只做越界防护（索引越界按首图、未传画廊按单图），不崩溃。
///
/// 宽度策略：
/// - 显式尺寸（`[img=W,H]`）→ 强制该宽度（同 HTML `<img width>`，可放大）
/// - 未指定尺寸 → 只约束上限，实际宽度由图片原始像素决定：低分辨率小图
///   **不放大**（放大只会更糊），高分辨率大图仍按可用宽 / 封顶宽收缩
class BbcodeImage extends StatelessWidget {
  final String url;
  final double? explicitWidth;
  final double maxImageWidth;

  /// 同帖/同楼的全部正文图片（按文档顺序，来自 `data-img-index` 同源的
  /// `BBCode2Html.imageUrls`）；未传时退化为单图
  final List<String> galleryUrls;

  /// [url] 在 [galleryUrls] 中的下标（来自 `data-img-index`）；越界按 0 处理
  final int galleryIndex;

  const BbcodeImage({
    super.key,
    required this.url,
    this.explicitWidth,
    this.maxImageWidth = 600,
    this.galleryUrls = const [],
    this.galleryIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 越界防护：索引缺失/越界退化为首图，未传画廊退化为单图
    final urls = galleryUrls.isNotEmpty ? galleryUrls : <String>[url];
    final index = (galleryIndex >= 0 && galleryIndex < urls.length)
        ? galleryIndex
        : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final width = resolvePostImageWidth(
          explicitWidth: explicitWidth,
          availableWidth: available,
          maxImageWidth: maxImageWidth,
        );
        // 未指定尺寸时只给宽度上限、不传 width：渲染器对块级自定义组件下发的是
        // 松约束，图片会按解码后的原始像素测量。解码链路（memCacheWidth →
        // ResizeImage）与缓存层的磁盘缩放都是 allowUpscaling=false，解码结果
        // 不会超过原图，因此"只设上限"即等价于 min(上限, 原始像素宽)。
        final hasExplicitWidth = explicitWidth != null && explicitWidth! > 0;
        final image = CachedNetworkImage(
          imageUrl: url,
          cacheManager: imageCacheManager,
          // 显式尺寸才给 width：给了就会把低分辨率小图拉伸放大（变糊）
          width: hasExplicitWidth ? width : null,
          memCacheWidth: (width * 2).toInt(),
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox(
            height: 100,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, size: 48, color: cs.outline),
        );
        return GestureDetector(
          onLongPress: () => showImageActions(
            context,
            imageUrls: urls,
            initialIndex: index,
            sourceInfo: '帖子图片',
          ),
          child: Stack(
            children: [
              // 显式尺寸：固定盒宽，加载中/加载失败也保持占位宽度，避免状态切换跳动
              // 未指定尺寸：上限盒宽，加载中按上限占位，解码后收敛到原始像素宽
              hasExplicitWidth
                  ? SizedBox(width: width, child: image)
                  : ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: width),
                      child: image,
                    ),
              Positioned(
                top: 6,
                right: 6,
                child: _ImageZoomButton(
                  onTap: () => showImageViewer(
                    context,
                    imageUrls: urls,
                    initialIndex: index,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 图片右上角的"看大图"按钮
///
/// 长按菜单里也有"查看图片"，但长按有延迟、且在 SelectionArea 里容易
/// 触发文本选择，所以给一个显式的一键入口。
///
/// 底色固定为半透明黑 + 白色图标：它叠在任意图片上，跟随主题变色反而
/// 会与图片内容撞色（与全屏查看器的黑底白字是同一约定）。
class _ImageZoomButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ImageZoomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.zoom_in, size: 18, color: Colors.white),
      ),
    );
  }
}

/// 链接点击处理 — QQ / 邮件 / 普通链接
void _handleLinkTap(BuildContext context, String url) {
  // QQ 链接特殊处理
  if (url.contains('wpa.qq.com')) {
    final qqMatch = RegExp(r'uin=(\d+)').firstMatch(url);
    if (qqMatch != null) {
      _showActionDialog(
        context,
        title: 'QQ',
        message: 'QQ号:\n${qqMatch.group(1)}',
        actionLabel: '复制',
        copyValue: qqMatch.group(1)!,
        onAction: () {
          Clipboard.setData(ClipboardData(text: qqMatch.group(1)!));
          showToast('已复制', duration: const Duration(seconds: 1));
        },
      );
      return;
    }
  }

  // mailto 链接
  if (url.startsWith('mailto:')) {
    _showActionDialog(
      context,
      title: '发送邮件',
      message: '发送至:\n${url.substring(7)}',
      actionLabel: '发送',
      copyValue: url.substring(7),
      onAction: () {
        final uri = Uri.tryParse(url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
    return;
  }

  // 普通链接 — 可编辑弹窗
  _showUrlEditDialog(context, url);
}

Future<void> _showActionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required VoidCallback onAction,
  required String copyValue,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      constraints: const BoxConstraints(maxWidth: 360),
      title: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(ctx).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SelectableText(message, style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('copy'),
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop('action'),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  switch (result) {
    case 'action':
      onAction();
    case 'copy':
      await Clipboard.setData(ClipboardData(text: copyValue));
      if (context.mounted) {
        showToast('已复制', duration: const Duration(seconds: 1));
      }
  }
}

/// 链接确认弹窗 — App打开（路由匹配）/ 外部浏览器 / 取消
Future<void> _showUrlEditDialog(BuildContext context, String url) async {
  final action = await showDialog<String>(
    context: context,
    builder: (_) => _UrlActionDialog(url: url),
  );
  if (action == null || context.mounted == false) return;

  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;

  switch (action) {
    case '__app__':
      // 与首页链接点击、系统入站链接共用同一决策（App 内优先，兜底内置浏览器）
      final target = UrlRouter.resolveTarget(url);
      if (target != null) context.push(target);
    case '__external__':
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 链接操作确认弹窗
class _UrlActionDialog extends StatelessWidget {
  final String url;
  const _UrlActionDialog({required this.url});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 280),
      title: Row(
        children: [
          const Expanded(child: Text('链接', style: TextStyle(fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 20),
            tooltip: '外部打开',
            onPressed: () => Navigator.of(context).pop('__external__'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(url, style: const TextStyle(fontSize: 12)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('__app__'),
          child: const Text('打开'),
        ),
      ],
    );
  }
}

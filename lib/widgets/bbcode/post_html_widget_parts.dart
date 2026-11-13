part of 'post_html_widget.dart';

/// flutter_math_fork 缺失的少量 KaTeX 别名 → 兼容写法
///
/// 只影响渲染，不改缓存里的 TeX 原文（`\lt`/`\gt` 在 52pojie 的
/// Parsedown 公式里很常见，如 `a \lt b`）。
String _normalizeMathTex(String tex) => tex
    .replaceAllMapped(RegExp(r'\\lt\b'), (_) => '<')
    .replaceAllMapped(RegExp(r'\\gt\b'), (_) => '>');

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
/// [monoFamilies] 为等宽字体族链（来自主题），用于行内代码。
/// [availableWidth] 为正文可用宽度（随窗口尺寸变化），用于表格宽度决策。
/// [fontSize] 为正文字号，用于估算表格内容宽度。
Map<String, String>? _stylesFor(
  dom.Element element,
  ColorScheme cs, {
  List<String>? monoFamilies,
  double availableWidth = 0,
  double fontSize = 16,
}) {
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
    case 'code':
      // 行内代码（`[md]` 反引号片段）：渲染器只给 `Courier`/`monospace`，
      // 而 Windows 没有这两个字体族、会退化成普通比例字体，再加上没有底色，
      // 结果与正文完全无法区分（docs/07 #123）。这里补主题等宽字体 + 淡底。
      return {
        'background-color': _cssColor(
          cs.onSurface.withValues(
            alpha: cs.brightness == Brightness.dark ? 0.18 : 0.08,
          ),
        ),
        if (monoFamilies != null && monoFamilies.isNotEmpty)
          'font-family': monoFamilies
              .map((f) => f.contains(' ') ? '"$f"' : f)
              .join(','),
      };
    case 'blockquote':
      return {
        'background-color': _cssColor(cs.quoteBg),
        'padding': '8px 12px',
        'margin': '0',
      };
    case 'table':
      // 宽度策略（随可用宽度实时变化，不写死列数）：
      // - 内容能装下（估算不换行宽度 ≤ 可用宽度×0.92）且各列内容量不悬殊：
      //   占满正文宽度，短表格不再缩成一条、内容均衡的表格宽度整齐
      // - 否则按内容自适应：但**压缩优先**——用 max-width 把表格钉在可用宽度内，
      //   内容自动折行；只有不可断词（长 URL 等）的最窄宽度都装不下时才横向滚动
      final width = _tableWidth(
        element,
        availableWidth: availableWidth,
        fontSize: fontSize,
      );
      final bounded = availableWidth.isFinite && availableWidth > 0;
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'margin': '0',
        'padding': '0',
        if (bounded) 'max-width': '${availableWidth.floor()}px',
        'width': ?width,
      };
    case 'td':
      // 不设 text-align：单元格内 [align] 已被 BBCode2Html 转成
      // `<div style="text-align:...">`，由内层元素自行对齐
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'padding': '4px 8px',
      };
    case 'th':
      // Markdown 表格的表头（`[md]` 路径产生 th）
      return {
        'border': '1px solid ${_cssColor(cs.outlineVariant)}',
        'padding': '4px 8px',
        'font-weight': 'bold',
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

/// 表格是否应占满正文宽度，返回 `'100%'` 或 null（保持内容自适应）。
///
/// 估算各列「单行不换行」所需宽度：
/// - 内容能装下才考虑撑满（撑满后渲染器会把富余宽度平均分给各列，
///   所以内容本身放不下时撑满反而会挤掉可读性）
/// - 各列内容量相差悬殊时也不撑满（例如 `#` 列旁边的长描述列，
///   平均分列会让 `#` 列宽得离谱）
///
/// 阈值 0.92 预留边距，2.5 为列内容量比例上限，均为观感折中值。
String? _tableWidth(
  dom.Element table, {
  required double availableWidth,
  required double fontSize,
}) {
  if (!availableWidth.isFinite || availableWidth <= 0) return null;
  final weights = _tableColumnWeights(table);
  if (weights.isEmpty) return null;

  // 中文 ≈ 1em，其余 ≈ 0.55em；每列再计入左右 padding 与边框
  final estimated =
      weights.fold(0.0, (sum, w) => sum + w) * fontSize + weights.length * 18;
  var maxWeight = 0.0;
  var minWeight = double.infinity;
  for (final w in weights) {
    if (w > maxWeight) maxWeight = w;
    if (w < minWeight) minWeight = w;
  }
  if (estimated > availableWidth * 0.92) return null;
  if (maxWeight / (minWeight < 0.1 ? 0.1 : minWeight) > 2.5) return null;
  return '100%';
}

/// 各列内容量（按字符宽度加权，取整列最大值）。
///
/// 返回列表长度即列数；嵌套表格的行不计入外层。
List<double> _tableColumnWeights(dom.Element table) {
  var columns = 0;
  final weights = <int, double>{};
  for (final row in table.querySelectorAll('tr')) {
    if (_nearestTable(row) != table) continue; // 排除嵌套表格的行
    var col = 0;
    for (final cell in row.children) {
      if (cell.localName != 'td' && cell.localName != 'th') continue;
      final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
      final perColumn = _weightedLength(cell) / (span > 0 ? span : 1);
      for (var i = 0; i < span; i++) {
        weights.update(
          col + i,
          (v) => v > perColumn ? v : perColumn,
          ifAbsent: () => perColumn,
        );
      }
      col += span;
    }
    if (col > columns) columns = col;
  }
  return List.generate(columns, (i) => weights[i] ?? 1);
}

/// 文本宽度加权值：中日韩等全角字符按 1，拉丁字符按 0.55
double _weightedLength(dom.Element element) {
  var v = 0.0;
  for (final rune in element.text.runes) {
    v += _isWideRune(rune) ? 1.0 : 0.55;
  }
  return v < 1 ? 1 : v;
}

bool _isWideRune(int rune) =>
    (rune >= 0x2E80 && rune <= 0x9FFF) ||
    (rune >= 0x3000 && rune <= 0x303F) ||
    (rune >= 0xFF00 && rune <= 0xFFEF);

dom.Element? _nearestTable(dom.Element element) {
  for (var p = element.parent; p != null; p = p.parent) {
    if (p.localName == 'table') return p;
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
        // 解码宽度与"布局宽度"解耦：取 min(屏幕宽, max(图片最大宽度, 显式宽))。
        // 布局宽一图一变（宽/窄布局、分享卡、编辑器预览各不同），若拿它当解码宽，
        // 同一张图会按不同尺寸各解一份、互相挤占 imageCache（返回时重解码，见 docs/07 #91）。
        // 用"屏幕宽 + 图片最大宽度"这个与布局无关的量，全场景命中同一条目。
        final screenWidth = MediaQuery.sizeOf(context).width;
        final intended = (explicitWidth ?? 0) > maxImageWidth
            ? explicitWidth!
            : maxImageWidth;
        final decodeWidth = intended < screenWidth ? intended : screenWidth;
        final image = CachedNetworkImage(
          imageUrl: url,
          cacheManager: imageCacheManager,
          // 显式尺寸才给 width：给了就会把低分辨率小图拉伸放大（变糊）
          width: hasExplicitWidth ? width : null,
          memCacheWidth: (decodeWidth * 2).round(),
          // 命中缓存（内存/磁盘）时不再淡入，避免"返回页面图片重新加载"的观感
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
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
          child: _ZoomableImage(
            onOpenViewer: () =>
                showImageViewer(context, imageUrls: urls, initialIndex: index),
            // 显式尺寸：固定盒宽，加载中/加载失败也保持占位宽度，避免状态切换跳动
            // 未指定尺寸：上限盒宽，加载中按上限占位，解码后收敛到原始像素宽
            child: hasExplicitWidth
                ? SizedBox(width: width, child: image)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width),
                    child: image,
                  ),
          ),
        );
      },
    );
  }
}

/// 小图阈值：图片渲染宽度小于该值时，右上角不显示"看大图"按钮。
///
/// 小图放大后只会更糊，按钮本身还会盖住图片内容；长按菜单里的"查看图片"
/// 仍然保留，作为需要时的兜底入口。
const double _kZoomButtonMinImageWidth = 120;

/// 「图片 + 右上角放大按钮」的宿主，负责按实际渲染尺寸过滤小图。
///
/// 宽度**量的是渲染结果**（而不是显式尺寸或原始像素），因为"图小不小"取决于
/// 它最终画出来多大：`[img=60,H]` 这类显式小图与低分辨率小图同样不该给放大入口，
/// 而低分辨率小图的渲染宽度又要等解码完成才知道。
/// 量取放在每帧之后（尺寸稳定后就不再 setState），能自然跟上
/// "占位 → 解码完成" 的尺寸变化。
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.child, required this.onOpenViewer});

  /// 已按宽度策略约束好的图片
  final Widget child;
  final VoidCallback onOpenViewer;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final GlobalKey _boxKey = GlobalKey();
  bool _showZoom = false;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncZoomButton());
    return Stack(
      children: [
        // 套一层 SizedBox：它的 RenderBox 尺寸即图片渲染尺寸（不含按钮自身）
        SizedBox(key: _boxKey, child: widget.child),
        if (_showZoom)
          Positioned(
            top: 6,
            right: 6,
            child: _ImageZoomButton(onTap: widget.onOpenViewer),
          ),
      ],
    );
  }

  void _syncZoomButton() {
    if (!mounted) return;
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final show = box.size.width >= _kZoomButtonMinImageWidth;
    if (show != _showZoom) setState(() => _showZoom = show);
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
        onAction: () async {
          final ok = await ClipboardHelper.write(qqMatch.group(1)!);
          showToast(
            ok ? '已复制' : '复制到剪切板失败',
            duration: const Duration(seconds: 1),
          );
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
      final ok = await ClipboardHelper.write(copyValue);
      if (context.mounted) {
        showToast(
          ok ? '已复制' : '复制到剪切板失败',
          duration: const Duration(seconds: 1),
        );
      }
  }
}

/// 链接确认弹窗 — App打开（路由匹配）/ 外部浏览器 / 取消
Future<void> _showUrlEditDialog(BuildContext context, String url) async {
  // 作者可能直接发相对地址（forum.php?...）。解析层按原文保留，
  // 这里按**当前页面所属站点**补全，再用绝对地址走 App 路由/浏览器。
  // 不能用全局 SiteStore：跨站页面可能正以临时身份访问他站。
  final resolvedUrl = resolveContentUrl(
    url,
    base: SiteScope.read(context).baseUrl,
  );
  final uri = Uri.tryParse(resolvedUrl);
  // 只处理可打开的网页/邮件地址；App 内路径不经过链接弹窗
  if (uri == null || !uri.hasScheme) return;
  if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'mailto') {
    return;
  }

  final action = await showDialog<String>(
    context: context,
    builder: (_) => _UrlActionDialog(url: resolvedUrl),
  );
  if (action == null || context.mounted == false) return;

  switch (action) {
    case '__app__':
      // 与首页链接点击、系统入站链接共用同一决策（App 内优先，兜底内置浏览器）
      final target = UrlRouter.resolveTarget(resolvedUrl);
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

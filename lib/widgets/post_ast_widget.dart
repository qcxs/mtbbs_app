import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/bbcode_parser.dart';
import '../core/url_router.dart';
import 'image_preview/image_preview.dart';

/// 可被全局/局部禁用的 BBCode 项
const bbcodeStyleTags = <String>{
  'bold',
  'italic',
  'underline',
  'strikethrough',
  'color',
  'size',
  'font',
  'backcolor',
  'imgDimension',
  'link',
  'email',
  'qq',
};

/// AST → Flutter Widget 递归渲染器
class PostAstWidget extends StatelessWidget {
  final List<AstNode> nodes;
  final double fontSize;
  final double indentWidth;
  final Map<String, String>? emojiMap;

  /// 被禁用的 BBCode 标签集合
  final Set<String>? disabledTags;

  /// 图片最大显示宽度
  final double maxImageWidth;

  const PostAstWidget({
    super.key,
    required this.nodes,
    this.fontSize = 16,
    this.indentWidth = 4,
    this.emojiMap,
    this.disabledTags,
    this.maxImageWidth = 600,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildBlocks(context, nodes),
    );
  }

  // ==================== 块级节点 ====================

  List<Widget> _buildBlocks(BuildContext context, List<AstNode> nodes) {
    return nodes.map((n) => _buildBlock(context, n)).toList();
  }

  Widget _buildBlock(BuildContext context, AstNode node) {
    switch (node.type) {
      case 'paragraph':
        if (node.children.any((c) => !_canBeInline(c))) {
          return _buildSegmentParagraph(context, node);
        }
        return Padding(
          padding: EdgeInsets.only(bottom: indentWidth),
          child: _buildRichText(context, node),
        );

      case 'quote':
      case 'free':
      case 'hide':
        return _buildYellowContainer(context, node);

      case 'code':
        return _buildCode(context, node);

      case 'list':
        return _buildList(context, node);

      case 'align':
        return _buildAlign(context, node);

      case 'link':
      case 'email':
      case 'qq':
        return _buildLinkContainer(context, node);

      case 'img':
        final src = node.attrs['value'] ?? '';
        if (src.isEmpty) return const SizedBox.shrink();
        return _buildImageNode(
          context,
          src,
          onLongPress: () => _showImageMenu(context, src),
        );

      case 'audio':
        return _mediaPlaceholder(
          context,
          Icons.audiotrack_outlined,
          '音频',
          node,
        );

      case 'media':
        return _mediaPlaceholder(context, Icons.videocam_outlined, '视频', node);

      case 'attach':
      case 'attachment':
      case 'attachimg':
        return _mediaPlaceholder(
          context,
          Icons.attach_file_outlined,
          '附件',
          node,
        );

      case 'appdata':
        return _buildAppData(context, node);

      case 'emoji':
        return _buildEmojiBlock(node);

      case 'hr':
      case 'thematicBreak':
        return Padding(
          padding: EdgeInsets.symmetric(vertical: indentWidth * 2),
          child: Divider(height: 1, color: Colors.grey.shade300),
        );

      default:
        return SizedBox.shrink();
    }
  }

  // ==================== 黄底容器 ====================

  Widget _buildYellowContainer(BuildContext context, AstNode node) {
    final label = node.type == 'hide' ? '隐藏内容' : '';
    final labelColor = node.type == 'hide' ? Colors.red.shade700 : Colors.grey;

    return SizedBox(
      width: double.infinity,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize - 4,
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildBlockChildren(context, node.children),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 代码块 ====================

  Widget _buildCode(BuildContext context, AstNode node) {
    final code = _collectText(node);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: indentWidth),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: fontSize - 2,
                color: Colors.green.shade200,
                height: 1.5,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '复制',
                  style: TextStyle(
                    fontSize: fontSize - 4,
                    color: Colors.green.shade300,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 列表 ====================

  Widget _buildList(BuildContext context, AstNode node) {
    final ordered = node.attrs['value'];
    final items = node.children.where((c) => c.type == 'listItem').toList();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: indentWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(items.length, (i) {
          final item = items[i];
          final prefix = ordered == null
              ? ''
              : ordered == 'a'
              ? '${String.fromCharCode(97 + i)}.'
              : '${i + 1}.';

          final widgets = <Widget>[];
          for (final child in item.children) {
            if (child.type == 'paragraph') {
              if (child.children.any((c) => !_canBeInline(c))) {
                widgets.add(_buildSegmentParagraph(context, child));
              } else {
                widgets.addAll(_buildInlineAsRichText(context, child));
              }
            } else {
              widgets.add(_buildBlock(context, child));
            }
          }

          return Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (prefix.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(prefix, style: TextStyle(fontSize: fontSize)),
                  ),
                Expanded(
                  child: widgets.isEmpty
                      ? SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: widgets,
                        ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildInlineAsRichText(BuildContext context, AstNode node) {
    final spans = _buildInlineSpans(context, node);
    if (spans.isEmpty) return [];
    final linkStyle = _LinkStyle.of(context);
    final textStyle = TextStyle(
      fontSize: fontSize,
      color: linkStyle?.style.color ?? Colors.black,
      decoration: linkStyle?.style.decoration,
    );
    return [
      RichText(
        text: TextSpan(style: textStyle, children: spans),
      ),
    ];
  }

  // ==================== 对齐 ====================

  Widget _buildAlign(BuildContext context, AstNode node) {
    final align = node.attrs['value'] ?? 'left';
    Alignment alignment;
    TextAlign textAlign;
    switch (align) {
      case 'center':
        alignment = Alignment.center;
        textAlign = TextAlign.center;
        break;
      case 'right':
        alignment = Alignment.centerRight;
        textAlign = TextAlign.right;
        break;
      default:
        alignment = Alignment.centerLeft;
        textAlign = TextAlign.left;
    }
    return Align(
      alignment: alignment,
      child: _buildBlockContainer(context, node, textAlign),
    );
  }

  Widget _buildBlockContainer(
    BuildContext context,
    AstNode node, [
    TextAlign? textAlign,
  ]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildBlockChildren(
        context,
        node.children,
        textAlign: textAlign,
      ),
    );
  }

  // ==================== 链接容器 ====================

  Widget _buildLinkContainer(BuildContext context, AstNode node) {
    String url;
    switch (node.type) {
      case 'email':
        url = node.attrs['value'] ?? _collectText(node);
        if (!url.startsWith('mailto:')) url = 'mailto:$url';
        break;
      case 'qq':
        url = node.attrs['value'] ?? _collectText(node);
        break;
      default:
        url = node.attrs['value'] ?? _collectText(node);
    }
    return GestureDetector(
      onTap: () => _handleLinkTap(context, url, node.type),
      child: _LinkStyle(
        style: TextStyle(
          color: Color(0xFF336699),
          decoration: TextDecoration.underline,
        ),
        child: Builder(builder: (ctx) => _buildBlockContainer(ctx, node)),
      ),
    );
  }

  void _handleLinkTap(BuildContext context, String url, String type) {
    if (type == 'qq') {
      _showActionDialog(
        context,
        title: 'QQ',
        message: 'QQ号:\n$url',
        actionLabel: '复制',
        copyValue: url,
        onAction: () {
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        },
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无效的$type: $url')));
      return;
    }
    final labels = switch (type) {
      'email' => ('发送邮件', '发送至:\n$url'),
      _ => ('打开链接', '跳转到:\n$url'),
    };
    _showActionDialog(
      context,
      title: labels.$1,
      message: labels.$2,
      actionLabel: type == 'email' ? '发送' : '打开',
      copyValue: url,
      onAction: () {
        switch (type) {
          case 'email':
            launchUrl(uri, mode: LaunchMode.externalApplication);
          default:
            final routeResult = UrlRouter.parse(url);
            if (routeResult.appPath != null) {
              context.push(routeResult.appPath!);
            } else {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
        }
      },
    );
  }

  // ==================== 多媒体占位符 ====================

  Widget _mediaPlaceholder(
    BuildContext context,
    IconData icon,
    String label,
    AstNode node,
  ) {
    final src = node.attrs['value'] ?? '';
    final isMedia = label == '音频' || label == '视频';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: indentWidth),
      child: GestureDetector(
        onTap: isMedia && src.isNotEmpty
            ? () => _handleLinkTap(context, src, 'link')
            : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                '[$label]',
                style: TextStyle(
                  fontSize: fontSize - 2,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (src.isNotEmpty) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    src,
                    style: TextStyle(
                      fontSize: fontSize - 4,
                      color: Colors.grey.shade400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==================== App 专用占位符 ====================

  Widget _buildAppData(BuildContext context, AstNode node) {
    final raw = node.attrs['value'] ?? '';
    if (raw.isEmpty) return const SizedBox.shrink();
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    switch (data['type'] as String?) {
      case 'attach':
        return _buildAttachment(context, data);
      case 'image_attach':
        final url = data['url'] as String? ?? '';
        if (url.isEmpty) return const SizedBox.shrink();
        return _buildImageNode(
          context,
          url,
          onLongPress: () => _showImageMenu(context, url, meta: data),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAttachment(BuildContext context, Map<String, dynamic> data) {
    final name = data['name'] as String? ?? '附件';
    final size = data['size'] as String? ?? '';
    final downloads = data['downloads'] as String? ?? '';
    final url = data['url'] as String? ?? '';
    final aid = data['aid'] as String? ?? '';
    final label = StringBuffer(name);
    if (size.isNotEmpty) {
      label.write('  ($size');
      if (downloads.isNotEmpty) label.write('，下载 $downloads 次');
      label.write(')');
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: indentWidth),
      child: GestureDetector(
        onTap: () =>
            _showAttachmentDialog(context, name, size, downloads, url, aid),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (label.length > name.length)
                      Text(
                        label.toString().substring(name.length).trim(),
                        style: TextStyle(
                          fontSize: fontSize - 2,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.download_rounded,
                color: Colors.blue.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== 对话框 ====================

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复制'),
              duration: Duration(seconds: 1),
            ),
          );
        }
    }
  }

  Future<void> _showAttachmentDialog(
    BuildContext context,
    String name,
    String size,
    String downloads,
    String url,
    String aid,
  ) async {
    final buf = StringBuffer('文件名: $name');
    if (size.isNotEmpty) buf.write('\n大小: $size');
    if (downloads.isNotEmpty) buf.write('\n下载次数: $downloads');
    await _showActionDialog(
      context,
      title: '附件',
      message: buf.toString(),
      actionLabel: '下载',
      copyValue: url.isNotEmpty ? url : aid,
      onAction: () {
        if (url.isNotEmpty) _openUrl(context, url);
      },
    );
  }

  // ==================== 图片 ====================

  void _showImageMenu(
    BuildContext context,
    String src, {
    Map<String, dynamic>? meta,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('查看图片'),
              onTap: () {
                Navigator.of(ctx).pop();
                Future.microtask(
                  () => showImageViewer(context, imageUrls: [src]),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看图片信息'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showRawImageInfo(context, src, meta: meta);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRawImageInfo(
    BuildContext context,
    String src, {
    Map<String, dynamic>? meta,
  }) {
    final content = meta != null
        ? 'URL: $src\n\n原始数据:\n${jsonEncode(meta)}'
        : 'URL: $src';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 400),
        title: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 8),
            const Expanded(child: Text('图片信息', style: TextStyle(fontSize: 16))),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(content, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageNode(
    BuildContext context,
    String src, {
    VoidCallback? onLongPress,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: indentWidth),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxImageWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: CachedNetworkImage(
              imageUrl: src,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              placeholder: (_, __) => const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openUrl(BuildContext context, String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载链接: $url')));
    }
  }

  // ==================== 表情块级回退 ====================

  Widget _buildEmojiBlock(AstNode node) {
    final name = node.attrs['value'] ?? '';
    final url = emojiMap?['[$name]'];
    if (url != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 22,
          height: 22,
          errorWidget: (_, __, ___) => Icon(
            Icons.emoji_emotions_outlined,
            size: 18,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }
    return Text('[$name]', style: TextStyle(fontSize: fontSize));
  }

  // ==================== 内联渲染 ====================

  Widget _buildRichText(
    BuildContext context,
    AstNode node, {
    TextAlign? textAlign,
  }) {
    final spans = _buildInlineSpans(context, node);
    if (spans.isEmpty) return SizedBox.shrink();

    final linkStyle = _LinkStyle.of(context);
    final textStyle = TextStyle(
      fontSize: fontSize,
      color: linkStyle?.style.color ?? Colors.black,
      decoration: linkStyle?.style.decoration,
      height: 1.6,
    );

    return RichText(
      text: TextSpan(style: textStyle, children: spans),
      textAlign: textAlign ?? TextAlign.start,
    );
  }

  // ==================== 段落分段 ====================

  Widget _buildSegmentParagraph(BuildContext context, AstNode node) {
    final segments = <Widget>[];
    final buf = <AstNode>[];

    void flushText() {
      if (buf.isEmpty) return;
      segments.add(
        Padding(
          padding: EdgeInsets.only(bottom: indentWidth),
          child: _buildRichText(
            context,
            AstNode(type: 'paragraph', children: List.from(buf)),
          ),
        ),
      );
      buf.clear();
    }

    for (final child in node.children) {
      if (_canBeInline(child)) {
        buf.add(child);
      } else {
        flushText();
        segments.add(_buildBlock(context, child));
      }
    }
    flushText();

    if (segments.isEmpty) return SizedBox.shrink();
    if (segments.length == 1) return segments.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments,
    );
  }

  bool _canBeInline(AstNode node) {
    switch (node.type) {
      case 'text':
      case 'lineBreak':
      case 'bold':
      case 'italic':
      case 'underline':
      case 'strikethrough':
      case 's':
      case 'color':
      case 'size':
      case 'font':
      case 'backcolor':
      case 'background':
      case 'emoji':
        return true;
      case 'img':
      case 'attachimg':
        final hasDim = node.attrs.containsKey('imgWidth');
        final ignoreDim = disabledTags?.contains('imgDimension') == true;
        return !ignoreDim && hasDim;
      default:
        return false;
    }
  }

  List<Widget> _buildBlockChildren(
    BuildContext context,
    List<AstNode> children, {
    TextAlign? textAlign,
  }) {
    final list = <Widget>[];
    for (final child in children) {
      if (child.type == 'paragraph') {
        if (child.children.any((c) => !_canBeInline(c))) {
          list.add(_buildSegmentParagraph(context, child));
        } else {
          list.add(
            Padding(
              padding: EdgeInsets.only(bottom: indentWidth),
              child: _buildRichText(context, child, textAlign: textAlign),
            ),
          );
        }
      } else {
        list.add(_buildBlock(context, child));
      }
    }
    return list;
  }

  List<InlineSpan> _buildInlineSpans(BuildContext context, AstNode node) {
    if (node.children.isEmpty && node.text != null) {
      return [TextSpan(text: node.text)];
    }
    if (node.children.isEmpty) return [];

    final spans = <InlineSpan>[];
    for (final child in node.children) {
      if (child.type == 'paragraph') {
        spans.addAll(_buildInlineSpans(context, child));
      } else {
        spans.addAll(_wrapInlineNode(context, child));
      }
    }
    return spans;
  }

  List<InlineSpan> _wrapInlineNode(BuildContext context, AstNode node) {
    final linkStyle = _LinkStyle.of(context);
    final baseStyle = TextStyle(
      fontSize: fontSize,
      color: linkStyle?.style.color ?? Colors.black,
      decoration: linkStyle?.style.decoration,
    );
    return [_buildNestedSpan(context, node, baseStyle)];
  }

  InlineSpan _buildNestedSpan(
    BuildContext context,
    AstNode node,
    TextStyle parentStyle,
  ) {
    TextStyle style = parentStyle;

    if (disabledTags != null &&
        bbcodeStyleTags.contains(node.type) &&
        disabledTags!.contains(node.type)) {
      if (node.children.isNotEmpty) {
        final children = node.children
            .map((c) => _buildNestedSpan(context, c, parentStyle))
            .toList();
        return TextSpan(style: parentStyle, children: children);
      }
      if (node.text != null)
        return TextSpan(text: node.text, style: parentStyle);
      return TextSpan(text: '', style: parentStyle);
    }

    switch (node.type) {
      case 'text':
        return TextSpan(text: node.text, style: style);

      case 'lineBreak':
        return TextSpan(text: '\n', style: style);

      case 'bold':
        style = style.copyWith(fontWeight: FontWeight.bold);
      case 'italic':
        style = style.copyWith(fontStyle: FontStyle.italic);
      case 'underline':
        style = style.copyWith(decoration: TextDecoration.underline);
      case 'strikethrough':
      case 's':
        style = style.copyWith(decoration: TextDecoration.lineThrough);

      case 'color':
        {
          final v = node.attrs['value'];
          if (v != null) style = style.copyWith(color: _parseColor(v));
        }
      case 'size':
        {
          final v = node.attrs['value'];
          if (v != null) style = style.copyWith(fontSize: _parseSize(v));
        }
      case 'font':
        {
          final v = node.attrs['value'];
          if (v != null) style = style.copyWith(fontFamily: v);
        }
      case 'backcolor':
      case 'background':
        {
          final v = node.attrs['value'];
          if (v != null)
            style = style.copyWith(background: Paint()..color = _parseColor(v));
        }

      case 'link':
      case 'email':
      case 'qq':
        {
          // Extract URL (same logic as _buildLinkContainer)
          String url;
          switch (node.type) {
            case 'email':
              url = node.attrs['value'] ?? _collectText(node);
              if (!url.startsWith('mailto:')) url = 'mailto:$url';
              break;
            default:
              url = node.attrs['value'] ?? _collectText(node);
          }
          // Apply link default style (blue + underline) on top of inherited style
          final linkStyle = style.copyWith(
            color: const Color(0xFF336699),
            decoration: TextDecoration.underline,
          );
          // Render children with link style
          final children = node.children
              .map((c) => _buildNestedSpan(context, c, linkStyle))
              .toList();
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: () => _handleLinkTap(context, url, node.type),
              child: RichText(
                text: TextSpan(style: linkStyle, children: children),
              ),
            ),
          );
        }

      case 'img':
        {
          final src = node.attrs['value'] ?? '';
          if (src.isNotEmpty) {
            return WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onLongPress: () => showImageActions(
                  context,
                  imageUrls: [src],
                  sourceInfo: '帖子图片',
                ),
                child: CachedNetworkImage(
                  imageUrl: src,
                  width: maxImageWidth * 0.2,
                  placeholder: (_, __) => const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            );
          }
          return TextSpan(text: '[图片]', style: style);
        }

      case 'emoji':
        {
          final name = node.attrs['value'] ?? '';
          final imgUrl = emojiMap?['[$name]'];
          if (imgUrl != null) {
            return WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CachedNetworkImage(
                imageUrl: imgUrl,
                width: 22,
                height: 22,
                errorWidget: (_, __, ___) => Icon(
                  Icons.emoji_emotions_outlined,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ),
            );
          }
          return TextSpan(text: '[$name]', style: style);
        }
    }

    if (node.children.isNotEmpty) {
      final children = <InlineSpan>[];
      for (final child in node.children) {
        children.add(_buildNestedSpan(context, child, style));
      }
      return TextSpan(style: style, children: children);
    }

    if (node.text != null) {
      return TextSpan(text: node.text, style: style);
    }

    return TextSpan(text: '', style: style);
  }

  // ==================== 工具方法 ====================

  String _collectText(AstNode node) {
    final buf = StringBuffer();
    void walk(AstNode n) {
      if (n.text != null) buf.write(n.text);
      for (final c in n.children) walk(c);
    }

    walk(node);
    return buf.toString();
  }

  Color _parseColor(String v) {
    // Named colors
    const named = <String, Color>{
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'brown': Colors.brown,
      'black': Colors.black,
      'white': Colors.white,
      'gray': Colors.grey,
      'grey': Colors.grey,
      'cyan': Colors.cyan,
      'lime': Color(0xFF00FF00),
      'maroon': Color(0xFF800000),
      'olive': Color(0xFF808000),
    };
    return named[v.toLowerCase()] ?? Colors.black;
  }

  double _parseSize(String value) {
    const sizes = [0, 10, 12, 14, 18, 24, 32, 48];
    final idx = int.tryParse(value.trim());
    if (idx != null && idx >= 1 && idx < sizes.length)
      return sizes[idx].toDouble();
    return fontSize;
  }
}

/// 向下传递链接样式的 InheritedWidget
class _LinkStyle extends InheritedWidget {
  final TextStyle style;

  const _LinkStyle({required this.style, required super.child});

  static _LinkStyle? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LinkStyle>();

  @override
  bool updateShouldNotify(_LinkStyle old) => style != old.style;
}

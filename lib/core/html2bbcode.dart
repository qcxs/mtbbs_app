import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;
import 'page_helper.dart';
import 'smilie_map.dart';
import 'url_util.dart';

/// Html2BBCode — 将 Discuz 帖子 HTML 转换为 BBCode 字符串
///
/// 专注于 PC 模板的 Discuz 帖子内容解析。
///
/// [smilieIdMap] 可选，smilieId → insertText 映射。
/// 未传入时自动使用 [SmilieMap.idMap]（由 EmojiService 维护的全局映射）。
class Html2BBCode {
  static final _noRecurseTags = <String>{'code'};
  final List<String> tips = [];
  final Map<String, String>? _customMap;

  Html2BBCode({Map<String, String>? smilieIdMap}) : _customMap = smilieIdMap;

  Map<String, String> get _effectiveMap => _customMap ?? SmilieMap.idMap;

  void _reset() => tips.clear();

  String convert(String html) {
    _reset();
    final doc = htmlParser.parse(html);
    final body = doc.body;
    if (body == null) return '';
    final result = _parseNode(body);
    return _format(result);
  }

  String convertElement(dom.Element el) {
    _reset();
    final result = _parseNode(el);
    return _format(result);
  }

  /// 同 [convertElement]，但只处理 [el] 的子节点，不匹配 [el] 自身的标签。
  /// 用于处理布局容器（如 `<td class="t_f">`）内的内容，避免输出 [td] 等布局标签。
  String convertElementContent(dom.Element el) {
    _reset();
    final result = el.nodes.map((c) => _parseNode(c)).join();
    return _format(result);
  }

  String _parseNode(dom.Node node) {
    if (node.nodeType == dom.Node.TEXT_NODE) return node.text ?? '';
    if (node.nodeType != dom.Node.ELEMENT_NODE) return '';
    final el = node as dom.Element;
    final classResult = _matchByClass(el);
    if (classResult != null) return classResult;
    final complexResult = _matchByOthers(el);
    if (complexResult != null) return complexResult;
    final tagResult = _matchByTagAndAttr(el);
    if (tagResult != null) return tagResult;
    return _parseChildren(el);
  }

  String _parseChildren(dom.Element el) {
    final tag = el.localName ?? '';
    if (_noRecurseTags.contains(tag)) {
      return el.text.trim();
    }
    return el.nodes.map((c) => _parseNode(c)).join();
  }

  String _format(String text) {
    return text
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  // ==================== class 匹配 ====================

  String? _matchByClass(dom.Element el) {
    final cls = el.className;
    // 忽略区域
    if (cls.contains('f_a')) return '';
    // 编辑记录：pstatus
    if (cls.contains('pstatus')) {
      final match = RegExp(
        r'本帖最后由\s*(.+?)\s*于\s*([\d\-:\s]+)\s*编辑',
      ).firstMatch(el.text.trim());
      if (match != null)
        return '\n作者: ${match.group(1)!.trim()}，修改时间：${match.group(2)!.trim()}\n';
      return '';
    }

    // PC 模板引用：.quote > blockquote → [quote]
    if (cls == 'quote') {
      final bq = el.querySelector('blockquote');
      if (bq != null) return '\n[quote]${_parseChildren(bq)}[/quote]\n';
      return '\n[quote]${_parseChildren(el)}[/quote]\n';
    }
    // PC 模板代码块：.blockcode → [code]
    if (cls == 'blockcode') {
      final codeText = el.text.trim();
      final clean = codeText.replaceAll(RegExp(r'复制代码\s*$'), '').trim();
      return '\n[code]$clean[/code]\n';
    }
    return null;
  }

  // ==================== 复杂匹配 ====================

  /// 占位图列表
  static const _placeholders = [
    'none.png',
    'nophoto.gif',
    'nophoto.png',
    'loading.gif',
    'loading.png',
  ];

  /// 解析图片真实 URL
  ///
  /// 优先级：PC 模板 `file`/`zoomfile` → `src`（跳过占位图）
  String _resolveImageSrc(dom.Element img) {
    // PC 模板：zoom 类图片，file 属性为真实 URL
    if (img.className.contains('zoom')) {
      final file = (img.attributes['file'] ?? '').trim();
      if (file.isNotEmpty && !_isPlaceholder(file)) return file;
      final zoomfile = (img.attributes['zoomfile'] ?? '').trim();
      if (zoomfile.isNotEmpty && !_isPlaceholder(zoomfile)) return zoomfile;
    }
    // 兜底：src
    final src = (img.attributes['src'] ?? '').trim();
    if (src.isNotEmpty && !_isPlaceholder(src)) return src;
    return '';
  }

  bool _isPlaceholder(String url) {
    final lower = url.toLowerCase();
    return _placeholders.any((p) => lower.contains(p));
  }

  /// 处理 ignore_js_op 包装器内的各类内容
  String? _handleIgnoreJsOp(dom.Element el) {
    // 1. 图片附件：<img class="zoom" aid="...">
    //    既有真实图片 URL，也有附件元数据（文件名、大小等）
    final zoomImg = el.querySelector('img.zoom[aid]');
    if (zoomImg != null) {
      final src = _resolveImageSrc(zoomImg);
      if (src.isNotEmpty) {
        final url = normalizeUrl(src);
        if (url.isNotEmpty) {
          // 提取元数据：文件名、大小、下载数、上传时间
          String name = '', size = '', downloads = '', uploadTime = '';
          final tip = el.querySelector('.aimg_tip');
          if (tip != null) {
            final strong = tip.querySelector('strong');
            if (strong != null) name = sanitizeText(strong.text);
            final em = tip.querySelector('em.xg1');
            if (em != null) {
              final et = sanitizeText(em.text);
              final sm = RegExp(r'\(([^,]+)').firstMatch(et);
              if (sm != null) size = sm.group(1)!.trim();
              final dm = RegExp(r'下载次数[：:]\s*(\d+)').firstMatch(et);
              if (dm != null) downloads = dm.group(1)!;
            }
            final timeEl = tip.querySelector('p.xg1.y');
            if (timeEl != null) {
              uploadTime = sanitizeText(
                timeEl.text,
              ).replaceAll(RegExp(r'上传\s*$'), '').trim();
            }
          }
          // 兜底：从 attach 链接提取文件名
          if (name.isEmpty) {
            final link = el.querySelector('a[href*="mod=attachment"]');
            if (link != null) name = sanitizeText(link.text);
          }
          if (name.isEmpty) name = '图片';

          final w = zoomImg.attributes['width'];
          final h = zoomImg.attributes['height'];
          final aid = zoomImg.attributes['aid'] ?? '';

          final data = jsonEncode({
            'type': 'image_attach',
            'url': url,
            // ignore: use_null_aware_elements
            if (w != null) 'width': w,
            // ignore: use_null_aware_elements
            if (h != null) 'height': h,
            'aid': aid,
            'name': name,
            if (size.isNotEmpty) 'size': size,
            if (downloads.isNotEmpty) 'downloads': downloads,
            if (uploadTime.isNotEmpty) 'uploadTime': uploadTime,
          });
          return '\n[appdata]$data[/appdata]\n';
        }
      }
    }

    // 2. 普通附件检测
    // <img src="...filetype/xxx.gif"> <span id="attach_N">
    //   <a href="...aid=XXX">name.ext</a>
    //   <em class="xg1">(size, 下载次数: N)</em>
    // </span>
    final attachLink = el.querySelector('a[href*="mod=attachment"]');
    if (attachLink != null) {
      final href = attachLink.attributes['href'] ?? '';
      final aidMatch = RegExp(r'aid=([^&]+)').firstMatch(href);
      final name = sanitizeText(attachLink.text);
      final em = el.querySelector('em.xg1');
      final emText = em != null ? sanitizeText(em.text) : '';
      final sizeMatch = RegExp(r'\(([^,]+)').firstMatch(emText);
      final size = sizeMatch?.group(1)?.trim() ?? '';
      final dlMatch = RegExp(r'下载次数[：:]\s*(\d+)').firstMatch(emText);
      final downloads = dlMatch?.group(1) ?? '';

      final data = jsonEncode({
        'type': 'attach',
        'aid': aidMatch?.group(1) ?? '',
        'name': name,
        if (size.isNotEmpty) 'size': size,
        'url': normalizeUrl(href),
        if (downloads.isNotEmpty) 'downloads': downloads,
      });
      return '\n[appdata]$data[/appdata]\n';
    }

    // ---- 非附件内容：由子节点处理器处理（script → detectPlayer / flv_ 等）----
    return null;
  }

  String? _matchByOthers(dom.Element el) {
    final cls = el.className;

    // PC 模板隐藏内容：comiis_p10 bg_e f14（登录提示）
    if (cls.contains('comiis_p10 bg_e f14')) {
      if (el.querySelector('h3.f_c') != null &&
          el.querySelector('a[href*="action=login"]') != null)
        return '\n[color=#999][size=2]需要登录查看，点击上方「登录」按钮[/size][/color]\n';
    }
    return null;
  }

  // ==================== 标签属性匹配 ====================

  String? _matchByTagAndAttr(dom.Element el) {
    final tag = el.localName ?? '';
    final cls = el.className;

    if (tag == 'script') {
      final sc = el.text;
      // Bilibili 视频嵌入
      if (sc.contains('flv_') && sc.contains('player.bilibili.com')) {
        final idx = sc.indexOf('bvid=');
        if (idx >= 0) {
          final after = sc.substring(idx + 5);
          final end = after.indexOf(RegExp("[&'\" ]"));
          if (end > 0)
            return '[media=x,500,375]https://b23.tv/BV${after.substring(0, end)}[/media]';
        }
      }
      // 音频嵌入（detectPlayer）
      if (sc.contains('detectPlayer')) {
        final audioMatch = RegExp(
          "detectPlayer\\([^,]+,[^,]+,\\s*[\"']([^\"']+)[\"']",
        ).firstMatch(sc);
        if (audioMatch != null) return '[audio]${audioMatch.group(1)}[/audio]';
      }
      // Flash 嵌入（AC_FL_RunContent）
      if (sc.contains('AC_FL_RunContent')) {
        final urlMatch = RegExp(r"encodeURI\('([^']*)'\)").firstMatch(sc);
        if (urlMatch != null) {
          final url = urlMatch.group(1)!;
          if (url.isNotEmpty) {
            return '[media]$url[/media]';
          }
        }
        return '';
      }
      return '';
    }

    // PC 模板媒体嵌入容器
    if (cls.contains('media')) return '';
    // 提示区域
    if (cls.contains('tip')) return '';

    // PC 模板：ignore_js_op 包装器
    if (tag == 'ignore_js_op') {
      final handled = _handleIgnoreJsOp(el);
      if (handled != null) return handled;
      // 回退：处理子节点（script → media/audio, span → bilibili 等）
      return _parseChildren(el);
    }

    // 文本样式
    if (tag == 'strong' || tag == 'b') return '[b]${_parseChildren(el)}[/b]';
    if (tag == 'i') return '[i]${_parseChildren(el)}[/i]';
    if (tag == 'u') return '[u]${_parseChildren(el)}[/u]';
    if (tag == 'strike') return '[s]${_parseChildren(el)}[/s]';

    // 链接
    if (tag == 'a') {
      final href = el.attributes['href'] ?? '';
      final content = _parseChildren(el);
      final text = el.text.trim();
      if (text.startsWith('@')) return '$text ';
      if (href.startsWith('mailto:'))
        return '[email=${href.replaceFirst('mailto:', '')}]$content[/email]';
      if (href.contains('wpa.qq.com')) {
        final qqMatch = RegExp(r'uin=(\d+)').firstMatch(href);
        return qqMatch != null ? '[qq]${qqMatch.group(1)}[/qq]' : '';
      }
      if (href.startsWith('javascript:')) return content;
      return '[url=$href]$content[/url]';
    }

    // 字体
    if (tag == 'font') {
      var res = _parseChildren(el);
      final color = el.attributes['color'];
      final size = el.attributes['size'];
      final face = el.attributes['face'];
      final styleAttr = el.attributes['style'] ?? '';
      final bgMatch = RegExp(
        r'background-color:\s*([^;]+)',
      ).firstMatch(styleAttr);
      final bg = bgMatch?.group(1);
      if (color != null) res = '[color=$color]$res[/color]';
      if (size != null) res = '[size=$size]$res[/size]';
      if (face != null) res = '[font=$face]$res[/font]';
      if (bg != null && bg.isNotEmpty)
        res = '[background=$bg]$res[/background]';
      return res;
    }

    // 对齐
    if (tag == 'div' && el.attributes.containsKey('align')) {
      return '[align=${el.attributes['align']}]${_parseChildren(el)}[/align]';
    }

    // 列表
    if (tag == 'ul') {
      final type = el.attributes['type'] ?? '';
      final cn = el.className;
      String listType = '';
      if (cn.contains('litype_1'))
        listType = '1';
      else if (cn.contains('litype_2'))
        listType = 'a';
      else if (type.isNotEmpty)
        listType = type;
      var li = '';
      for (final child in el.children) {
        if (child.localName == 'li') li += '[*]${_parseChildren(child)}\n';
      }
      return listType.isNotEmpty
          ? '[list=$listType]\n$li[/list]'
          : '[list]\n$li[/list]';
    }

    // 图片
    if (tag == 'img') {
      // 表情：通过 smilieid 匹配
      final smilieId = el.attributes['smilieid'];
      if (smilieId != null && smilieId.isNotEmpty) {
        final entry = _effectiveMap[smilieId];
        if (entry != null) return entry;
        return '';
      }
      // 普通图片
      final imgSrc = _resolveImageSrc(el);
      if (imgSrc.isEmpty) return '';
      final src = normalizeUrl(imgSrc);
      if (src.isEmpty) return '';
      final w = el.attributes['width'];
      final h = el.attributes['height'];
      if (w != null && h != null) return '[img=$w,$h]$src[/img]';
      return '[img]$src[/img]';
    }

    // 水平线
    if (tag == 'hr') return '[hr]';
    // 表格
    if (tag == 'table') return '[table]${_parseChildren(el)}[/table]';
    if (tag == 'tr') return '[tr]${_parseChildren(el)}[/tr]';
    if (tag == 'td' || tag == 'th') {
      return '[$tag]${_parseChildren(el)}[/$tag]';
    }
    if (tag == 'tbody') return _parseChildren(el);
    // 嵌入对象（跳过）
    if (tag == 'embed' || tag == 'object') return '';
    // 换行
    if (tag == 'br') return '\n';

    return null;
  }

  /// 将各种格式的 URL 统一转换为绝对 URL
  ///
  /// 支持的输入格式：
  ///   https://...       → 原样返回
  ///   //host/path       → https://host/path
  ///   /path             → {baseUrl}/path
  ///   ./path            → {baseUrl}/path（去掉 ./）
  ///   path/file.ext     → {baseUrl}/path/file.ext
  ///   forum.php?query   → {baseUrl}/forum.php?query
}

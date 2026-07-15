import 'package:flutter/material.dart';

/// 支持 BBCode 标签插入/包裹的 TextEditingController
///
/// 设计原则：
/// - 所有操作只包裹，不解包（清除样式请用 [clearStyles]）
/// - 包裹时自动去掉首尾空格
/// - 所有文本修改通过 [controller.value] 完成，由 Flutter 的 UndoHistory 自动跟踪。
class BBCodeController extends TextEditingController {
  BBCodeController({super.text});

  /// 未绑定到内容但活跃的图片 AID
  Set<String> pendingAids = {};

  // ==================== 通用包裹 ====================

  /// 包裹选中文本（有选中时）
  ///
  /// 返回 true 表示有选中并已包裹；false 表示无选中。
  /// 包裹前自动 trim 首尾空格。
  bool wrapSelection(String openTag, String closeTag) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;

    final txt = text;
    final selected = txt.substring(sel.start, sel.end);
    final trimmed = selected.trim();
    if (trimmed.isEmpty) return false;

    final trimStart = selected.indexOf(trimmed);
    final trimEnd = trimStart + trimmed.length;
    _replaceAndSelect(
      sel.start + trimStart,
      sel.start + trimEnd,
      '$openTag$trimmed$closeTag',
    );
    return true;
  }

  /// 用内容包裹内联标签（无选中时弹窗后调用）
  void wrapInline(String openTag, String closeTag, String content) {
    if (content.isEmpty) return;
    final sel = selection;
    final txt = text;
    final pos = sel.isValid ? sel.start : txt.length;
    _replaceAndSelect(pos, pos, '$openTag${content.trim()}$closeTag');
  }

  /// 包裹块级标签
  ///
  /// 有选中 → 包裹选中文字
  /// 无选中 → 在光标处插入空标签对
  void wrapBlock(String openTag, String closeTag) {
    final sel = selection;
    final txt = text;

    if (sel.isValid && !sel.isCollapsed) {
      var selected = txt.substring(sel.start, sel.end);
      final trimmed = selected.trim();
      final trimStart = selected.indexOf(trimmed);
      final trimEnd = trimStart + trimmed.length;
      _replaceAndSelect(
        sel.start + trimStart,
        sel.start + trimEnd,
        '$openTag$trimmed$closeTag',
      );
    } else {
      final pos = sel.isValid ? sel.start : txt.length;
      _replaceAndSelect(pos, pos, '$openTag$closeTag');
    }
  }

  /// 包裹带参数标签 [tag=param]text[/tag]
  ///
  /// 有选中 → 包裹选中文字
  /// 无选中 → 在光标处插入空标签对
  void wrapParam(String tagName, String param, String closeTag) {
    final openTag = param.isEmpty ? '[$tagName]' : '[$tagName=$param]';
    wrapBlock(openTag, closeTag);
  }

  // ==================== 清除样式 ====================

  /// 删除选中文字中的所有 BBCode 标签
  ///
  /// 匹配模式：`[xxx]`、`[xxx=yy]`、`[/xxx]`
  void clearStyles() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;

    var selected = text.substring(sel.start, sel.end);
    // 删除所有 [xxx]、[xxx=yy]、[/xxx]
    final cleaned = selected.replaceAllMapped(RegExp(r'\[[^\]]*\]'), (_) => '');
    if (cleaned == selected) return;
    _replaceAndSelect(sel.start, sel.end, cleaned);
  }

  // ==================== 链接 ====================

  /// 插入/包裹链接
  ///
  /// 有选中时：
  ///   - 选中文本是 URL（含 http/https） → `[url]text[/url]`
  ///   - 选中文本不是 URL → `[url=]text[/url]`（URL 留空用户填写）
  /// 无选中时：在光标处插入 `[url=]text[/url]`
  void insertLink(String url, {String? text}) {
    if (url.isEmpty) return;
    final sel = selection;
    final txt = this.text;

    String openTag;
    String content;

    if (text != null && text.isNotEmpty) {
      if (sel.isValid && !sel.isCollapsed) {
        var selected = txt.substring(sel.start, sel.end);
        final trimmed = selected.trim();
        final isUrl =
            trimmed.startsWith('http://') || trimmed.startsWith('https://');
        if (isUrl) {
          // 选中是 URL → [url]URL[/url]
          _replaceAndSelect(sel.start, sel.end, '[url]$trimmed[/url]');
        } else {
          // 选中是文字 → [url=URL]文字[/url]
          _replaceAndSelect(sel.start, sel.end, '[url=$url]$trimmed[/url]');
        }
        return;
      }
      final pos = sel.isValid ? sel.start : txt.length;
      _replaceAndSelect(pos, pos, '[url=$url]$text[/url]');
    } else {
      // 无显示文字
      openTag = '[url=$url]';
      content = '';
      final pos = sel.isValid ? sel.start : txt.length;
      _replaceAndSelect(pos, pos, '$openTag$content[/url]');
    }
  }

  // ==================== 图片 ====================

  /// 插入图片 [img]url[/img]
  void insertImage(String url) {
    if (url.isEmpty) return;
    final sel = selection;
    final pos = sel.isValid ? sel.start : text.length;
    _replaceAndSelect(pos, pos, '[img]$url[/img]');
  }

  // ==================== 自闭合标签 ====================

  /// 插入自闭合块标签 [hr]，始终插在新行
  void insertBlockTag(String tag) {
    final sel = selection;
    final pos = sel.isValid ? sel.start : text.length;
    final txt = text;
    final prefix =
        (pos > 0 && txt[pos - 1] != '\n') || (pos == 0 && txt.isNotEmpty)
        ? '\n'
        : '';
    _replaceAndSelect(pos, pos, '$prefix$tag\n');
  }

  // ==================== 选择标签 ====================

  /// 选中光标所在位置最近的 BBCode 标签对（含标签本身）
  void selectTag() {
    final sel = selection;
    if (!sel.isValid) return;
    final txt = text;
    final cursor = sel.start;

    const selfClosing = {'hr', 'img', 'br'};

    int openPos = -1;
    String tagName = '';

    for (int i = cursor - 1; i >= 0; i--) {
      if (txt[i] == '[') {
        if (i + 1 >= txt.length) continue;
        if (txt[i + 1] == '/') continue;

        int j = i + 1;
        while (j < txt.length &&
            txt[j] != ']' &&
            txt[j] != '=' &&
            txt[j] != ' ') {
          j++;
        }
        final name = txt.substring(i + 1, j);
        if (selfClosing.contains(name)) continue;

        openPos = i;
        tagName = name;
        break;
      }
    }

    if (openPos == -1 || tagName.isEmpty) return;

    final closeTag = '[/$tagName]';
    final openPrefix = '[$tagName';
    int depth = 1;
    int searchPos = openPos + 1;

    while (depth > 0 && searchPos < txt.length) {
      final nextOpen = txt.indexOf(openPrefix, searchPos);
      final nextClose = txt.indexOf(closeTag, searchPos);

      if (nextClose == -1) return;

      if (nextOpen != -1 && nextOpen < nextClose) {
        final afterName = nextOpen + 1 + tagName.length;
        if (afterName < txt.length) {
          final c = txt[afterName];
          if (c == ']' || c == '=' || c == ' ') {
            depth++;
            searchPos = nextOpen + 1;
            continue;
          }
        }
        searchPos = nextOpen + 1;
        continue;
      }

      depth--;
      if (depth == 0) {
        final end = nextClose + closeTag.length;
        selection = TextSelection(baseOffset: openPos, extentOffset: end);
        return;
      }
      searchPos = nextClose + closeTag.length;
    }
  }

  // ==================== 内部方法 ====================

  void _replaceAndSelect(int start, int end, String replacement) {
    final newText = text.replaceRange(start, end, replacement);
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }
}

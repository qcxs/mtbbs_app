import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:mtbbs/core/parser/bbcode2html.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_code_block.dart';
import 'package:provider/provider.dart';

/// BBCode [table] 表格解析结果
class _BbcodeTableData {
  final List<List<String>> rows; // rows → cells → raw BBCode
  _BbcodeTableData(this.rows);
}

/// 解析 BBCode [table]...[/table] 字符串
///
/// 使用栈式匹配（[outerBlocks]）解析最外层 tr/td，天然支持
/// table 套 table（嵌套表格）、td 内嵌 table 等场景，不会被
/// 内层 [/td]/[/tr] 截断。
_BbcodeTableData _parseTableBbcode(String bbcode) {
  final rows = <List<String>>[];
  // bbcode 是含 [table]...[/table] 标签的完整块
  final content = bbcode.substring(7, bbcode.length - 8); // 去 [table]/[/table]
  for (final tr in outerBlocks(content, 'tr')) {
    final trBlock = content.substring(tr.start, tr.end);
    final trInner = trBlock.substring(4, trBlock.length - 5); // 去 [tr]/[/tr]
    final cells = <String>[];
    for (final td in outerBlocks(trInner, 'td')) {
      final tdBlock = trInner.substring(td.start, td.end);
      // 去 [td]/[/td]，cell 内容保留原始 BBCode（含嵌套 [table]）
      cells.add(tdBlock.substring(4, tdBlock.length - 5));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return _BbcodeTableData(rows);
}

/// 将 BBCode 字符串按 [table] 分割为片段
///
/// 返回 (isTable, content) 列表，isTable=true 表示 content 是 [table]...[/table] 原文。
///
/// - 跳过位于 [hide]/[free]/[quote] 容器内部的 [table]：拆分会把容器
///   开/闭标签分到不同片段（如 `[hide][table]...[/table][/hide]`），
///   导致容器标签配对失败而原样显示，容器内的 table 交由 BBCode2Html 处理
/// - 用栈式匹配切分嵌套表格（table 套 table），保证按最外层配对
List<({bool isTable, String content})> splitByTable(String bbcode) {
  final segments = <({bool isTable, String content})>[];
  // 联合扫描：容器标签 + table 标签
  final combined = RegExp(
    r'\[(?:hide|free|quote)(?:=[^\]]*)?\]|\[/(?:hide|free|quote)\]|\[table\]|\[/table\]',
    caseSensitive: false,
  );
  var containerDepth = 0;
  var tableDepth = 0;
  var tableStart = -1;
  var lastEnd = 0;
  for (final match in combined.allMatches(bbcode)) {
    final token = match.group(0)!.toLowerCase();
    if (token.startsWith('[/')) {
      if (token == '[/table]') {
        if (containerDepth == 0 && tableDepth > 0) {
          tableDepth--;
          if (tableDepth == 0) {
            if (tableStart > lastEnd) {
              segments.add((
                isTable: false,
                content: bbcode.substring(lastEnd, tableStart),
              ));
            }
            segments.add((
              isTable: true,
              content: bbcode.substring(tableStart, match.end),
            ));
            lastEnd = match.end;
          }
        }
      } else if (containerDepth > 0) {
        containerDepth--;
      }
    } else {
      if (token == '[table]') {
        if (containerDepth == 0) {
          if (tableDepth == 0) tableStart = match.start;
          tableDepth++;
        }
      } else {
        containerDepth++;
      }
    }
  }
  if (lastEnd < bbcode.length) {
    segments.add((isTable: false, content: bbcode.substring(lastEnd)));
  }
  return segments;
}

/// BBCode 表格渲染组件
///
/// 将 [table] BBCode 解析后使用 Flutter 原生 [Table] widget 渲染，
/// 避免 flutter_html 表格扩展的内联宽度问题。
class BbcodeTableWidget extends StatelessWidget {
  final String bbcode; // 含 [table]...[/table] 标签的完整片段
  final double fontSize;
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const BbcodeTableWidget({
    super.key,
    required this.bbcode,
    this.fontSize = 16,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Widget build(BuildContext context) {
    // 解析使用 settings 中的标签禁用配置
    final settings = context.watch<SettingsProvider>();
    final effectiveDisabled = disabledTags ?? settings.disabledBbcodeTags;
    final converter = BBCode2Html(
      // 表情数据由 EmojiService 按站点维护且几乎不变，渲染层直接获取
      emojiMap: EmojiService().map,
      smilieIdMap: EmojiService().smilieIdMap,
      disabledTags: effectiveDisabled,
      baseUrl: null,
      autoDetectUrls: autoDetectUrls,
      // cell 内 code/table 还原为占位元素，由下方 extension 渲染
      emitCodePlaceholder: true,
      emitTablePlaceholder: true,
    );

    final data = _parseTableBbcode(bbcode);
    if (data.rows.isEmpty) return const SizedBox.shrink();

    // 计算最大列数
    final maxCols = data.rows
        .map((r) => r.length)
        .reduce((a, b) => a > b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(color: const Color(0xFFD0D7DE), width: 1),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: data.rows.map((row) {
          return TableRow(
            children: List.generate(maxCols, (colIdx) {
              final cellBbcode = colIdx < row.length ? row[colIdx] : '';
              final cellHtml = cellBbcode.isNotEmpty
                  ? converter.convert(cellBbcode)
                  : '';
              return Container(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(maxWidth: 350),
                child: cellHtml.isNotEmpty
                    ? Html(
                        data: cellHtml,
                        style: {
                          'body': Style(
                            fontSize: FontSize(fontSize),
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                          ),
                        },
                        extensions: [
                          BbcodeCodeExtension(
                            codeBlocks: converter.codeBlocks,
                            fontSize: fontSize,
                          ),
                          BbcodeTableExtension(
                            tableBlocks: converter.tableBlocks,
                            fontSize: fontSize,
                            disabledTags: effectiveDisabled,
                            autoDetectUrls: autoDetectUrls,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              );
            }),
          );
        }).toList(),
      ),
    );
  }
}

/// flutter_html extension：把 [table] 占位元素原地替换为 [BbcodeTableWidget]
///
/// BBCode2Html 在 [BBCode2Html.emitTablePlaceholder] 模式下将 [table] 块还原为
/// `<div class="bbcode-table" data-table-index="N"></div>`。flutter_html 核心
/// 不支持 `<table>` 渲染，此处按 data-table-index 取出原始 table BBCode，
/// 原地替换为 [BbcodeTableWidget]（Flutter 原生 Table，支持横向滚动）。
/// 容器内（hide/quote）与嵌套表格（cell 内）因此都能正确渲染。
class BbcodeTableExtension extends HtmlExtension {
  final List<String> tableBlocks;
  final double fontSize;
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const BbcodeTableExtension({
    required this.tableBlocks,
    required this.fontSize,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Set<String> get supportedTags => const {'div'};

  @override
  bool matches(ExtensionContext context) {
    return context.element?.attributes.containsKey('data-table-index') ?? false;
  }

  @override
  InlineSpan build(ExtensionContext context) {
    final index = int.tryParse(
      context.element?.attributes['data-table-index'] ?? '',
    );
    final bbcode = (index != null && index >= 0 && index < tableBlocks.length)
        ? tableBlocks[index]
        : '';
    return WidgetSpan(
      child: BbcodeTableWidget(
        bbcode: bbcode,
        fontSize: fontSize,
        disabledTags: disabledTags,
        autoDetectUrls: autoDetectUrls,
      ),
    );
  }
}

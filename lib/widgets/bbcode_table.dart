import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../core/bbcode2html.dart';
import '../core/emoji_loader.dart';
import '../providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// BBCode [table] 表格解析结果
class _BbcodeTableData {
  final List<List<String>> rows; // rows → cells → raw BBCode
  _BbcodeTableData(this.rows);
}

/// 解析 BBCode [table]...[/table] 字符串
_BbcodeTableData _parseTableBbcode(String bbcode) {
  final rows = <List<String>>[];
  final trRegex = RegExp(r'\[tr\]([\s\S]*?)\[/tr\]', caseSensitive: false);
  for (final trMatch in trRegex.allMatches(bbcode)) {
    final trContent = trMatch.group(1)!;
    final cells = <String>[];
    final tdRegex = RegExp(r'\[td\]([\s\S]*?)\[/td\]', caseSensitive: false);
    for (final tdMatch in tdRegex.allMatches(trContent)) {
      cells.add(tdMatch.group(1)!);
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return _BbcodeTableData(rows);
}

/// 将 BBCode 字符串按 [table] 分割为片段
///
/// 返回 (isTable, content) 列表，isTable=true 表示 content 是 [table]...[/table] 原文
List<({bool isTable, String content})> splitByTable(String bbcode) {
  final segments = <({bool isTable, String content})>[];
  final regex = RegExp(r'\[table\]([\s\S]*?)\[/table\]', caseSensitive: false);
  int lastEnd = 0;
  for (final match in regex.allMatches(bbcode)) {
    // 表格前的普通 BBCode
    if (match.start > lastEnd) {
      segments.add((isTable: false, content: bbcode.substring(lastEnd, match.start)));
    }
    // 表格 BBCode（含 [table] 标签本身）
    segments.add((isTable: true, content: bbcode.substring(match.start, match.end)));
    lastEnd = match.end;
  }
  // 剩余普通 BBCode
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
  final Map<String, String>? emojiMap;
  final Map<String, String>? smilieIdMap;
  final Set<String>? disabledTags;
  final bool autoDetectUrls;

  const BbcodeTableWidget({
    super.key,
    required this.bbcode,
    this.fontSize = 16,
    this.emojiMap,
    this.smilieIdMap,
    this.disabledTags,
    this.autoDetectUrls = true,
  });

  @override
  Widget build(BuildContext context) {
    // 解析使用 settings 中的标签禁用配置
    final settings = context.watch<SettingsProvider>();
    final effectiveDisabled = disabledTags ?? settings.disabledBbcodeTags;
    final converter = BBCode2Html(
      emojiMap: emojiMap,
      smilieIdMap: smilieIdMap ?? EmojiService().smilieIdMap,
      disabledTags: effectiveDisabled,
      baseUrl: null,
      autoDetectUrls: autoDetectUrls,
    );

    final data = _parseTableBbcode(bbcode);
    if (data.rows.isEmpty) return const SizedBox.shrink();

    // 计算最大列数
    final maxCols = data.rows.map((r) => r.length).reduce(
      (a, b) => a > b ? a : b,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: TableBorder.all(
          color: const Color(0xFFD0D7DE),
          width: 1,
        ),
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
                        extensions: const [],
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

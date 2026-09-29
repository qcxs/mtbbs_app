import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/forum/guide/export.dart' as guide_api;
import 'package:mtbbs/api/forum/viewthread/detail/export.dart' as thread_api;
import 'package:mtbbs/core/parser/bbcode_blocks.dart';
import 'package:mtbbs/services/api_service.dart';

import 'api_bootstrap.dart';

/// BBCode 顶层分块器 —— 真实数据体检探针（需要网络）。
///
/// 用途：`lib/core/parser/bbcode_blocks.dart` 是分块可视化编辑器的地基，
/// 它的「块级标签集合」必须覆盖真实正文里出现的构造。每当该集合变更、
/// 或论坛出现新的内容形态时，跑一遍这个探针即可确认：
///   1. 无损不变量 `join(raw) == 原文` 是否仍然成立（含畸形输入）
///   2. 有没有块级标签被漏掉（表现：文本块里残留块级开/闭标签）
///   3. 开标签数是否与块数一一对应（既没切多也没切少）
///   4. 各标签的真实上下文（人工核对切分是否合理）
///
/// 用法：
/// ```powershell
/// flutter test tool/bbcode_blocks_report_test.dart
/// flutter test tool/bbcode_blocks_report_test.dart --dart-define=limit=40
/// flutter test tool/bbcode_blocks_report_test.dart --dart-define=tids=173313,170313
/// ```
/// 取样默认走导读（最新帖 + 精华帖），游客态即可，不需要登录。
void main() {
  test('bbcode 分块体检报告', () async {
    const tidsEnv = String.fromEnvironment('tids', defaultValue: '');
    const account = String.fromEnvironment('account', defaultValue: '');
    final limit =
        int.tryParse(const String.fromEnvironment('limit', defaultValue: '')) ??
        8;
    final pages =
        int.tryParse(const String.fromEnvironment('pages', defaultValue: '')) ??
        1;

    await bootstrap(account: account);
    final dio = ApiService().dio;

    final cased = <({String where, String bbcode})>[];
    final tids = <String>[];

    if (tidsEnv.isNotEmpty) {
      tids.addAll(
        tidsEnv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    } else {
      // 逛导读取样：最新帖 + 精华帖，尽量覆盖不同长度的正文
      for (final view in ['newthread', 'digest']) {
        try {
          final list = await guide_api.getThreadList(dio, view: view, page: 1);
          for (final t in (list['threads'] as List? ?? const [])) {
            final tid = _extractTid(t);
            if (tid.isNotEmpty) tids.add(tid);
          }
        } catch (e) {
          print('取样失败 view=$view: $e');
        }
      }
    }

    final picked = tids.toSet().take(limit).toList();
    print('取样帖子: ${picked.length} 篇 → $picked');

    var floors = 0;
    for (final tid in picked) {
      for (var page = 1; page <= pages; page++) {
        try {
          final r = await thread_api.getThreadDetail(dio, tid: tid, page: page);
          if (r['success'] != true) {
            if (page == 1) {
              print('  tid=$tid 取详情失败: ${r['message']}');
            }
            break;
          }
          final main = r['mainPost'] as Map<String, dynamic>?;
          if (main != null) {
            floors++;
            cased.add((
              where: 'tid=$tid 楼主',
              bbcode: '${main['bbcode'] ?? ''}',
            ));
          }
          for (final p in (r['posts'] as List? ?? const [])) {
            final m = p as Map<String, dynamic>;
            floors++;
            cased.add((
              where: 'tid=$tid p$page 楼${m['floor']}',
              bbcode: '${m['bbcode'] ?? ''}',
            ));
          }
          if (page >= (r['totalPages'] as int? ?? 1)) break;
        } catch (e) {
          print('  tid=$tid p$page 异常: $e');
          break;
        }
      }
    }

    print('采集楼层数: $floors');
    _report(cased);
  });
}

void _report(List<({String where, String bbcode})> cased) {
  const blockCloseTags = [
    'quote',
    'free',
    'hide',
    'code',
    'list',
    'table',
    'align',
    'img',
    'attachimg',
    'attach',
    'audio',
    'media',
    'flash',
    'video',
    'appdata',
  ];

  var losslessOk = 0;
  final kindCount = <BbBlockKind, int>{};
  final structuralShapes = <String>[];
  final stranded = <String>[];
  final noBlock = <int>[];
  final tagCount = <String, int>{};
  final tagRe = RegExp(r'\[(/)?([a-zA-Z*]+)(?:=[^\]]*)?\]');

  for (final s in cased) {
    final blocks = splitBbcodeBlocks(s.bbcode);
    if (blocks.map((b) => b.raw).join() != s.bbcode) {
      print('!! 无损失败 ${s.where}');
      continue;
    }
    losslessOk++;

    final visible = blocks.where((b) => b.body.isNotEmpty).toList();
    for (final b in visible) {
      kindCount[b.kind] = (kindCount[b.kind] ?? 0) + 1;
    }
    final structural = visible.where((b) => !b.isText).length;
    if (structural == 0) {
      noBlock.add(s.bbcode.length);
    } else {
      structuralShapes.add(
        '${s.where} (${s.bbcode.length}字): '
        '${visible.map((b) => b.kind.name).join(' / ')}',
      );
    }

    for (final b in blocks.where((b) => b.isText)) {
      for (final t in blockCloseTags) {
        if (b.body.contains('[/$t]')) stranded.add('${s.where} → 文本块残留 [/$t]');
      }
    }

    for (final m in tagRe.allMatches(s.bbcode)) {
      if (m.group(1) == '/') continue;
      final t = m.group(2)!.toLowerCase();
      tagCount[t] = (tagCount[t] ?? 0) + 1;
      _collectSample(t, s.bbcode, m.start, m.end);
    }
  }

  print('');
  print('=== 1. 无损不变量 ===');
  print('通过 $losslessOk / ${cased.length}');

  print('');
  print('=== 2. 块类型分布 ===');
  print(kindCount);

  print('');
  print('=== 3. 含块级结构的楼层形态 ===');
  if (structuralShapes.isEmpty) {
    print('（无）');
  } else {
    for (final s in structuralShapes.take(25)) {
      print('  $s');
    }
    if (structuralShapes.length > 25) {
      print('  …还有 ${structuralShapes.length - 25} 条');
    }
  }

  print('');
  print('=== 4. 切漏信号（文本块里残留块级闭合标签）===');
  print(stranded.isEmpty ? '无' : stranded.take(20).join('\n'));

  print('');
  print('=== 5. 纯文本楼层（无块级结构）字长分布 ===');
  if (noBlock.isEmpty) {
    print('（无）');
  } else {
    noBlock.sort();
    print(
      '数量 ${noBlock.length}，字长 '
      'min=${noBlock.first} max=${noBlock.last} '
      '中位=${noBlock[noBlock.length ~/ 2]}',
    );
  }

  print('');
  print('=== 4b. 被撕开的行内容器（文本块以闭合标签开头）===');
  final torn = <String>[];
  for (final s in cased) {
    for (final b in splitBbcodeBlocks(s.bbcode)) {
      if (!b.isText) continue;
      final body = b.body;
      if (body.startsWith('[/')) {
        torn.add('${s.where} → 文本块以 ${body.split(']').first}] 开头');
      }
    }
  }
  print(torn.isEmpty ? '无' : torn.take(20).join('\n'));

  print('');
  print('=== 4c. 文本块内行内标签不平衡（源本身或切分导致）===');
  final unbalanced = <String>[];
  for (final s in cased) {
    for (final b in splitBbcodeBlocks(s.bbcode)) {
      if (!b.isText) continue;
      if (!_inlineBalanced(b.body)) {
        unbalanced.add('${s.where} → ${b.body.replaceAll('\n', '⏎')}');
      }
    }
  }
  print(unbalanced.isEmpty ? '无' : unbalanced.take(10).join('\n'));

  print('');
  print('=== 5b. 文本块里残留的块级开标签（未闭合降级的规模）===');
  final strandedOpen = <String>[];
  final openTagRe = RegExp(
    r'\[(quote|free|hide|code|list|table|align|img|attachimg|attach|appdata'
    r'|audio|flash|media|video|hr)(?:=[^\]]*)?\]',
    caseSensitive: false,
  );
  for (final s in cased) {
    for (final b in splitBbcodeBlocks(s.bbcode)) {
      if (!b.isText) continue;
      final m = openTagRe.firstMatch(b.body);
      if (m != null) {
        strandedOpen.add('${s.where} → 文本块残留 ${m.group(0)}');
      }
    }
  }
  print(strandedOpen.isEmpty ? '无' : strandedOpen.take(20).join('\n'));

  print('');
  print('=== 5c. 含 list/align/code/table 楼层的原文（便于人工核对切分）===');
  final rare = RegExp(
    r'\[(list|align|code|table)(?:=[^\]]*)?\]',
    caseSensitive: false,
  );
  var shown = 0;
  for (final s in cased) {
    if (!rare.hasMatch(s.bbcode) || shown >= 3) continue;
    shown++;
    print('  ${s.where} (${s.bbcode.length}字)');
    for (final b in splitBbcodeBlocks(
      s.bbcode,
    ).where((b) => b.body.isNotEmpty)) {
      final one = b.body.replaceAll('\n', '⏎');
      print(
        '    [${b.kind.name}] '
        '${one.length > 140 ? '${one.substring(0, 140)}…' : one}',
      );
    }
  }
  if (shown == 0) print('（本次样本无）');

  print('');
  print('=== 6. 开标签频次（核对块级集合是否漏项）===');
  final sorted = tagCount.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sorted) {
    final known = _knownSet.contains(e.key) ? '' : '   ← 未知/未归类';
    print('  [${e.key}] × ${e.value}$known');
  }

  print('');
  print('=== 7. 各标签的真实上下文（前 2 处，各 120 字）===');
  for (final e in sorted) {
    final samples = _samples[e.key];
    if (samples == null || samples.isEmpty) continue;
    print('  [${e.key}]');
    for (final s in samples) {
      print('    ${s.replaceAll('\n', '⏎')}');
    }
  }
}

/// 每个标签最多留 2 处上下文
final _samples = <String, List<String>>{};

void _collectSample(String tag, String text, int start, int end) {
  final list = _samples.putIfAbsent(tag, () => []);
  if (list.length >= 2) return;
  final from = (start - 40).clamp(0, text.length);
  final to = (end + 80).clamp(0, text.length);
  list.add(text.substring(from, to));
}

/// 已知标签（块级 + 行内 + 表情/附件等），用于标出未归类项
const _knownSet = <String>{
  // 块级
  'quote', 'free', 'hide', 'code', 'list', 'table', 'align',
  'img', 'attachimg', 'attach', 'audio', 'flash', 'media', 'video', 'hr',
  // 行内
  'b', 'i', 'u', 's', 'color', 'size', 'font', 'backcolor', 'background',
  'url', 'email', 'qq',
  // 结构/其它
  '*', 'appdata',
};

/// 行内标签名（与 bbcode_blocks.dart 的 _inlineTags 对齐）
const _inlineTagNames = <String>{
  'b',
  'i',
  'u',
  's',
  'color',
  'size',
  'font',
  'backcolor',
  'background',
  'url',
  'email',
  'qq',
};

/// 文本块内的行内标签是否成对（用于发现「被切分撕开的容器」）
bool _inlineBalanced(String s) {
  final re = RegExp(r'\[(/)?([a-zA-Z*]+)(?:=[^\]]*)?\]');
  final open = <String>[];
  for (final m in re.allMatches(s)) {
    final t = m.group(2)!.toLowerCase();
    if (!_inlineTagNames.contains(t)) continue;
    if (m.group(1) == '/') {
      open.remove(t);
    } else {
      open.add(t);
    }
  }
  return open.isEmpty;
}

String _extractTid(Object? thread) {
  if (thread is! Map) return '';
  for (final k in ['tid', 'id', 'threadId']) {
    final v = thread[k];
    if (v != null && '$v'.isNotEmpty) return '$v';
  }
  final url = '${thread['url'] ?? thread['threadUrl'] ?? ''}';
  final m = RegExp(r'(?:tid=|thread-)(\d+)').firstMatch(url);
  return m?.group(1) ?? '';
}

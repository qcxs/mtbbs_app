/// 表格宽度策略的开发用出图工具（不参与打包，也不在 `flutter test test/` 里跑）。
///
/// 用四类典型表格（短 2 列 / 描述 2 列 / 规格 3 列 / 宽 6 列）在 380/760/1200
/// 三档可用宽度下渲染，对比不同宽度策略，并把截图写到 `build/table_demo/`：
/// - `auto`     渲染器原生（内容自适应）
/// - `current`  旧的「列数 ≤4 就 100%」写死策略（保留用于对照）
/// - `adaptive` 只按「列数 ×110 ≤ 可用宽度」判断
/// - `smart`    宽度+内容自适应（与 `_stylesFor` 的生产实现一致）
///
/// 运行：`flutter test tool/table_demo_test.dart`
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;

const _border = '1px solid #B0B0B0';
const _pad = '4px 8px';

class Scenario {
  const Scenario(this.title, this.columns, this.html);
  final String title;
  final int columns;
  final String html;
}

const _scenarios = <Scenario>[
  Scenario(
    '1. Short 2-column',
    2,
    '<table>'
        '<tr><td>Status</td><td>OK</td></tr>'
        '<tr><td>Mode</td><td>Auto</td></tr>'
        '</table>',
  ),
  Scenario(
    '2. Descriptive 2-column',
    2,
    '<table>'
        '<tr><th>Module</th><th>Details</th></tr>'
        '<tr><td>navicat.exe</td><td>0x00400000 image base, loaded from '
        'C:/Program Files/PremiumSoft/Navicat</td></tr>'
        '<tr><td>libcc.dll</td><td>0x180000000 image base, CRT runtime</td>'
        '</tr>'
        '</table>',
  ),
  Scenario(
    '3. Spec 3-column (# / component / description)',
    3,
    '<table>'
        '<tr><th>#</th><th>Component</th><th>Description</th></tr>'
        '<tr><td>1</td><td>Loader</td><td>Resolves imports and maps modules '
        'into memory before entry point</td></tr>'
        '<tr><td>2</td><td>Runtime</td><td>Provides heap, strings and thread '
        'primitives for managed code</td></tr>'
        '</table>',
  ),
  Scenario(
    '4. Wide 6-column',
    6,
    '<table>'
        '<tr><th>ID</th><th>Name</th><th>Type</th><th>Size</th>'
        '<th>Flags</th><th>Owner</th></tr>'
        '<tr><td>01</td><td>alpha</td><td>core</td><td>12 KB</td>'
        '<td>R-X</td><td>team</td></tr>'
        '<tr><td>02</td><td>beta</td><td>util</td><td>4 KB</td>'
        '<td>RW-</td><td>team</td></tr>'
        '</table>',
  ),
];

Map<String, String>? Function(dom.Element) stylesFor(
  String variant,
  double available,
  int columns,
) {
  final smartForce = <dom.Element, bool>{};
  bool smartForceFor(dom.Element table) => smartForce[table] ??= () {
    final rows = table
        .querySelectorAll('tr')
        .where((r) => _nearestTable(r) == table);
    var cols = 0;
    final weights = <int, double>{};
    for (final row in rows) {
      var col = 0;
      for (final cell in row.children) {
        if (cell.localName != 'td' && cell.localName != 'th') continue;
        final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
        final w = _weightedLength(cell) / span;
        for (var i = 0; i < span; i++) {
          weights.update(col + i, (v) => v > w ? v : w, ifAbsent: () => w);
        }
        col += span;
      }
      if (col > cols) cols = col;
    }
    if (cols == 0) return false;
    final list = List.generate(cols, (i) => weights[i] ?? 1);
    final estimated = list.fold(0.0, (a, b) => a + b) * 15 + cols * 18 + 2;
    final maxW = list.reduce((a, b) => a > b ? a : b);
    final minW = list.reduce((a, b) => a < b ? a : b);
    final balanced = maxW / (minW < 0.1 ? 0.1 : minW) <= 2.5;
    return estimated <= available * 0.92 && balanced;
  }();
  return (e) {
    if (e.localName == 'table') {
      final force = variant == 'current'
          ? columns <= 4
          : variant == 'adaptive'
          ? columns * 110 <= available
          : variant == 'smart'
          ? smartForceFor(e)
          : false;
      return {
        'border': _border,
        'margin': '0',
        'padding': '0',
        if (force) 'width': '100%',
      };
    }
    if (e.localName == 'td' || e.localName == 'th') {
      return {
        'border': _border,
        'padding': _pad,
        if (e.localName == 'th') 'font-weight': 'bold',
      };
    }
    return null;
  };
}

dom.Element? _nearestTable(dom.Element e) {
  for (var p = e.parent; p != null; p = p.parent) {
    if (p.localName == 'table') return p;
  }
  return null;
}

bool _isWide(int rune) =>
    (rune >= 0x2E80 && rune <= 0x9FFF) ||
    (rune >= 0x3000 && rune <= 0x303F) ||
    (rune >= 0xFF00 && rune <= 0xFFEF);

double _weightedLength(dom.Element e) {
  var v = 0.0;
  for (final r in e.text.runes) {
    v += _isWide(r) ? 1.0 : 0.55;
  }
  return v < 1 ? 1 : v;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final path in [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader('Segoe')
        ..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
      await loader.load();
    }
  });

  for (final variant in ['auto', 'current', 'adaptive', 'smart']) {
    for (final width in [380.0, 760.0, 1200.0]) {
      testWidgets('$variant @ $width', (tester) async {
        final key = GlobalKey();
        tester.view.physicalSize = Size(width, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: Colors.white,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: RepaintBoundary(
                    key: key,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final s in _scenarios) ...[
                            Text(
                              s.title,
                              style: const TextStyle(
                                fontFamily: 'Segoe',
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 6),
                            HtmlWidget(
                              s.html,
                              buildAsync: false,
                              textStyle: const TextStyle(
                                fontFamily: 'Segoe',
                                fontSize: 15,
                                height: 1.5,
                                color: Color(0xDE000000),
                              ),
                              customStylesBuilder: stylesFor(
                                variant,
                                width - 32,
                                s.columns,
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final widths = [
          for (var i = 0; i < _scenarios.length; i++)
            tester
                .getSize(find.byType(HtmlTable).at(i))
                .width
                .toStringAsFixed(1),
        ];
        // ignore: avoid_print
        print('[$variant @ $width] table widths = $widths');

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/table_demo')
            ..createSync(recursive: true);
          File(
            '${dir.path}/${variant}_${width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}

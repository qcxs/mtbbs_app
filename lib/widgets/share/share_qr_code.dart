import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// 分享图用二维码：`qr` 编码 + 自绘模块（白底 + 细边框）。
///
/// 不用 `pretty_qr_code`：它断言「单个模块 ≥ 2px」，64px 的二维码会直接崩
/// （模块密集时也会画糊）。自绘方块不受此限——屏幕预览略密，但 3x 截图放大后仍可扫。
class ShareQrCode extends StatelessWidget {
  final String data;
  final double size;

  const ShareQrCode({super.key, required this.data, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qrImage = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L),
    );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: CustomPaint(painter: _QrPainter(qrImage), size: Size.infinite),
    );
  }
}

/// 把 `QrImage` 的暗模块画成方块（按行合并连续模块，减少相邻缝隙）。
class _QrPainter extends CustomPainter {
  final QrImage qr;

  const _QrPainter(this.qr);

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    if (n <= 0 || size.width <= 0) return;
    final m = size.width / n;
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      var c = 0;
      while (c < n) {
        if (!qr.isDark(r, c)) {
          c++;
          continue;
        }
        var end = c + 1;
        while (end < n && qr.isDark(r, end)) {
          end++;
        }
        canvas.drawRect(Rect.fromLTRB(c * m, r * m, end * m, (r + 1) * m), paint);
        c = end;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.qr != qr;
}

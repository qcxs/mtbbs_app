import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// 剪贴板图片粘贴服务
///
/// 从系统剪贴板检测并提取图片，保存到临时缓存目录。
/// 仅支持 Windows 桌面（通过 PowerShell Get-Clipboard）。
class ClipboardPasteService {
  /// 缓存文件最长保留时间
  static const _maxCacheAge = Duration(hours: 1);

  /// 检测剪贴板是否有图片，有则保存到缓存目录并返回文件
  ///
  /// 返回临时 [File]（调用方负责使用后删除），无图片返回 null。
  static Future<File?> pasteImage() async {
    if (!Platform.isWindows) return null;
    try {
      final cacheDir = Directory('${Directory.systemTemp.path}\\mtbbs_clip');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      final outPath =
          '${cacheDir.path}\\img_${DateTime.now().millisecondsSinceEpoch}.png';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Add-Type -AssemblyName System.Windows.Forms; ' +
            '\$img = [System.Windows.Forms.Clipboard]::GetImage(); ' +
            'if (\$img -ne \$null) { ' +
            '\$img.Save(\'$outPath\', ' +
            '[System.Drawing.Imaging.ImageFormat]::Png); ' +
            'Write-Output "OK" } else { Write-Output "NULL" }',
      ]);

      if (result.exitCode == 0 &&
          result.stdout.toString().trim() == 'OK' &&
          await File(outPath).exists() &&
          await File(outPath).length() > 0) {
        // 异步清理过期缓存
        unawaited(_cleanCache(cacheDir));
        return File(outPath);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 读取剪贴板文本
  static Future<String?> pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  /// 清理过期缓存文件
  static Future<void> _cleanCache(Directory dir) async {
    try {
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > _maxCacheAge) {
            await entity.delete();
          }
        }
      }
    } catch (_) {
      // 静默失败
    }
  }
}

/// 用于标记异步不等待
void unawaited(Future<void> future) => future.ignore();

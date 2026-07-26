import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:mtbbs/core/app/app_paths.dart';

/// 剪贴板图片粘贴服务
///
/// 从系统剪贴板检测并提取图片，保存到临时缓存目录。
/// 仅支持 Windows 桌面（通过 PowerShell）。
///
/// ## 读取优先级（自上而下保留原始格式，避免 Bitmap 重编码）
/// 1. FileDrop（原始文件路径，GIF 动画无损）
/// 2. PNG / GIF / JFIF 原始编码字节
/// 3. GetImage() → Bitmap.Save(Png) 兜底（静态图，会丢失动效和元数据）
class ClipboardPasteService {
  /// 缓存文件最长保留时间
  static const _maxCacheAge = Duration(hours: 1);

  /// 检测剪贴板是否有图片，有则保存到缓存目录并返回文件
  ///
  /// 返回临时 [File]（调用方负责使用后删除），无图片返回 null。
  static Future<File?> pasteImage() async {
    if (!Platform.isWindows) return null;
    try {
      final cacheDir = Directory(await AppPaths.clipboardDir);
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      final basePath = cacheDir.path;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // PowerShell 脚本：
      //   1) FileDrop → 直接复制原始文件（保留 GIF 动画等）
      //   2) 原始编码格式（PNG/GIF/JPEG）→ 写字节
      //   3) GetImage + Save(Png) 兜底
      final script =
          '''
Add-Type -AssemblyName System.Windows.Forms

# --- 1. FileDrop：优先使用原始文件 ---
${_buildFileDropDetection(basePath, timestamp)}

# --- 2. 直接读取原始编码字节 ---
${_buildRawFormatDetection(basePath, timestamp)}

# --- 3. 兜底：GetImage + Save(Png) ---
${_buildFallbackDetection(basePath, timestamp)}
''';

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ]);

      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        if (output.startsWith('OK:')) {
          final filePath = output.substring(3).trim();
          if (filePath.isNotEmpty &&
              await File(filePath).exists() &&
              await File(filePath).length() > 0) {
            unawaited(_cleanCache(cacheDir));
            return File(filePath);
          }
        }
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

// ==================== PowerShell 脚本构建 ====================

/// 1) FileDrop：直接复制原始文件
String _buildFileDropDetection(String basePath, int timestamp) {
  return r'''
$drop = [System.Windows.Forms.Clipboard]::GetFileDropList()
if ($drop -and $drop.Count -gt 0) {
  $src = $drop[0]
  $ext = [System.IO.Path]::GetExtension($src).ToLower()
  $imageExts = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp')
  if ($imageExts -contains $ext) {
    $outPath = "''' +
      '$basePath' +
      r'''\img_''' +
      '$timestamp' +
      r'''_drop$ext"
    Copy-Item -Path $src -Destination $outPath -Force
    Write-Output "OK: $outPath"
    return
  }
}
''';
}

/// 2) 直接读取原始编码字节（PNG / GIF / JFIF）
String _buildRawFormatDetection(String basePath, int timestamp) {
  return r'''
$formats = @('PNG', 'GIF', 'JFIF')
$extMap = @{ 'PNG'='.png'; 'GIF'='.gif'; 'JFIF'='.jpg' }
foreach ($fmt in $formats) {
  if ([System.Windows.Forms.Clipboard]::ContainsData($fmt)) {
    $data = [System.Windows.Forms.Clipboard]::GetData($fmt)
    if ($data -ne $null) {
      $outPath = "''' +
      '$basePath' +
      r'''\img_''' +
      '$timestamp' +
      r'''$($extMap[$fmt])"
      [System.IO.File]::WriteAllBytes($outPath, [byte[]]$data)
      Write-Output "OK: $outPath"
      return
    }
  }
}
''';
}

/// 3) 兜底：GetImage + Save(Png)
String _buildFallbackDetection(String basePath, int timestamp) {
  return r'''
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img -ne $null) {
  $outPath = "''' +
      '$basePath' +
      r'''\img_''' +
      '$timestamp' +
      r'''.png"
  $img.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $img.Dispose()
  Write-Output "OK: $outPath"
  return
}

Write-Output "NULL"
''';
}

/// 用于标记异步不等待
void unawaited(Future<void> future) => future.ignore();

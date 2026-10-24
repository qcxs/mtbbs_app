import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mtbbs/core/app/app_paths.dart';

/// 剪贴板读取结果
///
/// [files] 是资源管理器复制的文件（已复制为缓存副本），[image] 是截图 /
/// 浏览器复制的位图。两者互斥：有文件列表时以文件为准。
class ClipboardPasteData {
  final List<File> files;
  final File? image;

  /// 文件列表里被忽略的条目数（目录 / 已失效路径）
  final int ignored;

  const ClipboardPasteData({
    this.files = const [],
    this.image,
    this.ignored = 0,
  });
}

/// 剪贴板文件 / 图片粘贴服务
///
/// 仅支持 Windows 桌面（通过 PowerShell 读取系统剪贴板）。
///
/// ## 常见剪贴板形态
/// - **资源管理器复制文件**：`CF_HDROP`（`Clipboard.GetFileDropList`），可多选
/// - **截图 / 浏览器复制图片**：原始编码字节（PNG/GIF/JFIF）或 `GetImage()` 位图
/// - **普通文本**：由调用方用 Flutter `Clipboard` 读取
///
/// ## 读取优先级（自上而下保留原始格式，避免 Bitmap 重编码）
/// 1. 文件列表（原始文件，GIF 动画无损）
/// 2. PNG / GIF / JFIF 原始编码字节
/// 3. GetImage() → Bitmap.Save(Png) 兜底（静态图，会丢失动效和元数据）
class ClipboardPasteService {
  ClipboardPasteService._();

  /// 缓存文件最长保留时间
  static const _maxCacheAge = Duration(hours: 1);

  /// 可识别的图片扩展名（带点、小写）
  static const imageExtensions = <String>{
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.bmp',
    '.webp',
  };

  /// 扩展名（带点、小写）；没有扩展名返回空串
  static String extensionOf(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '';
    return path.substring(dot).toLowerCase();
  }

  /// 是否为图片路径
  static bool isImagePath(String path) =>
      imageExtensions.contains(extensionOf(path));

  /// 读取剪贴板：一次 PowerShell 调用同时检测文件列表与图片。
  ///
  /// [files] 中的每个文件都会**复制一份**到临时缓存目录（调用方负责使用后
  /// 删除），因此不会把用户原文件当作临时文件删掉。
  static Future<ClipboardPasteData> pasteClipboard() async {
    if (!Platform.isWindows) return const ClipboardPasteData();
    try {
      final cacheDir = Directory(await AppPaths.clipboardDir);
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final script = _clipboardScript
          .replaceAll('__BASE__', cacheDir.path)
          .replaceAll('__TS__', '$timestamp');

      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        script,
      ], stdoutEncoding: utf8);
      if (result.exitCode != 0) return const ClipboardPasteData();

      final dropPaths = <String>[];
      File? image;
      for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
        if (line.startsWith('DROP:')) {
          final path = line.substring(5).trim();
          if (path.isNotEmpty) dropPaths.add(path);
        } else if (line.startsWith('IMAGE:')) {
          final path = line.substring(6).trim();
          if (path.isEmpty) continue;
          final file = File(path);
          if (await file.exists() && await file.length() > 0) image = file;
        }
      }

      final copied = await _copyToCache(dropPaths, cacheDir, timestamp);
      if (copied.files.isNotEmpty || image != null) {
        unawaited(_cleanCache(cacheDir));
      }
      return ClipboardPasteData(
        files: copied.files,
        image: image,
        ignored: copied.ignored,
      );
    } catch (_) {
      return const ClipboardPasteData();
    }
  }

  /// 检测剪贴板是否有图片，有则返回缓存文件
  ///
  /// 返回临时 [File]（调用方负责使用后删除），无图片返回 null。
  static Future<File?> pasteImage() async {
    final data = await pasteClipboard();
    final images = data.files.where((f) => isImagePath(f.path)).toList();

    // 只保留第一张图片，其余副本（含非图片文件）直接清理
    for (final file in data.files) {
      if (images.isEmpty || !identical(file, images.first)) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    return images.isNotEmpty ? images.first : data.image;
  }

  /// 把源文件复制到缓存目录（保留原文件名：附件上传取的是缓存文件 basename）
  static Future<({List<File> files, int ignored})> _copyToCache(
    List<String> sources,
    Directory cacheDir,
    int timestamp,
  ) async {
    final files = <File>[];
    var ignored = 0;
    for (var i = 0; i < sources.length; i++) {
      final srcPath = sources[i];
      final src = File(srcPath);
      if (!await src.exists()) {
        ignored++; // 目录 / 已删除的文件
        continue;
      }

      final name = srcPath.split(RegExp(r'[/\\]')).last;
      final dest = File('${cacheDir.path}\\${timestamp}_${i}_$name');
      try {
        await src.copy(dest.path);
        // File.copy 在 Windows 上会保留源文件的最后修改时间。源文件很旧时，
        // 新副本会被 _cleanCache 当成过期缓存，在上传读文件的同一时刻删除，
        // 表现为 PathAccessException errno 32（文件被另一个程序占用）。
        // 副本必须显式刷新时间戳，保证至少存活一个缓存周期。
        try {
          await dest.setLastModified(DateTime.now());
        } catch (_) {
          // 时间戳刷新失败不丢文件：上传失败会走正常的失败提示
        }
        files.add(dest);
      } catch (_) {
        // 单个文件复制失败不影响其余文件
      }
    }
    return (files: files, ignored: ignored);
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

/// 一次 PowerShell 调用读取剪贴板，按优先级输出：
/// - `DROP:{path}`：资源管理器复制的文件（可多行）
/// - `IMAGE:{path}`：位图已写入缓存
/// - `NONE`：没有文件也没有图片
///
/// `__BASE__` / `__TS__` 由调用方替换（PowerShell 单引号字符串，路径不参与转义）。
/// 显式设 UTF-8：中文用户名/文件名经管道返回时不会被系统代码页破坏。
const _clipboardScript = r'''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms

# --- 1. 文件列表（CF_HDROP）---
$drop = [System.Windows.Forms.Clipboard]::GetFileDropList()
if ($drop -ne $null -and $drop.Count -gt 0) {
  foreach ($f in $drop) {
    if ($f) { Write-Output "DROP:$f" }
  }
  return
}

# --- 2. 原始编码字节（PNG / GIF / JFIF）---
$formats = @('PNG', 'GIF', 'JFIF')
$extMap = @{ 'PNG'='.png'; 'GIF'='.gif'; 'JFIF'='.jpg' }
foreach ($fmt in $formats) {
  if ([System.Windows.Forms.Clipboard]::ContainsData($fmt)) {
    $data = [System.Windows.Forms.Clipboard]::GetData($fmt)
    if ($data -ne $null) {
      $outPath = '__BASE__\img___TS__' + $extMap[$fmt]
      [System.IO.File]::WriteAllBytes($outPath, [byte[]]$data)
      Write-Output "IMAGE:$outPath"
      return
    }
  }
}

# --- 3. 兜底：GetImage + Save(Png) ---
$img = [System.Windows.Forms.Clipboard]::GetImage()
if ($img -ne $null) {
  $outPath = '__BASE__\img___TS__.png'
  $img.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $img.Dispose()
  Write-Output "IMAGE:$outPath"
  return
}

Write-Output "NONE"
''';

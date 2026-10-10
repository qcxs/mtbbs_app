import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:mtbbs/api/forum/post/upload.dart' as upload_api;
import 'package:mtbbs/core/parser/page_fetcher.dart';
import 'package:mtbbs/core/utils/cache_utils.dart';
import 'package:mtbbs/core/utils/logger.dart';
import 'package:mtbbs/services/api_service.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 快速上传论坛图片并插入 `[attachimg]aid[/attachimg]`（迷你编辑器用）。
///
/// 完整版走「图片管理面板」（列表/删除/忽略/刷新）；迷你版只要"选图→上传→插入"
/// 一条龙，因此这里只保留必要步骤。上传成功后清理 file_picker 的临时副本
/// （见 docs/07 #28）。
Future<void> uploadForumImagesQuick({
  required BBCodeController contentCtl,
  required PageFormData pageData,
  required String uid,
  VoidCallback? focus,
}) async {
  if (pageData.uploadHash.isEmpty) {
    showToast('页面数据未加载，无法上传');
    return;
  }

  final imgExts = pageData.imageExtensions;
  final result = await FilePicker.platform.pickFiles(
    type: imgExts.isNotEmpty ? FileType.custom : FileType.image,
    allowedExtensions: imgExts.isNotEmpty ? imgExts : null,
    allowMultiple: true,
    withReadStream: true,
    // 关闭插件默认压缩：否则 GIF 丢动画、PNG 被转 JPG（docs/07 #14）
    allowCompression: false,
  );
  if (result == null || result.files.isEmpty) return;

  int success = 0;
  int fail = 0;
  String lastError = '';
  for (final f in result.files) {
    final path = f.path;
    if (path == null) {
      fail++;
      continue;
    }
    try {
      final up = await upload_api.uploadImage(
        ApiService().dio,
        file: File(path),
        uid: uid,
        uploadHash: pageData.uploadHash,
      );
      if (up['success'] == true) {
        final aid = up['aid']?.toString() ?? '';
        if (aid.isNotEmpty) {
          contentCtl.wrapInline('', '', '[attachimg]$aid[/attachimg]');
          success++;
        } else {
          fail++;
        }
        await deleteFilePickerTempIfAny(path);
      } else {
        fail++;
        lastError = up['error']?.toString() ?? '';
      }
    } catch (e) {
      fail++;
      lastError = e.toString();
    }
  }

  AppLogger.i(
    'EDITOR',
    'quick image upload: success=$success fail=$fail total=${result.files.length}',
  );
  focus?.call();
  if (success > 0 && fail == 0) {
    showToast('已插入 $success 张图片');
  } else if (success > 0) {
    showToast('上传完成：成功 $success 张，失败 $fail 张');
  } else {
    showToast('上传失败${lastError.isNotEmpty ? '：$lastError' : ''}');
  }
}

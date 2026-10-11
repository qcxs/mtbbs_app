import 'package:flutter/material.dart';

import 'package:mtbbs/pages/editor/forum_image_controller.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/image_picker_sheet.dart';

/// 打开"图片管理"抽屉 —— 迷你编辑器（帖子页）的图片入口。
///
/// 与完整编辑器**共用同一套** [ImagePickerSheet]（纯 UI）与同一个
/// [ForumImageController]（状态/动作唯一实现）。
///
/// 控制器由**调用方持有**（迷你编辑器在页面生命周期内持久持有，以便在工具栏上显示
/// 图片角标；完整版另在 `_EditorPageState` 持有）。本函数只负责"刷新 + 渲染抽屉"。
Future<void> showForumImageDrawer(
  BuildContext context, {
  required ForumImageController controller,
}) async {
  final data = controller.pageData();
  if (data.uploadHash.isEmpty) {
    showToast('页面数据未加载，无法上传');
    return;
  }
  // 每次打开刷新"已上传未使用"的图片（控制器持有列表，关闭不清空）
  controller.refresh();
  final extensions = data.imageExtensions;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 500, maxHeight: 450),
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (_, __) => ImagePickerSheet(
        images: controller.list,
        loading: controller.loading,
        ignoredAids: controller.ignoredAids,
        contentText: controller.contentCtl.text,
        controller: controller.contentCtl,
        onUpload: controller.upload,
        onDelete: controller.delete,
        onIgnore: controller.ignore,
        onRefresh: controller.refresh,
        onInsert: (aid) {
          controller.contentCtl.wrapInline(
            '',
            '',
            '[attachimg]$aid[/attachimg]',
          );
          controller.syncPendingAids();
        },
        allowedExtensions: extensions.isNotEmpty ? extensions : null,
      ),
    ),
  );
}

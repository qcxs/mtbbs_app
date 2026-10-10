import 'package:flutter/material.dart';

import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/core/app/emoji_loader.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/pages/editor/editor_dialogs.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';
import 'package:mtbbs/widgets/dialog/emoji_picker_sheet.dart';

/// 工具栏动作中"上下文相关入口"的回调集合。
///
/// 完整版（全屏）与迷你版（帖子页 / 私信页内嵌）共用同一套动作逻辑
/// （见 [dispatchToolbarItem]），差异只在图片/附件/图床/历史/导入这些
/// 入口各自的实现，由各自的 Surface 注入。
class EditorActionHooks {
  const EditorActionHooks({
    required this.focus,
    required this.onImage,
    this.onAttachment,
    this.onMtImage,
    this.onHistory,
    this.onHistoryPage,
    this.onMdImport,
    this.onQuickReply,
    this.onOpenSettings,
    this.undoController,
  });

  /// 焦点回到正文
  final VoidCallback focus;

  /// 图片（论坛图片上传；私信页无此能力，传 null）
  final VoidCallback? onImage;

  /// 附件（仅完整版有）
  final VoidCallback? onAttachment;

  /// MT 图床面板
  final VoidCallback? onMtImage;

  /// 浏览历史选择器
  final VoidCallback? onHistory;

  /// 编辑历史页
  final VoidCallback? onHistoryPage;

  /// 导入 Markdown
  final VoidCallback? onMdImport;

  /// 常用语选择（弹出常用语面板并插入）
  final VoidCallback? onQuickReply;

  /// 打开编辑器设置
  final VoidCallback? onOpenSettings;

  /// 撤销/重做控制器（迷你版可不提供，此时撤销/重做按钮无效果）
  final UndoHistoryController? undoController;
}

/// 分发工具栏项点击 / 快捷键（模板项与复杂项统一入口）。
///
/// [items] 是当前工具栏实际展示的项列表（完整版=settings.toolbarItems，
/// 迷你版=settings.miniToolbarItems(ctx)），模板文本从其中取，保证两版一致。
void dispatchToolbarItem(
  BuildContext context,
  BBCodeController contentCtl,
  List<ManagedItem> items, {
  required String id,
  required EditorActionHooks hooks,
}) {
  if (id == kImageLongPressId) {
    _insertImageByUrl(context, contentCtl, hooks);
    return;
  }
  if (id == kEditorSettingsId) {
    hooks.onOpenSettings?.call();
    return;
  }

  final index = items.indexWhere((e) => e.id == id);
  if (index >= 0) {
    final item = items[index];
    final template = toolbarTemplateOf(item);
    if (template != null) {
      // 无占位符的块级模板（[hr]、表格骨架）按块级插入；其余走统一模板应用
      if (toolbarIsBlockOf(item) && !template.contains(kSelectTextToken)) {
        contentCtl.insertBlockTag(template);
      } else {
        contentCtl.applyTemplate(template);
      }
      hooks.focus();
      return;
    }
  }

  final action = resolveToolbarAction(id);
  if (action != null)
    _dispatchToolbarAction(context, contentCtl, action, hooks);
}

void _dispatchToolbarAction(
  BuildContext context,
  BBCodeController ctl,
  ToolbarAction action,
  EditorActionHooks hooks,
) {
  switch (action) {
    case ToolbarAction.undo:
      hooks.undoController?.undo();
      hooks.focus();
    case ToolbarAction.redo:
      hooks.undoController?.redo();
      hooks.focus();
    case ToolbarAction.select:
      ctl.selectTag();
      hooks.focus();
    case ToolbarAction.clearStyles:
      ctl.clearStyles();
      hooks.focus();
    case ToolbarAction.link:
      _insertLink(context, ctl, hooks);
    case ToolbarAction.image:
      hooks.onImage?.call();
    case ToolbarAction.attach:
      hooks.onAttachment?.call();
    case ToolbarAction.imageLongPress:
      _insertImageByUrl(context, ctl, hooks);
    case ToolbarAction.emoji:
      showEmojiPickerFor(context, ctl, hooks.focus);
    case ToolbarAction.color:
      showColorPickerDialog(context, ctl, hooks.focus, isBackcolor: false);
    case ToolbarAction.backcolor:
      showColorPickerDialog(context, ctl, hooks.focus, isBackcolor: true);
    case ToolbarAction.fontSize:
      showFontSizePicker(context, ctl, hooks.focus);
    case ToolbarAction.history:
      hooks.onHistory?.call();
    case ToolbarAction.editHistory:
      hooks.onHistoryPage?.call();
    case ToolbarAction.mdImport:
      hooks.onMdImport?.call();
    case ToolbarAction.quickReply:
      hooks.onQuickReply?.call();
    case ToolbarAction.mtImage:
      hooks.onMtImage?.call();
  }
}

void _insertLink(
  BuildContext context,
  BBCodeController ctl,
  EditorActionHooks hooks,
) {
  final sel = ctl.selection;
  final selectedText = sel.isValid && !sel.isCollapsed
      ? ctl.text.substring(sel.start, sel.end).trim()
      : '';
  if (selectedText.isNotEmpty) {
    final isUrl =
        selectedText.startsWith('http://') ||
        selectedText.startsWith('https://');
    if (isUrl) {
      ctl.wrapSelection('[url]', '[/url]');
    } else {
      ctl.wrapBlock('[url=]', '[/url]');
    }
    hooks.focus();
    return;
  }
  showTextInputDialog(
    context,
    title: '插入链接',
    label: 'URL',
    hint: 'https://...',
    value: '',
    secondLabel: '显示文字',
    secondHint: '可选',
    secondValue: '',
    onSubmit: (url, text) {
      final hasUrl = url.isNotEmpty;
      final hasText = text.isNotEmpty;
      if (hasUrl && hasText) {
        ctl.wrapInline('[url=$url]', '[/url]', text);
      } else if (hasUrl) {
        ctl.wrapInline('[url]', '[/url]', url);
      } else if (hasText) {
        ctl.wrapInline('[url=]', '[/url]', text);
      }
      if (hasUrl || hasText) hooks.focus();
    },
  );
}

void _insertImageByUrl(
  BuildContext context,
  BBCodeController ctl,
  EditorActionHooks hooks,
) {
  showTextInputDialog(
    context,
    title: '插入图片',
    label: '图片 URL',
    hint: 'https://...',
    value: '',
    onSubmit: (url, _) {
      if (url.isNotEmpty) {
        ctl.insertImage(url);
        hooks.focus();
      }
    },
  );
}

/// 表情选择底部面板（完整版 / 迷你版共用）
Future<void> showEmojiPickerFor(
  BuildContext context,
  BBCodeController contentCtl,
  VoidCallback focus,
) async {
  final emojiService = EmojiService();
  if (!emojiService.isLoaded) {
    showToast('暂无表情数据，请在设置中加载');
    return;
  }
  await showModalBottomSheet(
    context: context,
    constraints: const BoxConstraints(maxWidth: 500, maxHeight: 420),
    builder: (ctx) => EmojiPickerSheet(
      groups: emojiService.groups,
      frequentEmojis: emojiService.frequentlyUsed,
      onEmojiPicked: (emoji) {
        final insertText = emoji['insertText'] as String;
        final smilieId = emoji['smilieId'] as String;
        contentCtl.wrapInline('', '', insertText);
        EmojiService().recordUsage(smilieId);
        focus();
      },
    ),
  );
}

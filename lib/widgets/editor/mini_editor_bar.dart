import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:mtbbs/config/toolbar_config.dart';
import 'package:mtbbs/models/managed_item.dart';
import 'package:mtbbs/pages/editor/editor_interactions.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_controller.dart';
import 'package:mtbbs/widgets/bbcode/bbcode_toolbar.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/dialog/quick_reply_dialog.dart';

/// 迷你编辑器 — 帖子页 / 私信页内嵌使用的紧凑编辑表面。
///
/// 与完整版 [EditorPage] **共用** `EditorSession`（内容/页面数据/提交协议）
/// 与 [dispatchToolbarItem]（工具栏动作逻辑），差异只在：
/// - 工具栏项取 `settings.miniToolbarItems(toolbarContext)`：
///   与完整版**共用同一套工具栏**（同一顺序），只按该上下文的可见性（`data['mini']`）过滤
/// - 图片入口由调用方注入：帖子页=论坛图片上传（`onImage`）+ MT 图床（`onMtImage`）；
///   私信页只有 MT 图床（`onMtImage`，`onImage` 传 null）
/// - "展开为完整版"由调用方处理（先保存保底 → 内存交接给 `/editor`）
///
/// 右上角固定：预览切换 / 展开完整版 / 收起。常用语已作为工具栏项（`quickReply`）。
class MiniEditorBar extends StatefulWidget {
  const MiniEditorBar({
    super.key,
    required this.contentCtl,
    required this.toolbarContext,
    required this.onSubmit,
    this.onImage,
    this.onMtImage,
    this.onExpandToFull,
    this.onCollapse,
    this.targetLabel,
    this.onTapTarget,
    this.hintText = '说点什么…',
    this.submitting = false,
    this.autofocus = false,
  });

  /// 正文控制器（通常来自 `EditorSession.contentCtl`；私信页可独立创建）
  final BBCodeController contentCtl;

  /// 决定使用哪一份迷你工具栏配置
  final MiniToolbarContext toolbarContext;

  /// 提交（由调用方完成实际请求与善后，例如帖子页追加楼层 / 私信发送）
  final Future<void> Function() onSubmit;

  /// 论坛图片上传（帖子页有；私信页为 null）
  final VoidCallback? onImage;

  /// MT 图床面板
  final VoidCallback? onMtImage;

  /// 展开为完整版编辑器（私信页无完整版，传 null 时不显示入口）
  final VoidCallback? onExpandToFull;

  /// 收起（读帖）；为 null 时不显示收起按钮
  final VoidCallback? onCollapse;

  /// 当前回复目标（如 "回复 @某人"）；非空时显示目标芯片（点击弹预览）。
  ///
  /// 刻意不提供"取消目标"按钮：关闭回复等同于关闭迷你编辑器（收起），
  /// 避免"还在回复评论？还是回复帖子？"的歧义。
  final String? targetLabel;

  /// 点击目标芯片（弹窗预览被回复的评论内容）
  final VoidCallback? onTapTarget;

  final String hintText;
  final bool submitting;
  final bool autofocus;

  @override
  State<MiniEditorBar> createState() => _MiniEditorBarState();
}

class _MiniEditorBarState extends State<MiniEditorBar> {
  late final BBCodeToolbarController _toolbarCtl;
  final FocusNode _focusNode = FocusNode();
  final UndoHistoryController _undoController = UndoHistoryController();
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _toolbarCtl = BBCodeToolbarController(onAction: _onToolbarAction);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
    }
  }

  @override
  void dispose() {
    _undoController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _focus() {
    if (_previewing) return;
    _focusNode.requestFocus();
  }

  void _onToolbarAction(String id) {
    dispatchToolbarItem(
      context,
      widget.contentCtl,
      context.read<SettingsProvider>().miniToolbarItems(widget.toolbarContext),
      id: id,
      hooks: EditorActionHooks(
        focus: _focus,
        onImage: widget.onImage,
        onMtImage: widget.onMtImage,
        onQuickReply: () =>
            showQuickReplyPicker(context, widget.contentCtl, _focus),
        undoController: _undoController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final items = settings.miniToolbarItems(widget.toolbarContext);
    final shortcuts = {
      for (final item in items) item.id: settings.toolbarShortcut(item.id),
    };

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 4,
        top: 2,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopRow(cs, items, shortcuts),
          const SizedBox(height: 6),
          _buildBody(cs),
          const SizedBox(height: 6),
          _buildActionRow(cs),
        ],
      ),
    );
  }

  /// 单行顶部：回复目标芯片 + 工具栏 + 右上角（预览 / 完整版 / 收起）。
  ///
  /// 共用一行为的是不出现"只有几个按钮的空行"（私信页曾在预览按钮上浪费一整行），
  /// 同时芯片与工具栏相邻、操作按钮固定在右侧。
  Widget _buildTopRow(
    ColorScheme cs,
    List<ManagedItem> items,
    Map<String, String> shortcuts,
  ) {
    return Row(
      children: [
        if (widget.targetLabel != null) ...[
          InkWell(
            onTap: widget.onTapTarget,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.reply_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      widget.targetLabel!,
                      style: TextStyle(fontSize: 12, color: cs.primary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: _previewing
              ? const SizedBox.shrink()
              : ValueListenableBuilder<UndoHistoryValue>(
                  valueListenable: _undoController,
                  builder: (_, undoVal, __) => BBCodeToolbar(
                    controller: _toolbarCtl,
                    canUndo: undoVal.canUndo,
                    canRedo: undoVal.canRedo,
                    items: items,
                    shortcuts: shortcuts,
                    showSettingsButton: false,
                    showContainer: false,
                  ),
                ),
        ),
        IconButton(
          icon: Icon(
            _previewing ? Icons.edit_outlined : Icons.visibility_outlined,
            size: 20,
          ),
          tooltip: _previewing ? '编辑' : '预览',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _previewing = !_previewing),
        ),
        if (widget.onExpandToFull != null)
          IconButton(
            icon: const Icon(Icons.open_in_full, size: 20),
            tooltip: '展开为完整版',
            visualDensity: VisualDensity.compact,
            onPressed: widget.submitting ? null : widget.onExpandToFull,
          ),
        if (widget.onCollapse != null)
          IconButton(
            icon: const Icon(Icons.expand_more, size: 20),
            tooltip: '收起',
            visualDensity: VisualDensity.compact,
            onPressed: widget.submitting ? null : widget.onCollapse,
          ),
      ],
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_previewing) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.contentCtl,
              builder: (_, value, __) {
                final text = value.text.trim();
                if (text.isEmpty) {
                  return Text(
                    '（无内容）',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  );
                }
                return PostHtmlWidget(bbcode: value.text);
              },
            ),
          ),
        ),
      );
    }
    return TextField(
      controller: widget.contentCtl,
      focusNode: _focusNode,
      undoController: _undoController,
      minLines: 2,
      maxLines: 6,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildActionRow(ColorScheme cs) {
    // 撤销/重做不再固定在此：它们是工具栏项（`undo`/`redo`），
    // 由工具栏渲染与派发（共用 `EditorActionHooks.undoController`）。
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.contentCtl,
          builder: (_, value, __) {
            final hasText = value.text.trim().isNotEmpty;
            if (widget.submitting) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return FilledButton.icon(
              onPressed: hasText ? widget.onSubmit : null,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('发送'),
            );
          },
        ),
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:mtbbs/pages/editor/editor_session.dart';

/// 人机验证输入行 — 完整版编辑器与迷你版编辑器共用。
///
/// 两种形态：
/// - **图片验证码**（默认）：展示图片，提示「输入验证码」；
/// - **验证问答**（[isQaa]）：展示题面，提示「输入答案」。
///
/// 图片/题面都由 [EditorSession] 通过站点 Dio 拉取（带 cookie），这里只负责
/// 展示，所以不使用 `CachedNetworkImage`（每次都必须实时请求）。
class CaptchaField extends StatelessWidget {
  const CaptchaField({
    super.key,
    required this.controller,
    required this.onRefresh,
    this.image,
    this.question = '',
    this.isQaa = false,
    this.answerHint = '',
    this.loading = false,
    this.failed = false,
  });

  final TextEditingController controller;
  final Uint8List? image;
  final String question;
  final bool isQaa;

  /// 题面里自带的答案提示；非空时显示「填充答案」按钮
  final String answerHint;

  final bool loading;
  final bool failed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!isQaa) return _buildImageRow(theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 题面一行：右侧放「填充答案 / 换一个」，输入框另起一行铺满宽度
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('验证问答', style: theme.textTheme.bodySmall),
            const SizedBox(width: 8),
            Expanded(child: _buildQuestion(theme)),
            if (answerHint.isNotEmpty)
              TextButton.icon(
                onPressed: _fillAnswer,
                icon: const Icon(Icons.auto_fix_high, size: 16),
                label: const Text('填充答案'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            IconButton(
              onPressed: loading ? null : onRefresh,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: '换一个',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(width: double.infinity, child: _buildTextField(theme)),
      ],
    );
  }

  /// 把题面里自带的答案填进输入框（站点把答案写在题目里时才有此入口）
  void _fillAnswer() {
    controller.text = answerHint;
    controller.selection = TextSelection.collapsed(offset: answerHint.length);
  }

  Widget _buildQuestion(ThemeData theme) {
    if (loading) {
      return Text('题目加载中…', style: theme.textTheme.bodySmall);
    }
    if (question.isEmpty) {
      return Text(
        failed ? '题目加载失败，点击刷新' : '点击刷新加载题目',
        style: theme.textTheme.bodySmall,
      );
    }
    return SelectableText(question, style: theme.textTheme.bodyMedium);
  }

  Widget _buildImageRow(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('验证码', style: theme.textTheme.bodySmall),
        SizedBox(width: 110, child: _buildTextField(theme)),
        InkWell(
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 100,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _buildImage(theme),
          ),
        ),
        IconButton(
          onPressed: loading ? null : onRefresh,
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: '换一个',
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _buildTextField(ThemeData theme) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        isDense: true,
        hintText: isQaa ? '输入答案' : '输入验证码',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
      ),
    );
  }

  Widget _buildImage(ThemeData theme) {
    if (loading) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (image != null) {
      return Image.memory(
        image!,
        width: 100,
        height: 30,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }
    return Text(
      failed ? '加载失败' : '点击刷新',
      style: theme.textTheme.bodySmall,
    );
  }
}

/// 按页面实际开启的验证类型渲染输入行（可能同时开启图片验证码与验证问答）。
class CaptchaFields extends StatelessWidget {
  const CaptchaFields({super.key, required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (session.seccodeRequired)
            CaptchaField(
              controller: session.seccodeCtl,
              image: session.seccodeImage,
              loading: session.seccodeLoading,
              failed: session.seccodeFailed,
              onRefresh: () => session.loadSeccodeImage(),
            ),
          if (session.secqaaRequired)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CaptchaField(
                controller: session.secqaaCtl,
                isQaa: true,
                question: session.secqaaQuestion,
                answerHint: session.secqaaAnswerHint,
                loading: session.secqaaLoading,
                failed: session.secqaaFailed,
                onRefresh: () => session.loadSecqaaQuestion(),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mtbbs/core/parser/plain_bbcode.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/widgets/common/app_sheet.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 正文来源视角：App 内部结构 / 可粘贴的纯 BBCode
enum PostSourceView { appdata, bbcode }

/// 「查看」抽屉：展示一楼的 BBCode 原文
///
/// 右上角切换两种视角：
/// - **App**：保留 `[appdata]` 原始 JSON，便于排查解析问题；
/// - **BBCode**：appdata 已降级为标准标签（图片附件 → `[img]` 等），
///   可以直接粘贴进编辑器。
class PostSourceSheet extends StatefulWidget {
  const PostSourceSheet({
    super.key,
    required this.username,
    required this.bbcode,
  });

  final String username;
  final String bbcode;

  /// 打开底部抽屉
  static Future<void> show(
    BuildContext context, {
    required String username,
    required String bbcode,
  }) {
    return showAppSheet<void>(
      context: context,
      // 正文可能很长，给到屏幕 82% 高度
      maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      builder: (_) => PostSourceSheet(username: username, bbcode: bbcode),
    );
  }

  @override
  State<PostSourceSheet> createState() => _PostSourceSheetState();
}

class _PostSourceSheetState extends State<PostSourceSheet> {
  PostSourceView _view = PostSourceView.bbcode;

  /// 纯 BBCode 只算一次：抽屉内切换视角时不重复解析长正文
  late final String _plainBbcode = toPlainBbcode(widget.bbcode);

  String get _currentText =>
      _view == PostSourceView.appdata ? widget.bbcode : _plainBbcode;

  Future<void> _copy() async {
    final ok = await ClipboardHelper.write(_currentText);
    showToast(ok ? '已复制' : '复制失败');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppSheetScaffold(
      title: widget.username.isEmpty ? '查看' : '查看 · ${widget.username}',
      actions: [
        _ViewToggle(
          value: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        IconButton(
          tooltip: '复制当前视角',
          onPressed: _copy,
          icon: const Icon(Icons.copy, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ],
      child: Column(
        // 默认 center 会让正文块按内容宽度居中，短内容看起来像被缩进
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                // 与正文区分：浅色底 + 图标，避免被当成正文内容
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _view == PostSourceView.appdata
                          ? 'App 视角：保留 appdata 原始结构'
                          : '纯 BBCode：appdata 已还原为标准标签，可直接粘贴到编辑器',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                child: SelectableText(
                  _currentText,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    color: cs.onSurface,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 右上角的 App / BBCode 切换器
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.value, required this.onChanged});

  final PostSourceView value;
  final ValueChanged<PostSourceView> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, PostSourceView.bbcode, 'BBCode'),
          _segment(context, PostSourceView.appdata, 'App'),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    PostSourceView target,
    String label,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == target;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(target),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

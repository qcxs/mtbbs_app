import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';

/// 编辑器预览数据（防抖后更新）
class EditorPreviewData {
  final String title;
  final String content;
  const EditorPreviewData(this.title, this.content);
}

/// 编辑器预览面板 — 渲染标题 + BBCode 内容。
///
/// 宽屏时作为右栏，窄屏时作为预览页；长按内容弹出原始 BBCode。
class EditorPreview extends StatelessWidget {
  final ValueListenable<EditorPreviewData> data;
  final ValueChanged<String> onShowRaw;

  const EditorPreview({super.key, required this.data, required this.onShowRaw});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<EditorPreviewData>(
      valueListenable: data,
      builder: (context, data, _) {
        final settings = context.read<SettingsProvider>();
        if (data.title.isEmpty && data.content.isEmpty) {
          return Center(
            child: Text(
              '输入内容后即可预览',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              data.content.isNotEmpty
                  ? GestureDetector(
                      onLongPress: () => onShowRaw(data.content),
                      child: PostHtmlWidget(
                        bbcode: data.content,
                        disabledTags: settings.disabledBbcodeTags,
                        autoDetectUrls: settings.autoDetectUrls,
                      ),
                    )
                  : Text('暂无内容', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        );
      },
    );
  }
}

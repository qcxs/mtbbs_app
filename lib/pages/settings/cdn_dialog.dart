import 'package:flutter/material.dart';
import 'package:mtbbs/core/app/site_cdn.dart';
import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 站点 CDN 查看对话框 — 独立组件，可在任意页面调用。
///
/// 与 [FormulaDialog] 同一交互范式：点击设置项只弹窗展示，
/// 是否重新检测由用户点标题右侧的刷新按钮决定。
class CdnDialog {
  static void show(BuildContext context) {
    final host = SiteStore.instance.host;
    var busy = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final cs = Theme.of(ctx).colorScheme;
          final cdn = SiteCdnStore.instance.cdnFor(host);
          return AlertDialog(
            title: Row(
              children: [
                const Expanded(child: Text('CDN 检测')),
                GestureDetector(
                  onTap: busy
                      ? null
                      : () async {
                          setD(() => busy = true);
                          final result = await detectSiteCdn(
                            host: host,
                            force: true,
                          );
                          if (!ctx.mounted) return;
                          setD(() => busy = false);
                          showToast(
                            result == null
                                ? '未识别到 CDN，继续使用站点地址'
                                : 'CDN: $result',
                          );
                        },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : Icon(
                            Icons.refresh,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                  ),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxWidth: 400),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前站点：$host',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '识别到的 CDN：',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cdn ?? '未识别，当前使用站点地址',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: cdn == null
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'CDN 由站点自动下发，识别后用于表情与静态图片，'
                      '无需手动配置；识别不到时回退站点地址。',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }
}

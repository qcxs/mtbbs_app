import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 排行条目卡片
///
/// 显示排名、标题、版块、作者、时间、统计值。
class RankTile extends StatelessWidget {
  final int rank;
  final String title;
  final String forumName;
  final String author;
  final String time;
  final String count;
  final String tid;

  const RankTile({
    super.key,
    required this.rank,
    required this.title,
    required this.forumName,
    required this.author,
    required this.time,
    required this.count,
    required this.tid,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTop = rank > 0 && rank <= 3;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (tid.isNotEmpty) context.push('/thread/$tid');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // 排名 — 前三名用实心徽章，其余只是数字，拉开主次
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isTop ? cs.primary : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isTop ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 标题 + 元信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          forumName,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          ' · $author',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          Text(
                            ' · $time',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 数值
              Text(
                count,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

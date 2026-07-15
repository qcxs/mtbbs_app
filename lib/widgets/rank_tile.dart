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
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (tid.isNotEmpty) context.push('/thread/$tid');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              // 排名
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: rank <= 3
                        ? Colors.deepOrange.shade400
                        : Colors.grey.shade500,
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
                            color: Colors.blue.shade400,
                          ),
                        ),
                        Text(
                          ' · $author',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if (time.isNotEmpty) ...[
                          Text(
                            ' · $time',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade400,
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
                  color: Colors.deepOrange.shade300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

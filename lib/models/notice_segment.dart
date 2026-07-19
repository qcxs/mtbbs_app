/// 通知消息段落
///
/// [type] 类型：text（纯文本）、user（用户链接）、thread（帖子链接）、quote（引用留言）
/// [text] 显示文本
/// [uid] 用户链接时的用户 ID
/// [url] 帖子链接时的跳转 URL
class NoticeSegment {
  final String type;
  final String text;
  final String? uid;
  final String? url;

  const NoticeSegment({
    required this.type,
    required this.text,
    this.uid,
    this.url,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        if (uid != null) 'uid': uid,
        if (url != null) 'url': url,
      };

  factory NoticeSegment.fromJson(Map<String, dynamic> json) => NoticeSegment(
        type: json['type'] as String,
        text: json['text'] as String? ?? '',
        uid: json['uid'] as String?,
        url: json['url'] as String?,
      );
}

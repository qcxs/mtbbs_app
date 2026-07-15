/// 帖子列表项数据模型
class ThreadItem {
  final int? uid;
  final String? nickname;
  final String? level;
  final String? time;
  final String? followUrl;
  final String? title;
  final String? summary;
  final String? threadUrl;
  final int? threadId;
  final String? boardName;
  final String? boardUrl;
  final int? likes;
  final int? comments;
  final int? views;
  final List<String>? images;

  const ThreadItem({
    this.uid,
    this.nickname,
    this.level,
    this.time,
    this.followUrl,
    this.title,
    this.summary,
    this.threadUrl,
    this.threadId,
    this.boardName,
    this.boardUrl,
    this.likes,
    this.comments,
    this.views,
    this.images,
  });

  factory ThreadItem.fromJson(Map<String, dynamic> json) => ThreadItem(
    uid: json['uid'] as int?,
    nickname: json['nickname']?.toString(),
    level: json['level']?.toString(),
    time: json['time']?.toString(),
    followUrl: json['followUrl']?.toString(),
    title: json['title']?.toString(),
    summary: json['summary']?.toString(),
    threadUrl: json['threadUrl']?.toString(),
    threadId: json['threadId'] as int?,
    boardName: json['boardName']?.toString(),
    boardUrl: json['boardUrl']?.toString(),
    likes: json['likes'] as int?,
    comments: json['comments'] as int?,
    views: json['views'] as int?,
    images: json['images'] != null
        ? (json['images'] as List).cast<String>()
        : null,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'nickname': nickname,
    'level': level,
    'time': time,
    'followUrl': followUrl,
    'title': title,
    'summary': summary,
    'threadUrl': threadUrl,
    'threadId': threadId,
    'boardName': boardName,
    'boardUrl': boardUrl,
    'likes': likes,
    'comments': comments,
    'views': views,
    'images': images,
  };
}

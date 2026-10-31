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
  final int? boardId;
  final int? likes;
  final int? comments;
  final int? views;
  final List<String>? images;

  /// 精华等级（>0 = 精华帖；null/0 = 普通帖）。
  final int? digest;

  /// 标题前的状态徽标（如「回收站」「关闭」「审核中」）。
  ///
  /// 来自列表模板标题链接内的前置 `<span>`，与 [digest]（「精」）分开：
  /// 精华是正向荣誉、单独盖章；状态是提示，渲染成普通小标签。
  final List<String>? statusLabels;

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
    this.boardId,
    this.likes,
    this.comments,
    this.views,
    this.images,
    this.digest,
    this.statusLabels,
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
    boardId: json['boardId'] as int?,
    likes: json['likes'] as int?,
    comments: json['comments'] as int?,
    views: json['views'] as int?,
    images: json['images'] != null
        ? (json['images'] as List).cast<String>()
        : null,
    digest: json['digest'] as int?,
    statusLabels: json['statusLabels'] != null
        ? (json['statusLabels'] as List).map((e) => e.toString()).toList()
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
    'boardId': boardId,
    'likes': likes,
    'comments': comments,
    'views': views,
    'images': images,
    'digest': digest,
    'statusLabels': statusLabels,
  };
}

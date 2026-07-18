/// 帖子详情页数据模型
///
/// 对应 forum.php?mod=viewthread&tid={tid}&page={page} 的返回数据。
/// 基于 PC 模板解析，仅包含两个站点（标准 Discuz + 克米）的公共字段。
class ThreadViewData {
  final String tid;
  final String title;
  final int currentPage;
  final int totalPages;
  final String formhash;

  /// 楼主帖（page=1 时存在）
  final PostItem? mainPost;

  /// 评论列表（当前页除楼主外的帖子）
  final List<PostItem> posts;

  const ThreadViewData({
    required this.tid,
    required this.title,
    required this.currentPage,
    required this.totalPages,
    this.formhash = '',
    this.mainPost,
    this.posts = const [],
  });
}

/// 单帖数据模型（楼主和评论共用）
///
/// 基于 PC 模板 table#pidXX.plhin 结构解析。
/// 头像通过 uid 由 UserAvatar 组件渲染，模型中不存储。
class PostItem {
  final String pid;
  final int floor;
  final String floorLabel;
  final bool isOp;

  // 作者信息
  final String uid;
  final String username;
  final String usergroup;

  // 帖子信息
  final String postTime;
  final String ipLocation;
  final String source;
  final String bbcode;

  // 操作 URL
  final String rateUrl;
  final String followUrl;
  final String recommendUrl;
  final String favoriteUrl;
  final String kickUrl;
  final bool isLiked;

  /// 评分记录，结构 {header, detailUrl, totalScore, entries: [{username, uid, score, reason}]}
  final Map<String, dynamic>? rating;

  const PostItem({
    this.pid = '',
    this.floor = 0,
    this.floorLabel = '',
    this.isOp = false,
    this.uid = '',
    this.username = '',
    this.usergroup = '',
    this.postTime = '',
    this.ipLocation = '',
    this.source = '',
    this.bbcode = '',
    this.rateUrl = '',
    this.followUrl = '',
    this.recommendUrl = '',
    this.favoriteUrl = '',
    this.kickUrl = '',
    this.isLiked = false,
    this.rating,
  });

  bool get isMainPost => isOp;

  /// 从 parse 返回的 Map 构建
  factory PostItem.fromMap(Map<String, dynamic> p) => PostItem(
    pid: p['pid']?.toString() ?? '',
    floor: (p['floor'] as int?) ?? 0,
    floorLabel: p['floorLabel']?.toString() ?? '',
    isOp: p['isOp'] == true,
    uid: p['uid']?.toString() ?? '',
    username: p['username']?.toString() ?? '',
    usergroup: p['usergroup']?.toString() ?? '',
    postTime: p['postTime']?.toString() ?? '',
    ipLocation: p['ipLocation']?.toString() ?? '',
    source: p['source']?.toString() ?? '',
    bbcode: p['bbcode']?.toString() ?? '',
    rateUrl: p['rateUrl']?.toString() ?? '',
    followUrl: p['followUrl']?.toString() ?? '',
    recommendUrl: p['recommendUrl']?.toString() ?? '',
    favoriteUrl: p['favoriteUrl']?.toString() ?? '',
    kickUrl: p['kickUrl']?.toString() ?? '',
    isLiked: p['isLiked'] == true,
    rating: p['rating'] != null
        ? Map<String, dynamic>.from(p['rating'] as Map)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'pid': pid,
    'floor': floor,
    'floorLabel': floorLabel,
    'isOp': isOp,
    'uid': uid,
    'username': username,
    'usergroup': usergroup,
    'postTime': postTime,
    'ipLocation': ipLocation,
    'source': source,
    'bbcode': bbcode,
    'rateUrl': rateUrl,
    'followUrl': followUrl,
    'recommendUrl': recommendUrl,
    'favoriteUrl': favoriteUrl,
    'kickUrl': kickUrl,
    'isLiked': isLiked,
    'rating': rating,
  };
}

/// 用于安全地操作可为空值的链式调用
extension MapExtension<T> on T {
  R? let<R>(R Function(T) f) => f(this);
}

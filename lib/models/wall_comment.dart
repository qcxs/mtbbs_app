/// 留言板单条留言模型
///
/// 对应 `home.php?mod=space&uid={uid}&do=wall` 页面里
/// `#comment_ul > dl[id^=comment_]` 的一条。
class WallComment {
  final String cid;
  final String authorUid;
  final String authorName;
  final String avatar;
  final String time;

  /// 正文（BBCode）——服务端已把受限 BBCode 白名单渲染成 HTML，parse 层回退为 BBCode
  final String message;

  /// 引用块（回复某条留言时服务端注入）：被引作者 / 被引内容，空串表示无引用
  final String quotedUser;
  final String quotedText;

  /// 当前登录用户对该条可执行的操作（按页面实际渲染的操作链接判定）
  final bool canEdit;
  final bool canDelete;
  final bool canReply;

  const WallComment({
    this.cid = '',
    this.authorUid = '',
    this.authorName = '',
    this.avatar = '',
    this.time = '',
    this.message = '',
    this.quotedUser = '',
    this.quotedText = '',
    this.canEdit = false,
    this.canDelete = false,
    this.canReply = false,
  });

  factory WallComment.fromMap(Map<String, dynamic> m) => WallComment(
    cid: _s(m['cid']),
    authorUid: _s(m['authorUid']),
    authorName: _s(m['authorName']),
    avatar: _s(m['avatar']),
    time: _s(m['time']),
    message: _s(m['message']),
    quotedUser: _s(m['quotedUser']),
    quotedText: _s(m['quotedText']),
    canEdit: m['canEdit'] == true,
    canDelete: m['canDelete'] == true,
    canReply: m['canReply'] == true,
  );

  bool get hasQuote => quotedText.isNotEmpty;

  static String _s(dynamic v) => v?.toString() ?? '';
}

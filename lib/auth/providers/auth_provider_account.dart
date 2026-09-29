part of 'auth_provider.dart';

/// 账号模型
class Account {
  String username;
  String uid;
  String avatarUrl;
  String credits;
  String userGroup;
  String cookieString;

  // 个人资料扩展
  String nickname;
  String signature;
  String customTitle;
  bool online;
  bool emailVerified;
  String spaceUrl;
  int friends;
  int replies;
  int threads;
  String adminGroup;
  String onlineTime;
  String registerTime;
  String lastVisit;
  int reputation;
  int goldCoins;
  int credit;

  /// 登录是否已过期（服务器返回未登录但保留账号数据，供重新登录合并）
  bool expired;

  Account({
    required this.username,
    this.uid = '',
    this.expired = false,
    this.avatarUrl = '',
    this.credits = '',
    this.userGroup = '',
    this.cookieString = '',
    this.nickname = '',
    this.signature = '',
    this.customTitle = '',
    this.online = false,
    this.emailVerified = false,
    this.spaceUrl = '',
    this.friends = 0,
    this.replies = 0,
    this.threads = 0,
    this.adminGroup = '',
    this.onlineTime = '',
    this.registerTime = '',
    this.lastVisit = '',
    this.reputation = 0,
    this.goldCoins = 0,
    this.credit = 0,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'uid': uid,
    'expired': expired,
    'avatarUrl': avatarUrl,
    'credits': credits,
    'userGroup': userGroup,
    'cookieString': cookieString,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    username: json['username']?.toString() ?? '',
    uid: json['uid']?.toString() ?? '',
    expired: json['expired'] == true,
    avatarUrl: json['avatarUrl']?.toString() ?? '',
    credits: json['credits']?.toString() ?? '',
    userGroup: json['userGroup']?.toString() ?? '',
    cookieString: json['cookieString']?.toString() ?? '',
  );
}

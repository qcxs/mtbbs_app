/// 用户个人资料强类型模型
///
/// 对应 home.php?mod=space&uid={uid}&do=profile 返回的个人资料。
class UserProfile {
  // === 基本信息 ===
  final String uid;
  final String nickname;
  final String avatar;
  final String spaceUrl;
  final bool online;
  final bool emailVerified;
  final String signature;
  final String customTitle;

  // === 勋章 ===
  final List<Medal> medals;

  // === 统计概览 ===
  final int friends;
  final int replies;
  final int threads;
  final int shares;

  // === 详细资料 ===
  final String qq;
  final String gender;
  final String birthday;
  final String occupation;
  final String realName;
  final String residence;
  final String birthplace;

  // === 活动概况 ===
  final String userGroup;
  final String adminGroup;
  final String onlineTime;
  final String registerTime;
  final String lastVisit;
  final String registerIp;
  final String lastVisitIp;
  final String lastActivityTime;
  final String lastPostTime;
  final String timezone;

  // === 积分 ===
  final int credits;
  final int reputation;
  final int goldCoins;
  final int credit;
  final String usedSpace;

  const UserProfile({
    this.uid = '',
    this.nickname = '',
    this.avatar = '',
    this.spaceUrl = '',
    this.online = false,
    this.emailVerified = false,
    this.signature = '',
    this.customTitle = '',
    this.medals = const [],
    this.friends = 0,
    this.replies = 0,
    this.threads = 0,
    this.shares = 0,
    this.qq = '',
    this.gender = '',
    this.birthday = '',
    this.occupation = '',
    this.realName = '',
    this.residence = '',
    this.birthplace = '',
    this.userGroup = '',
    this.adminGroup = '',
    this.onlineTime = '',
    this.registerTime = '',
    this.lastVisit = '',
    this.registerIp = '',
    this.lastVisitIp = '',
    this.lastActivityTime = '',
    this.lastPostTime = '',
    this.timezone = '',
    this.credits = 0,
    this.reputation = 0,
    this.goldCoins = 0,
    this.credit = 0,
    this.usedSpace = '',
  });

  /// 从 space API 返回的 profile Map 构建
  factory UserProfile.fromMap(Map<String, dynamic> p) {
    final stats = (p['stats'] as Map<String, dynamic>?) ?? {};
    final details = (p['details'] as Map<String, dynamic>?) ?? {};
    final activity = (p['activity'] as Map<String, dynamic>?) ?? {};
    final points = (p['points'] as Map<String, dynamic>?) ?? {};
    final medalsList = (p['medals'] as List<dynamic>?) ?? [];

    return UserProfile(
      uid: _s(p['uid']),
      nickname: _s(p['nickname']),
      avatar: _s(p['avatar']),
      spaceUrl: _s(p['spaceUrl']),
      online: p['online'] as bool? ?? false,
      emailVerified: p['emailVerified'] as bool? ?? false,
      signature: _s(p['signature']),
      customTitle: _s(p['customTitle']),
      medals: medalsList
          .map((m) => Medal.fromMap(m as Map<String, dynamic>))
          .toList(),
      friends: _i(stats['friends']),
      replies: _i(stats['replies']),
      threads: _i(stats['threads']),
      shares: _i(stats['shares']),
      qq: _s(details['qq']),
      gender: _s(details['gender']),
      birthday: _s(details['birthday']),
      occupation: _s(details['occupation']),
      realName: _s(details['realName']),
      residence: _s(details['residence']),
      birthplace: _s(details['birthplace']),
      userGroup: _s(activity['userGroup']),
      adminGroup: _s(activity['adminGroup']),
      onlineTime: _s(activity['onlineTime']),
      registerTime: _s(activity['registerTime']),
      lastVisit: _s(activity['lastVisit']),
      registerIp: _s(activity['registerIp']),
      lastVisitIp: _s(activity['lastVisitIp']),
      lastActivityTime: _s(activity['lastActivityTime']),
      lastPostTime: _s(activity['lastPostTime']),
      timezone: _s(activity['timezone']),
      credits: _i(points['credits']),
      reputation: _i(points['reputation']),
      goldCoins: _i(points['goldCoins']),
      credit: _i(points['credit']),
      usedSpace: _s(points['usedSpace']),
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'nickname': nickname,
    'avatar': avatar,
    'spaceUrl': spaceUrl,
    'online': online,
    'emailVerified': emailVerified,
    'signature': signature,
    'customTitle': customTitle,
    'medals': medals.map((m) => m.toMap()).toList(),
    'stats': {
      'friends': friends,
      'replies': replies,
      'threads': threads,
      'shares': shares,
    },
    'details': {
      'qq': qq,
      'gender': gender,
      'birthday': birthday,
      'occupation': occupation,
      'realName': realName,
      'residence': residence,
      'birthplace': birthplace,
    },
    'activity': {
      'userGroup': userGroup,
      'adminGroup': adminGroup,
      'onlineTime': onlineTime,
      'registerTime': registerTime,
      'lastVisit': lastVisit,
      'lastVisitIp': lastVisitIp,
      'registerIp': registerIp,
      'lastActivityTime': lastActivityTime,
      'lastPostTime': lastPostTime,
      'timezone': timezone,
    },
    'points': {
      'credits': credits,
      'reputation': reputation,
      'goldCoins': goldCoins,
      'credit': credit,
      'usedSpace': usedSpace,
    },
  };

  static String _s(dynamic v) => v?.toString() ?? '';
  static int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }
}

/// 勋章模型
class Medal {
  final String name;
  final String icon;

  const Medal({required this.name, required this.icon});

  factory Medal.fromMap(Map<String, dynamic> m) =>
      Medal(name: _s(m['name']), icon: _s(m['icon']));

  Map<String, dynamic> toMap() => {'name': name, 'icon': icon};

  static String _s(dynamic v) => v?.toString() ?? '';
}

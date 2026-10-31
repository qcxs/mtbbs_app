/// 账号设置（按 host + uid 隔离）
///
/// 当前没有账号级偏好，先保留结构，后续账号级行为（自动签到、通知偏好等）
/// 直接往这里加字段，不再改存储层。
class AccountSettings {
  final int schemaVersion;
  final String host;
  final String uid;

  const AccountSettings({
    this.schemaVersion = 1,
    required this.host,
    required this.uid,
  });

  factory AccountSettings.defaults(String host, String uid) =>
      AccountSettings(host: host, uid: uid);

  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'host': host,
    'uid': uid,
  };

  factory AccountSettings.fromMap(
    String host,
    String uid,
    Map<String, dynamic> map,
  ) => AccountSettings(
    schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
    host: host,
    uid: uid,
  );
}

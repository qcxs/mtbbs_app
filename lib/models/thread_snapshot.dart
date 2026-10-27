import 'dart:convert';

import 'package:mtbbs/models/thread_detail.dart';

/// 帖子缓存快照结构版本。
///
/// **v1 视为冻结**：后续只允许追加可选字段，不允许重命名、改类型、
/// 改必填性或调整嵌套层级（见 `docs/24-帖子缓存与离线帖子.md` 第 4 节）。
const int kThreadSnapshotSchemaVersion = 1;

/// 每个帖子最多保留的自动缓存正文版本数。
const int kThreadAutoMaxVersions = 3;

/// 导出文件顶层标记。
const String kThreadCacheExportFormat = 'mtbbs.thread_cache';

/// 缓存类型
enum ThreadCacheKind {
  /// 自动缓存（新帖每次成功访问写入，有 TTL）
  auto,

  /// 离线帖子（用户主动保存，永不过期）
  offline;

  static ThreadCacheKind? fromValue(Object? value) {
    final v = value?.toString();
    for (final k in ThreadCacheKind.values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

/// 帖子缓存快照
///
/// 保存一次抓取时的完整内容：楼主帖 + 已加载的评论页。
/// 正文直接存 [PostItem] 的 Map，读取时用 [PostItem.fromMap] 还原，不重新解析 HTML。
class ThreadSnapshot {
  final int schemaVersion;
  final ThreadCacheKind kind;
  final String host;

  /// 自动缓存的账号标识：`uid:<uid>` 或 `guest`；离线为 null
  final String? viewer;

  /// 离线副本的保存者标签（仅展示，不做鉴权）
  final String? savedBy;

  final String tid;
  final String title;

  /// 标题 + 楼主正文的 FNV-1a 64 位哈希
  final String contentHash;

  /// 楼主发布时间原文（如「3 小时前」），仅用于判定/调试
  final String postTimeText;

  /// 抓取时是否被判为新帖
  final bool isNewAtCapture;

  final PostItem mainPost;

  /// 评论页：页码 → 该页评论（不含楼主）
  final Map<int, List<PostItem>> commentPages;

  /// 实际已缓存的页码（升序）
  final List<int> cachedPages;

  /// 抓取时的总页数
  final int totalPages;

  final DateTime createdAt;
  final DateTime? lastVisitedAt;
  final DateTime? expiresAt;
  final DateTime? savedAt;

  /// 按 UTF-8 JSON 长度估算的大小
  final int approxBytes;

  const ThreadSnapshot({
    this.schemaVersion = kThreadSnapshotSchemaVersion,
    required this.kind,
    required this.host,
    this.viewer,
    this.savedBy,
    required this.tid,
    required this.title,
    required this.contentHash,
    this.postTimeText = '',
    this.isNewAtCapture = false,
    required this.mainPost,
    this.commentPages = const {},
    this.cachedPages = const [],
    this.totalPages = 1,
    required this.createdAt,
    this.lastVisitedAt,
    this.expiresAt,
    this.savedAt,
    this.approxBytes = 0,
  });

  bool get isAuto => kind == ThreadCacheKind.auto;
  bool get isOffline => kind == ThreadCacheKind.offline;

  /// 自动缓存存储键：`auto|{host}|{viewer}|{tid}|{contentHash}`
  static String autoKey({
    required String host,
    required String viewer,
    required String tid,
    required String contentHash,
  }) => 'auto|$host|${viewer.isEmpty ? 'guest' : viewer}|$tid|$contentHash';

  /// 离线副本存储键：`offline|{host}|{tid}`
  static String offlineKey({required String host, required String tid}) =>
      'offline|$host|$tid';

  String get storageKey => isAuto
      ? autoKey(
          host: host,
          viewer: viewer ?? 'guest',
          tid: tid,
          contentHash: contentHash,
        )
      : offlineKey(host: host, tid: tid);

  /// 正文摘要（去掉 BBCode 标记后的前 80 字），供管理列表展示
  String get mainSummary {
    var text = mainPost.bbcode
        .replaceAll(RegExp(r'\[appdata\][\s\S]*?\[/appdata\]'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length > 80) text = '${text.substring(0, 80)}…';
    return text;
  }

  /// 转成只读页可用的 [ThreadViewData]
  ThreadViewData toViewData({int page = 1}) => ThreadViewData(
    tid: tid,
    title: title,
    currentPage: page,
    totalPages: totalPages,
    mainPost: mainPost,
    posts: List<PostItem>.from(commentPages[page] ?? const []),
  );

  Map<String, dynamic> toMap({bool includeApproxBytes = true}) => {
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'host': host,
    'viewer': viewer,
    'savedBy': savedBy,
    'tid': tid,
    'title': title,
    'contentHash': contentHash,
    'postTimeText': postTimeText,
    'isNewAtCapture': isNewAtCapture,
    'mainPost': mainPost.toMap(),
    'commentPages': {
      for (final e in commentPages.entries)
        e.key.toString(): [for (final p in e.value) p.toMap()],
    },
    'cachedPages': cachedPages,
    'totalPages': totalPages,
    'createdAt': createdAt.toIso8601String(),
    'lastVisitedAt': lastVisitedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'savedAt': savedAt?.toIso8601String(),
    if (includeApproxBytes) 'approxBytes': approxBytes,
  };

  /// 从持久化/导入的 Map 还原
  ///
  /// 核心字段缺失或结构版本不支持时抛 [FormatException]，由调用方按「单条损坏」
  /// 跳过处理，不影响其他记录。
  factory ThreadSnapshot.fromMap(Map<String, dynamic> map) {
    final version =
        (map['schemaVersion'] as num?)?.toInt() ??
        kThreadSnapshotSchemaVersion;
    if (version != kThreadSnapshotSchemaVersion) {
      throw FormatException('unsupported schemaVersion: $version');
    }
    final kind = ThreadCacheKind.fromValue(map['kind']);
    if (kind == null) throw FormatException('invalid kind: ${map['kind']}');
    final host = map['host']?.toString() ?? '';
    if (host.isEmpty) throw const FormatException('missing host');
    final tid = map['tid']?.toString() ?? '';
    if (tid.isEmpty) throw const FormatException('missing tid');
    final rawMain = map['mainPost'];
    if (rawMain is! Map) throw const FormatException('missing mainPost');

    final pages = <int, List<PostItem>>{};
    final rawPages = map['commentPages'];
    if (rawPages is Map) {
      for (final entry in rawPages.entries) {
        final page = int.tryParse(entry.key.toString());
        final list = entry.value;
        if (page == null || page < 1 || list is! List) continue;
        pages[page] = [
          for (final p in list)
            if (p is Map) PostItem.fromMap(Map<String, dynamic>.from(p)),
        ];
      }
    }

    final storedPages = (map['cachedPages'] as List<dynamic>?)
        ?.map((e) => int.tryParse(e.toString()))
        .whereType<int>()
        .where(pages.containsKey)
        .toList();
    final cached = storedPages != null && storedPages.isNotEmpty
        ? (storedPages..sort())
        : (pages.keys.toList()..sort());

    final rawBytes = (map['approxBytes'] as num?)?.toInt() ?? 0;

    final snapshot = ThreadSnapshot(
      schemaVersion: version,
      kind: kind,
      host: host,
      viewer: map['viewer']?.toString(),
      savedBy: map['savedBy']?.toString(),
      tid: tid,
      title: map['title']?.toString() ?? '',
      contentHash: map['contentHash']?.toString() ?? '',
      postTimeText: map['postTimeText']?.toString() ?? '',
      isNewAtCapture: map['isNewAtCapture'] == true,
      mainPost: PostItem.fromMap(Map<String, dynamic>.from(rawMain)),
      commentPages: pages,
      cachedPages: cached,
      totalPages: (map['totalPages'] as num?)?.toInt() ?? 1,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastVisitedAt: _parseDate(map['lastVisitedAt']),
      expiresAt: _parseDate(map['expiresAt']),
      savedAt: _parseDate(map['savedAt']),
      approxBytes: rawBytes,
    );
    return snapshot.approxBytes > 0 ? snapshot : snapshot.recomputeBytes();
  }

  /// 更新评论页并重算大小
  ThreadSnapshot withCommentPage(int page, List<PostItem> posts) {
    final pages = <int, List<PostItem>>{
      for (final e in commentPages.entries) e.key: List<PostItem>.from(e.value),
    };
    pages[page] = List<PostItem>.from(posts);
    final cached = pages.keys.toList()..sort();
    final updated = copyWith(commentPages: pages, cachedPages: cached);
    return updated.recomputeBytes();
  }

  ThreadSnapshot copyWith({
    String? title,
    String? contentHash,
    String? viewer,
    String? savedBy,
    PostItem? mainPost,
    Map<int, List<PostItem>>? commentPages,
    List<int>? cachedPages,
    int? totalPages,
    DateTime? createdAt,
    DateTime? lastVisitedAt,
    DateTime? expiresAt,
    DateTime? savedAt,
    int? approxBytes,
  }) => ThreadSnapshot(
    schemaVersion: schemaVersion,
    kind: kind,
    host: host,
    viewer: viewer ?? this.viewer,
    savedBy: savedBy ?? this.savedBy,
    tid: tid,
    title: title ?? this.title,
    contentHash: contentHash ?? this.contentHash,
    postTimeText: postTimeText,
    isNewAtCapture: isNewAtCapture,
    mainPost: mainPost ?? this.mainPost,
    commentPages: commentPages ?? this.commentPages,
    cachedPages: cachedPages ?? this.cachedPages,
    totalPages: totalPages ?? this.totalPages,
    createdAt: createdAt ?? this.createdAt,
    lastVisitedAt: lastVisitedAt ?? this.lastVisitedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    savedAt: savedAt ?? this.savedAt,
    approxBytes: approxBytes ?? this.approxBytes,
  );

  /// 按 UTF-8 JSON 长度重算 [approxBytes]（不包含自身字段）
  ThreadSnapshot recomputeBytes() => copyWith(approxBytes: estimateBytes());

  int estimateBytes() => utf8
      .encode(jsonEncode(toMap(includeApproxBytes: false)))
      .length;

  /// 轻量索引
  ThreadSnapshotMeta toMeta() => ThreadSnapshotMeta(
    key: storageKey,
    schemaVersion: schemaVersion,
    kind: kind,
    host: host,
    viewer: viewer,
    savedBy: savedBy,
    tid: tid,
    title: title,
    contentHash: contentHash,
    postTimeText: postTimeText,
    isNewAtCapture: isNewAtCapture,
    summary: mainSummary,
    cachedPages: cachedPages,
    totalPages: totalPages,
    createdAt: createdAt,
    lastVisitedAt: lastVisitedAt,
    expiresAt: expiresAt,
    savedAt: savedAt,
    approxBytes: approxBytes,
  );

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

/// 帖子缓存轻量索引
///
/// 管理页、过期清理、版本裁剪只需读它，不必把大段 BBCode 载入内存。
class ThreadSnapshotMeta {
  final String key;
  final int schemaVersion;
  final ThreadCacheKind kind;
  final String host;
  final String? viewer;
  final String? savedBy;
  final String tid;
  final String title;
  final String contentHash;
  final String postTimeText;
  final bool isNewAtCapture;
  final String summary;
  final List<int> cachedPages;
  final int totalPages;
  final DateTime createdAt;
  final DateTime? lastVisitedAt;
  final DateTime? expiresAt;
  final DateTime? savedAt;
  final int approxBytes;

  const ThreadSnapshotMeta({
    required this.key,
    this.schemaVersion = kThreadSnapshotSchemaVersion,
    required this.kind,
    required this.host,
    this.viewer,
    this.savedBy,
    required this.tid,
    required this.title,
    required this.contentHash,
    this.postTimeText = '',
    this.isNewAtCapture = false,
    this.summary = '',
    this.cachedPages = const [],
    this.totalPages = 1,
    required this.createdAt,
    this.lastVisitedAt,
    this.expiresAt,
    this.savedAt,
    this.approxBytes = 0,
  });

  bool get isAuto => kind == ThreadCacheKind.auto;
  bool get isOffline => kind == ThreadCacheKind.offline;

  /// 自动缓存同一帖子的分组标识（不含 contentHash）
  String get threadGroupKey => '$host|${viewer ?? 'guest'}|$tid';

  /// 离线副本标识
  String get offlineGroupKey => '$host|$tid';

  DateTime get sortTime =>
      (isOffline ? savedAt : lastVisitedAt) ?? createdAt;

  bool isExpiredAt(DateTime now) =>
      isAuto && expiresAt != null && expiresAt!.isBefore(now);

  Map<String, dynamic> toMap() => {
    'key': key,
    'schemaVersion': schemaVersion,
    'kind': kind.name,
    'host': host,
    'viewer': viewer,
    'savedBy': savedBy,
    'tid': tid,
    'title': title,
    'contentHash': contentHash,
    'postTimeText': postTimeText,
    'isNewAtCapture': isNewAtCapture,
    'summary': summary,
    'cachedPages': cachedPages,
    'totalPages': totalPages,
    'createdAt': createdAt.toIso8601String(),
    'lastVisitedAt': lastVisitedAt?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'savedAt': savedAt?.toIso8601String(),
    'approxBytes': approxBytes,
  };

  /// 宽松解析：损坏记录返回 null，由调用方跳过
  static ThreadSnapshotMeta? tryFromMap(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final kind = ThreadCacheKind.fromValue(map['kind']);
    final key = map['key']?.toString();
    final host = map['host']?.toString() ?? '';
    final tid = map['tid']?.toString() ?? '';
    if (kind == null || key == null || key.isEmpty) return null;
    if (host.isEmpty || tid.isEmpty) return null;
    return ThreadSnapshotMeta(
      key: key,
      schemaVersion:
          (map['schemaVersion'] as num?)?.toInt() ??
          kThreadSnapshotSchemaVersion,
      kind: kind,
      host: host,
      viewer: map['viewer']?.toString(),
      savedBy: map['savedBy']?.toString(),
      tid: tid,
      title: map['title']?.toString() ?? '',
      contentHash: map['contentHash']?.toString() ?? '',
      postTimeText: map['postTimeText']?.toString() ?? '',
      isNewAtCapture: map['isNewAtCapture'] == true,
      summary: map['summary']?.toString() ?? '',
      cachedPages:
          (map['cachedPages'] as List<dynamic>?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          const [],
      totalPages: (map['totalPages'] as num?)?.toInt() ?? 1,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      lastVisitedAt: ThreadSnapshot._parseDate(map['lastVisitedAt']),
      expiresAt: ThreadSnapshot._parseDate(map['expiresAt']),
      savedAt: ThreadSnapshot._parseDate(map['savedAt']),
      approxBytes: (map['approxBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

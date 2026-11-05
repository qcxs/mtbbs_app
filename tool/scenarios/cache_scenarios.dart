/// 本地帖子缓存场景：只读快照，不访问网络
///
/// 用途有两个：
/// 1. 离线验证「缓存快照 → MCP payload」的字段是否仍然对得上；
/// 2. 给 AI 一个不受站点风控 / 验证码影响的快速夹具。
library;

import 'package:mtbbs/core/app/site_store.dart';
import 'package:mtbbs/models/thread_snapshot.dart';
import 'package:mtbbs/services/thread_cache_service.dart';
import 'scenario_types.dart';

final Map<String, ApiScenario> cacheScenarios = {
  'cache.list': ApiScenario(
    desc: '列出当前站点本机的帖子缓存索引（自动缓存 + 离线保存），不发请求',
    params: {
      'kind': 'auto|offline（默认 auto）',
      'limit': '返回条数（默认 10，最多 50）',
    },
    run: (a) async {
      final service = ThreadCacheService.instance;
      final host = SiteStore.instance.host;
      if (service.isDisabled) {
        return {
          'disabled': true,
          'host': host,
          'items': const [],
          'message': '帖子缓存库损坏或不可用，App 内可在缓存管理页修复/重建',
        };
      }
      final kind = (a['kind'] ?? 'auto').toLowerCase();
      final limit = intArg(a, 'limit', 10).clamp(1, 50);
      final all = kind == 'offline'
          ? await service.listOffline()
          : await service.listAuto();
      final items = all.where((m) => m.host == host).toList()
        ..sort(_newestFirst);
      return {
        'disabled': false,
        'host': host,
        'kind': kind == 'offline' ? 'offline' : 'auto',
        'total': items.length,
        'items': [for (final m in items.take(limit)) _brief(m)],
      };
    },
  ),
  'cache.thread': ApiScenario(
    desc: '读取某帖的本地缓存快照（不发 HTTP；用于验证缓存内容与页码完整性）',
    params: {
      'tid': '*帖子 ID',
      'page': '页码（默认 1）',
      'kind': 'auto|offline（默认先看离线，再 auto）',
    },
    run: (a) async {
      final service = ThreadCacheService.instance;
      final host = SiteStore.instance.host;
      final tid = (a['tid'] ?? '').trim();
      if (tid.isEmpty) {
        return {'success': false, 'message': '缺少必填参数 tid'};
      }
      if (service.isDisabled) {
        return {'success': false, 'disabled': true, 'message': '帖子缓存库不可用'};
      }
      final kind = (a['kind'] ?? '').toLowerCase();
      final page = intArg(a, 'page', 1);
      final metas = <ThreadSnapshotMeta>[
        if (kind != 'auto') ...await service.listOffline(),
        if (kind != 'offline') ...await service.listAuto(),
      ].where((m) => m.host == host && m.tid == tid).toList()
        ..sort(_newestFirst);
      if (metas.isEmpty) {
        return {
          'success': false,
          'hit': false,
          'tid': tid,
          'message': '该帖在本机没有缓存；先在 App 内访问或离线保存',
        };
      }
      final meta = metas.first;
      final snapshot = await service.readSnapshot(meta.key);
      if (snapshot == null) {
        return {
          'success': false,
          'hit': false,
          'tid': tid,
          'message': '缓存索引存在但正文读取失败（可能已被清理或损坏）',
          'meta': _brief(meta),
        };
      }
      final posts = snapshot.commentPages[page];
      return {
        'success': true,
        'hit': true,
        'tid': tid,
        'page': page,
        'title': snapshot.title,
        'totalPages': snapshot.totalPages,
        'cachedPages': meta.cachedPages,
        'pageComments': posts?.length ?? 0,
        'mainPostChars': snapshot.mainPost.bbcode.length,
        'stale': meta.isExpiredAt(DateTime.now()),
        'meta': _brief(meta),
      };
    },
  ),
};

int _newestFirst(ThreadSnapshotMeta a, ThreadSnapshotMeta b) {
  final at = a.lastVisitedAt ?? a.createdAt;
  final bt = b.lastVisitedAt ?? b.createdAt;
  return bt.compareTo(at);
}

Map<String, dynamic> _brief(ThreadSnapshotMeta m) => {
  'key': m.key,
  'kind': m.kind.name,
  'tid': m.tid,
  'title': m.title,
  if (m.viewer != null) 'viewer': m.viewer,
  'cachedPages': m.cachedPages,
  'totalPages': m.totalPages,
  'approxBytes': m.approxBytes,
  'createdAt': m.createdAt.toIso8601String(),
  if (m.lastVisitedAt != null)
    'lastVisitedAt': m.lastVisitedAt!.toIso8601String(),
  if (m.expiresAt != null) 'expiresAt': m.expiresAt!.toIso8601String(),
  if (m.savedAt != null) 'savedAt': m.savedAt!.toIso8601String(),
};

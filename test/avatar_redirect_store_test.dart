import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/core/app/avatar_redirect_store.dart';

/// 内存后端：模拟 sembast 记录级存储，不依赖磁盘路径
class _MemoryBackend implements AvatarRedirectBackend {
  final Map<String, Map<String, Object?>> data = {};
  final List<String> deleted = [];

  @override
  Future<Map<String, Map<String, Object?>>> getAll() async =>
      Map<String, Map<String, Object?>>.from(data);

  @override
  Future<void> put(String url, String? finalUrl, DateTime updatedAt) async {
    data[url] = {
      'final': finalUrl,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  @override
  Future<void> delete(List<String> urls) async {
    deleted.addAll(urls);
    for (final u in urls) {
      data.remove(u);
    }
  }
}

void main() {
  late _MemoryBackend backend;
  late AvatarRedirectStore store;

  setUp(() {
    backend = _MemoryBackend();
    store = AvatarRedirectStore.instance;
    store.debugReset();
    store.backend = backend;
  });

  const url = 'https://a.example/uc_server/avatar.php?uid=1&size=middle';

  test('无重定向时归一为 null 存储，lookup 返回原始 URL', () async {
    store.set(url, url); // finalUrl == url → 无重定向
    final r = store.lookup(url);
    expect(r.known, isTrue);
    expect(r.value, url);
    await store.debugFlush();
    expect(backend.data[url]!['final'], isNull); // 不冗余存完整 URL
  });

  test('有重定向时存储并返回最终 URL', () async {
    const finalUrl = 'https://cdn.example/1_avatar_middle.jpg';
    store.set(url, finalUrl);
    final r = store.lookup(url);
    expect(r.known, isTrue);
    expect(r.value, finalUrl);
    await store.debugFlush();
    expect(backend.data[url]!['final'], finalUrl);
  });

  test('TTL 内 known；超时视为未知并清理', () async {
    store.cacheTtl = const Duration(days: 7);
    store.set(url, 'https://cdn.example/x.jpg');
    expect(store.lookup(url).known, isTrue);

    // 模拟 8 天后查询 → 过期视为未知，并触发删除
    store.debugSetUpdatedAt(
      url,
      DateTime.now().subtract(const Duration(days: 8)),
    );
    expect(store.lookup(url).known, isFalse);
    await store.debugFlush();
    expect(backend.deleted, contains(url));
  });

  test('TTL 为 null 或负数时永不过期', () {
    store.cacheTtl = null;
    store.debugSetUpdatedAt(url, DateTime(2000));
    expect(store.lookup(url).known, isFalse); // 未 set 过 → unknown

    store.set(url, 'https://cdn.example/x.jpg');
    store.cacheTtl = const Duration(days: -1); // 与头像缓存 -1 语义一致
    store.debugSetUpdatedAt(url, DateTime(2000));
    expect(store.lookup(url).known, isTrue); // 永不过期
  });

  test('加载时惰性跳过过期记录', () async {
    backend.data[url] = {
      'final': 'https://cdn.example/x.jpg',
      'updatedAt': DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch,
    };
    store.cacheTtl = const Duration(days: 7);
    await store.loadIfNeeded();
    expect(store.lookup(url).known, isFalse);
    await store.debugFlush();
    expect(backend.deleted, contains(url));
  });

  test('旧格式（整体 JSON）迁移为新格式并删除旧记录', () async {
    backend.data['redirects'] = {
      'value':
          '{"https://a.example/avatar.php?uid=2&size=small":"https://cdn/2.jpg",'
          '"https://a.example/avatar.php?uid=3&size=big":null}',
    };
    await store.loadIfNeeded();

    expect(
      store.lookup('https://a.example/avatar.php?uid=2&size=small').value,
      'https://cdn/2.jpg',
    );
    // null（历史无重定向）归一为原始 URL
    expect(
      store.lookup('https://a.example/avatar.php?uid=3&size=big').value,
      'https://a.example/avatar.php?uid=3&size=big',
    );
    await store.debugFlush();
    expect(backend.data.containsKey('redirects'), isFalse); // 旧记录已删
    expect(
      backend.data.containsKey('https://a.example/avatar.php?uid=2&size=small'),
      isTrue,
    );
  });

  test('超容量上限时淘汰最久未更新的记录', () async {
    store.maxEntries = 2;
    final now = DateTime.now();
    backend.data['https://a.example/u1'] = {
      'final': null,
      'updatedAt': now
          .subtract(const Duration(days: 10))
          .millisecondsSinceEpoch,
    };
    backend.data['https://a.example/u2'] = {
      'final': null,
      'updatedAt': now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
    };
    backend.data['https://a.example/u3'] = {
      'final': null,
      'updatedAt': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    };
    await store.loadIfNeeded();

    expect(store.lookup('https://a.example/u1').known, isFalse); // 最旧被淘汰
    expect(store.lookup('https://a.example/u2').known, isTrue);
    expect(store.lookup('https://a.example/u3').known, isTrue);
    await store.debugFlush();
    expect(backend.deleted, contains('https://a.example/u1'));
  });
}

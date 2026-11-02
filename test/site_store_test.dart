import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/config/site_config.dart';
import 'package:mtbbs/core/app/site_store.dart';

Site _site(
  String name,
  String baseUrl, {
  Map<String, String> forums = const {},
  List<String> order = const [],
}) => Site(
  name: name,
  baseUrl: baseUrl,
  loginPagePath: '/member.php?mod=logging&action=login',
  forums: forums,
  defaultForumOrder: order,
);

void main() {
  final store = SiteStore.instance;

  setUp(() => store.init());

  test('replaceSites 更新版块并通知监听者', () {
    var notified = 0;
    void listener() => notified++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));

    store.replaceSites([
      _site(
        'MT论坛',
        'https://bbs.binmt.cc',
        forums: {'41': '综合交流', '42': '技术分享'},
        order: ['41', '42'],
      ),
    ]);

    expect(store.forums['41'], '综合交流');
    expect(store.defaultForumOrder, ['41', '42']);
    expect(notified, greaterThan(0), reason: '版块变化必须通知 UI 重建');
  });

  test('switchTo 更新当前站点并通知监听者', () {
    store.replaceSites([
      _site('A', 'https://a.example.com'),
      _site('B', 'https://b.example.com'),
    ]);

    var notified = 0;
    void listener() => notified++;
    store.addListener(listener);
    addTearDown(() => store.removeListener(listener));

    store.switchTo(1);

    expect(store.host, 'b.example.com');
    expect(notified, greaterThan(0));
  });
}

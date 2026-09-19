import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/pages/settings/about_page.dart';

/// 关于页的应用图标是 `mipmap-xxxhdpi/ic_launcher.png` 的副本，路径写错只会在
/// 运行期报 "Unable to load asset"，编译期发现不了；图标本身坏了也只是显示空白。
/// 这里守住"asset 已声明 + 路径与页面用的是同一个常量"。
///
/// 图标点击旋转是纯装饰，不写用例（同 `special_thanks_test.dart` 只守资产的取舍）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('关于页应用图标能加载', () async {
    final data = await rootBundle.load(AboutPage.iconAsset);
    expect(data.lengthInBytes, greaterThan(0), reason: '为空说明 asset 未声明或路径不对');
  });
}

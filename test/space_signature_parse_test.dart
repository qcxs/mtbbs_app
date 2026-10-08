import 'package:flutter_test/flutter_test.dart';
import 'package:mtbbs/api/home/space/parse.dart' as space_parse;
import 'package:mtbbs/core/app/site_store.dart';

/// 克米移动模板个人空间「个人签名」解析回归。
///
/// 真实 DOM（来自 bbs.binmt.cc 移动端抓取）的特征是**值在前、标签在后**，
/// 且标签的包裹层级逐行不同：
///   - 用户ID：`<li><div class="profile_rs">14330</div><span>用户ID</span></li>`
///   - 个人签名：`<li>…<strong><font><span>个人签名</span></font></strong></li>`
///   - 自定头衔：`<li><a><div class="profile_r">…</div><span>自定头衔</span></a></li>`
/// 早期的 `_comiisRowValue` 只看 `span.parent`，取不到作为兄弟节点的值，导致签名丢失。
void main() {
  setUpAll(() {
    SiteStore.instance.init();
  });

  /// 组装克米移动端个人空间页（`.comiis_space_info` 触发移动分支）
  String pageWith(List<String> rows) {
    return '''
<html><body class="pg_space">
<div class="comiis_space_info"><h2>喵喵猫</h2></div>
<div class="comiis_space_profile">
<ul>
${rows.join('\n')}
</ul>
</div>
</body></html>
''';
  }

  /// 签名行（值在前，标签被 <strong><font> 包裹）
  String signatureRow(String valueHtml) {
    return '<li class="b_t"><div class="profile_r profile_face f_c">$valueHtml'
        '</div><strong><font color="white"><span>个人签名</span></font></strong></li>';
  }

  Map<String, dynamic> parseProfile(List<String> rows) {
    final resp = space_parse.parseResponse(pageWith(rows), 200);
    expect(resp['success'], true);
    return (resp['profile'] as Map).cast<String, dynamic>();
  }

  test('图片签名：img 转 [img]', () {
    final profile = parseProfile([
      signatureRow(
        '<img src="https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif" border="0" alt="">',
      ),
    ]);
    expect(
      profile['signature'],
      '[img]https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif[/img]',
    );
  });

  test('用户用未闭合 [b][color] 染页：原样保留，不当垃圾清理', () {
    // 喵喵猫的签名是 `[img]…[/img]` 后跟**未闭合**的 `[b][color=white]`（签名染页手法）。
    // `$sightml` 原样输出，HTML 解析器在 `</div>` 处把开标签补成空对，于是得到
    // `<strong><font color="white"></font></strong>`。这是**用户有意为之**的内容，
    // 不是模板注入（另一用户 uid=88062 的同一行没有它），因此不做清理。
    final profile = parseProfile([
      signatureRow(
        '<img src="https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif" border="0" alt="">'
        '<strong><font color="white"></font></strong>',
      ),
    ]);
    expect(
      profile['signature'],
      '[img]https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif[/img]'
      '[b][color=white][/color][/b]',
    );
  });

  test('文字签名', () {
    final profile = parseProfile([signatureRow('签名文字')]);
    expect(profile['signature'], '签名文字');
  });

  test('链接签名：a 转 [url]', () {
    final profile = parseProfile([
      signatureRow('<a href="https://example.com" target="_blank">点我</a>'),
    ]);
    expect(profile['signature'], '[url=https://example.com]点我[/url]');
  });

  test('同页其他行不受影响（用户ID / 自定头衔）', () {
    final profile = parseProfile([
      '<li class="b_t"><div class="profile_rs f_c">14330</div><span>用户ID</span></li>',
      signatureRow('文字'),
      '<li class="b_t"><a href="/x" class="profile_a">'
          '<div class="profile_r profile_face f_c">喵喵，喵~</div>'
          '<span>自定头衔</span></a></li>',
    ]);
    expect(profile['uid'], '14330');
    expect(profile['customTitle'], '喵喵，喵~');
  });

  // ==================== PC（标准 Discuz）模板 ====================
  //
  // 结构取自 Discuz `template/default/home/space_profile_body.htm`，并用站点真实
  // PC 页面（Cookie 强制 `*_mobile=no`）核对过：
  //   `<li><em class="xg1">个人签名&nbsp;&nbsp;</em><table><tr><td>$sightml</td></tr></table></li>`
  // 注意签名 HTML（`sightml`）是**保存时**由 `discuzcode()` 渲染并入库的，PC/移动
  // 两端拿到的**是同一份**，所以两端解析出的 BBCode 应完全一致。

  /// 组装 PC 个人空间页（无 `.comiis_space_info` → 走标准 Discuz 分支）
  String pcPage(String signatureHtml) {
    return '''
<html><body id="nv_profile">
<div id="ct"><div class="mn"><div class="bm bw0"><div class="bm_c">
<div class="bm_c u_profile">
<h2 class="mbn">喵喵猫<span class="xw0">(UID: 14330)</span></h2>
<ul class="pf_l cl pbm mbm"><li><em>邮箱状态</em>已验证</li></ul>
<ul>
<li class="xg1"><em>自定义头衔&nbsp;&nbsp;</em>喵喵，喵~</li>
<li><em class="xg1">个人签名&nbsp;&nbsp;</em><table><tr><td>$signatureHtml</td></tr></table></li>
</ul>
</div></div></div></div>
</body></html>
''';
  }

  Map<String, dynamic> parsePcProfile(String signatureHtml) {
    final resp = space_parse.parseResponse(pcPage(signatureHtml), 200);
    expect(resp['success'], true);
    return (resp['profile'] as Map).cast<String, dynamic>();
  }

  test('PC 模板：图片签名 + 未闭合染页标签（与移动端同一份 sightml）', () {
    final profile = parsePcProfile(
      '<img src="https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif" border="0" alt="" />'
      '<strong><font color="white">',
    );
    expect(
      profile['signature'],
      '[img]https://ftp.bmp.ovh/imgs/2020/03/038b5fb1c560f724.gif[/img]'
      '[b][color=white][/color][/b]',
    );
  });

  test('PC 模板：文字签名 + 自定头衔', () {
    final profile = parsePcProfile('年少不知号贵，猥琐升级，勿浪！');
    expect(profile['signature'], '年少不知号贵，猥琐升级，勿浪！');
    expect(profile['customTitle'], '喵喵，喵~');
  });
}

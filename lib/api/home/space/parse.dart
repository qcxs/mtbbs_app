import 'package:html/dom.dart' as dom;
import 'package:mtbbs/api/helpers.dart';
import 'package:mtbbs/core/parser/html2bbcode.dart';
import 'package:mtbbs/core/app/page_helper.dart';
import 'package:mtbbs/core/utils/logger.dart';

/// 用户空间个人资料响应解析
///
/// 支持两套模板（由请求 UA 决定，见 http.dart）：
/// - **克米移动模板**：`body.pg_space` / `.comiis_space_info`（含关注/粉丝/人气）
/// - **标准 Discuz PC 模板**：`#uhd` / `.u_profile` / `#pbbs` / `#psts`
///
/// 两套结构差异较大，这里按 DOM 特征分流，输出统一的 profile 结构，
/// 由渲染层按字段是否存在条件渲染。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  final pre = prepareDoc(body, statusCode);
  if (pre.error != null) return pre.error!;
  final doc = pre.doc!;

  final profile = <String, dynamic>{};

  // 按模板分流：克米移动 ↔ 标准 Discuz PC
  if (doc.querySelector('.comiis_space_info') != null) {
    _parseComiisProfile(doc, profile);
  } else {
    // 标准解析（#uhd + .u_profile）
    _parseHeader(doc, profile);
    _parseProfileSection(doc, profile);

    // 如果标准解析没拿到昵称，尝试从 h2 直接提取（部分模板）
    if ((profile['nickname'] == null || profile['nickname'] == '') &&
        profile['uid'] != null) {
      _parseNicknameFallback(doc, profile);
    }

    _parseActivitySection(doc, profile);
    _parseStatsSection(doc, profile);
  }

  // 必要内容校验：昵称和 uid 都没有，且页面上无用户内容 DOM → 判定无效
  if ((profile['nickname'] == null || profile['nickname'] == '') &&
      (profile['uid'] == null || profile['uid'] == '')) {
    final hasUserContent =
        doc.querySelector('#uhd, .u_profile, .comiis_space_info') != null;
    if (!hasUserContent) {
      AppLogger.w('PARSE', 'space: no user content');
      return {'success': false, 'message': '页面不可用或用户不存在'};
    }
  }

  return {'success': true, 'profile': profile};
}

/// 解析克米移动模板（`body.pg_space` 下的 `.comiis_space_info`）
///
/// 移动模板独有：关注数 / 粉丝数 / 人气 / 等级（Lv.x）；资料、统计、积分的
/// 标签名与 PC 不同（如「帖子/回复」对应 PC 的「主题/回帖」）。
void _parseComiisProfile(dom.Document doc, Map<String, dynamic> profile) {
  // --- 头像 / 昵称 ---
  final avatarImg = doc.querySelector('.comiis_space_info .user_img img');
  if (avatarImg != null) profile['avatar'] = avatarImg.attributes['src'];

  final nameEl = doc.querySelector('.comiis_space_info h2');
  if (nameEl != null) {
    final name = sanitizeText(nameEl.text);
    if (name.isNotEmpty) profile['nickname'] = name;
  }

  // --- 信息行：人气 / 关注 / 粉丝 ---
  for (final span in doc.querySelectorAll(
    '.comiis_space_info .comiis_space_tx > p > span',
  )) {
    final text = sanitizeText(span.text);
    final m = RegExp(r'([\d,]+)\s*(人气|关注|粉丝)').firstMatch(text);
    if (m == null) continue;
    final num = m.group(1)!.replaceAll(',', '');
    switch (m.group(2)) {
      case '人气':
        profile['popularity'] = num;
        break;
      case '关注':
        profile['following'] = num;
        break;
      case '粉丝':
        profile['followers'] = num;
        break;
    }
  }

  // --- 等级 + 用户组（PC 无等级，移动有 Lv.x）---
  final levelEl = doc.querySelector('.comiis_space_tx .kmlevs.bg_0');
  if (levelEl != null) {
    final lv = sanitizeText(levelEl.text);
    if (lv.isNotEmpty) profile['level'] = lv;
  }
  final activity = <String, dynamic>{};
  final groupEl = doc.querySelector('.comiis_space_tx .kmlev');
  if (groupEl != null) {
    final group = sanitizeText(groupEl.text);
    if (group.isNotEmpty) activity['userGroup'] = group;
  }

  // --- 勋章（swiper 内 img[alt]，alt 即勋章名）---
  final medalImgs = doc.querySelectorAll('#comiis_medal img[alt]');
  final medals = medalImgs
      .map(
        (img) => {
          'name': img.attributes['alt'] ?? '',
          'icon': img.attributes['src'] ?? '',
        },
      )
      .where((m) => (m['name'] as String).isNotEmpty)
      .toList();
  if (medals.isNotEmpty) profile['medals'] = medals;

  // --- 个性签名（HTML → BBCode）---
  final sigEl = _comiisRowValue(doc, '个人签名');
  if (sigEl != null) {
    final bbcode = Html2BBCode().convertElementContent(sigEl);
    if (bbcode.isNotEmpty) profile['signature'] = bbcode;
  }

  // --- 自定义头衔（值同样落在 .profile_r，故按标签文案定位）---
  final titleEl = _comiisRowValue(doc, '自定头衔');
  if (titleEl != null) {
    final title = sanitizeText(titleEl.text);
    if (title.isNotEmpty) profile['customTitle'] = title;
  }

  // --- 详细资料 / 活跃（li：div.profile_rs 为值，span 为标签）---
  final details = <String, dynamic>{};
  for (final li in doc.querySelectorAll('.comiis_space_profile li')) {
    final labelEl = li.querySelector('span');
    final valueEl = li.querySelector('.profile_rs');
    if (labelEl == null || valueEl == null) continue;
    final label = sanitizeText(labelEl.text);
    final value = sanitizeText(valueEl.text);
    if (value.isEmpty) continue;
    switch (label) {
      case '用户ID':
        profile['uid'] = value;
        break;
      case 'QQ':
        details['qq'] = value;
        break;
      case '职业':
        details['occupation'] = value;
        break;
      case '居住地':
        details['residence'] = value;
        break;
      case '真实姓名':
        details['realName'] = value;
        break;
      case '出生地':
        details['birthplace'] = value;
        break;
      case '生日':
        details['birthday'] = value;
        break;
      case '性别':
        details['gender'] = value;
        break;
      case '在线时间':
        activity['onlineTime'] = value;
        break;
      case '注册时间':
        activity['registerTime'] = value;
        break;
      case '最后访问':
        activity['lastVisit'] = value;
        break;
    }
  }
  if (details.isNotEmpty) profile['details'] = details;
  if (activity.isNotEmpty) profile['activity'] = activity;

  // --- 统计行（帖子 / 回复 / 好友 / 粉丝 / 人气）---
  final stats = <String, dynamic>{};
  for (final span in doc.querySelectorAll(
    '.comiis_space_profileico li a span',
  )) {
    final text = sanitizeText(span.text);
    final m = RegExp(r'^(帖子|回复|好友|粉丝|人气)\s*([\d,]+)$').firstMatch(text);
    if (m == null) continue;
    final num = m.group(2)!.replaceAll(',', '');
    switch (m.group(1)) {
      case '帖子':
        stats['threads'] = num;
        break;
      case '回复':
        stats['replies'] = num;
        break;
      case '好友':
        stats['friends'] = num;
        break;
      case '粉丝':
        stats['followers'] = num;
        break;
      case '人气':
        stats['popularity'] = num;
        break;
    }
  }
  if (stats.isNotEmpty) profile['stats'] = stats;

  // --- 积分行（积分 / 好评 / 金币 / 信誉；li 的裸文本为标签，span 为值）---
  final points = <String, dynamic>{};
  for (final li in doc.querySelectorAll('.comiis_space_profilejf li')) {
    final valueEl = li.querySelector('span');
    if (valueEl == null) continue;
    final value = sanitizeText(valueEl.text);
    final clone = li.clone(true);
    clone.querySelector('span')?.remove();
    final label = sanitizeText(clone.text);
    if (label.isEmpty || value.isEmpty) continue;
    switch (label) {
      case '积分':
        points['credits'] = value.replaceAll(',', '');
        break;
      case '好评':
        points['reputation'] = value;
        break;
      case '金币':
        points['goldCoins'] = value;
        break;
      case '信誉':
        points['credit'] = value;
        break;
    }
  }
  if (points.isNotEmpty) profile['points'] = points;
}

/// 按标签文案定位克米资料行，返回其值元素（`.profile_r` 或 `.profile_rs`）。
///
/// 签名行与自定义头衔行的值都用 `.profile_r`（同为 `profile_face` 类），
/// 只靠类名区分不开，必须按行内 `span` 的标签文案定位。
dom.Element? _comiisRowValue(dom.Document doc, String label) {
  for (final span in doc.querySelectorAll('.comiis_space_profile li span')) {
    if (sanitizeText(span.text) == label) {
      return span.parent?.querySelector('.profile_r, .profile_rs');
    }
  }
  return null;
}

/// 解析头部区域：#uhd 中的头像、昵称、空间链接
void _parseHeader(dom.Document doc, Map<String, dynamic> profile) {
  // 头像
  final avatarImg = doc.querySelector('#uhd .avt img');
  if (avatarImg != null) {
    profile['avatar'] = avatarImg.attributes['src'];
  }

  // 空间链接
  final spaceLink = doc.querySelector('#uhd .h p a');
  if (spaceLink != null) {
    profile['spaceUrl'] = sanitizeText(spaceLink.text);
  }

  // 在线状态
  final onlineImg = doc.querySelector('#ct h2 img[alt="online"]');
  profile['online'] = onlineImg != null;
}

/// 兜底：从页面 h2（非标题栏）中提取昵称
/// 部分模板的 .u_profile 区域不可用，但 h2 直接包含用户名
void _parseNicknameFallback(dom.Document doc, Map<String, dynamic> profile) {
  final excludedTexts = {
    'Ta 的空间',
    '选择您要发布的东东...',
    '活跃概况',
    '统计信息',
    '勋章',
    '个人签名',
  };
  for (final h2 in doc.querySelectorAll('h2')) {
    final text = sanitizeText(h2.text);
    if (text.isEmpty || excludedTexts.contains(text)) continue;
    // 跳过包含 emoji 或特殊图标的
    if (text.contains('') || text.contains('')) continue;
    // 嵌套在头部导航区域的跳过
    final parent = h2.parent;
    if (parent != null && parent.className.contains('comiis_head')) continue;
    profile['nickname'] = text;
    break;
  }
}

/// 解析 .u_profile 区域中的基本信息和详细资料
void _parseProfileSection(dom.Document doc, Map<String, dynamic> profile) {
  final profileBox = doc.querySelector('.u_profile');
  if (profileBox == null) return;

  // --- 昵称和 UID ---
  final h2 = profileBox.querySelector('h2');
  if (h2 != null) {
    final text = sanitizeText(h2.text);
    final uidMatch = RegExp(r'UID:\s*(\d+)').firstMatch(text);
    if (uidMatch != null) {
      profile['uid'] = uidMatch.group(1);
    }
    final nickMatch = RegExp(r'^(.+?)\s*\(').firstMatch(text);
    if (nickMatch != null) {
      profile['nickname'] = nickMatch.group(1)?.trim();
    }
  }

  // --- 邮箱状态 ---
  final emailLi = profileBox.querySelector('ul.pf_l.cl.pbm li');
  if (emailLi != null) {
    final em = emailLi.querySelector('em');
    if (em != null && sanitizeText(em.text) == '邮箱状态') {
      final liClone = emailLi.clone(true);
      liClone.querySelector('em')?.remove();
      profile['emailVerified'] = sanitizeText(liClone.text) != '未验证';
    }
  }

  // --- 自定义头衔 ---
  for (final li in profileBox.querySelectorAll('ul > li.xg1')) {
    final em = li.querySelector('em');
    if (em == null) continue;
    if (sanitizeText(em.text).contains('自定义头衔')) {
      final liClone = li.clone(true);
      liClone.querySelector('em')?.remove();
      profile['customTitle'] = sanitizeText(liClone.text);
      break;
    }
  }

  // --- 个人签名（HTML → BBCode）---
  _parseSignature(profileBox, profile);

  // --- 勋章 ---
  _parseMedals(doc, profile);

  // --- 统计概览（好友数/回帖数/主题数/分享数）---
  final statUl = profileBox.querySelector('ul.cl.bbda');
  if (statUl != null) {
    final links = statUl.querySelectorAll('a');
    final stats = <String, dynamic>{};
    for (final link in links) {
      final text = sanitizeText(link.text);
      final numMatch = RegExp(r'([\d,]+)').firstMatch(text);
      if (numMatch != null) {
        final num = numMatch.group(1)?.replaceAll(',', '');
        if (text.contains('好友数')) stats['friends'] = num;
        if (text.contains('回帖数')) stats['replies'] = num;
        if (text.contains('主题数')) stats['threads'] = num;
        if (text.contains('分享数')) stats['shares'] = num;
      }
    }
    if (stats.isNotEmpty) profile['stats'] = stats;
  }

  // --- 详细资料（QQ/职业/居住地等）---
  final detailUl = profileBox.querySelector('ul.pf_l.cl');
  if (detailUl != null) {
    // 检查是否有实际的 li（排除邮箱状态后的空 ul）
    final lis = detailUl.querySelectorAll('li');
    if (lis.isNotEmpty) {
      final details = <String, dynamic>{};
      _parseListItemsInUl(detailUl, (label, value) {
        switch (label) {
          case 'QQ':
            final qqLink = detailUl.querySelector('li a[title="发起QQ聊天"]');
            if (qqLink != null) {
              final uinMatch = RegExp(
                r'uin=(\d+)',
              ).firstMatch(qqLink.attributes['href'] ?? '');
              if (uinMatch != null) details['qq'] = uinMatch.group(1);
            }
            break;
          case '性别':
            details['gender'] = value;
            break;
          case '生日':
            details['birthday'] = value;
            break;
          case '职业':
            details['occupation'] = value;
            break;
          case '真实姓名':
            details['realName'] = value;
            break;
          case '居住地':
            details['residence'] = value;
            break;
          case '出生地':
            details['birthplace'] = value;
            break;
        }
      });
      if (details.isNotEmpty) profile['details'] = details;
    }
  }
}

/// 解析个人签名：HTML → BBCode
void _parseSignature(dom.Element profileBox, Map<String, dynamic> profile) {
  for (final li in profileBox.querySelectorAll('ul > li')) {
    final em = li.querySelector('em');
    if (em == null) continue;
    if (sanitizeText(em.text).contains('个人签名')) {
      // 签名内容在 <table><tr><td> 中
      final td = li.querySelector('table td');
      if (td != null) {
        // 转换为 BBCode
        final converter = Html2BBCode();
        final bbcode = converter.convertElementContent(td);
        if (bbcode.isNotEmpty) {
          profile['signature'] = bbcode;
        }
      }
      break;
    }
  }
}

/// 解析勋章区域
void _parseMedals(dom.Document doc, Map<String, dynamic> profile) {
  // 查找 <h2> 文本为"勋章"的父 div
  dom.Element? medalsDiv;
  for (final h2 in doc.querySelectorAll('h2')) {
    if (sanitizeText(h2.text) == '勋章') {
      medalsDiv = h2.parent;
      break;
    }
  }
  if (medalsDiv == null) return;

  final medalImgs = medalsDiv.querySelectorAll('p.md_ctrl img');
  if (medalImgs.isEmpty) return;

  final medals = medalImgs.map((img) {
    return {
      'name': img.attributes['alt'] ?? '',
      'icon': img.attributes['src'] ?? '',
    };
  }).toList();

  profile['medals'] = medals;
}

/// 解析活跃概况区域 — 按 <h2> 文本"活跃概况"定位
void _parseActivitySection(dom.Document doc, Map<String, dynamic> profile) {
  // 查找所有 <h2> 找到"活跃概况"
  dom.Element? activityDiv;
  for (final h2 in doc.querySelectorAll('h2')) {
    if (sanitizeText(h2.text) == '活跃概况') {
      activityDiv = h2.parent; // <div class="pbm mbm bbda cl">
      break;
    }
  }
  if (activityDiv == null) return;

  final activity = <String, dynamic>{};

  // 管理组 / 用户组
  for (final em in activityDiv.querySelectorAll('ul li em.xg1')) {
    final label = sanitizeText(em.text);
    // 获取后面的 <a> 链接文本
    final link = em.parent?.querySelector('a');
    final value = sanitizeText(link?.text);
    if (label.contains('管理组')) {
      activity['adminGroup'] = value;
    } else if (label.contains('用户组')) {
      activity['userGroup'] = value;
    }
  }

  // 其余活跃信息在 #pbbs 中
  final pbbs = activityDiv.querySelector('#pbbs');
  if (pbbs != null) {
    _parseListItemsInUl(pbbs, (label, value) {
      switch (label) {
        case '在线时间':
          activity['onlineTime'] = value;
          break;
        case '注册时间':
          activity['registerTime'] = value;
          break;
        case '最后访问':
          activity['lastVisit'] = value;
          break;
        case '注册 IP':
          activity['registerIp'] = value;
          break;
        case '上次访问 IP':
          activity['lastVisitIp'] = value;
          break;
        case '上次活动时间':
          activity['lastActivityTime'] = value;
          break;
        case '上次发表时间':
          activity['lastPostTime'] = value;
          break;
        case '所在时区':
          activity['timezone'] = value;
          break;
      }
    });
  }

  if (activity.isNotEmpty) profile['activity'] = activity;
}

/// 解析统计信息区域 (#psts)
void _parseStatsSection(dom.Document doc, Map<String, dynamic> profile) {
  final psts = doc.querySelector('#psts');
  if (psts == null) return;

  final points = <String, dynamic>{};
  _parseListItemsInUl(psts, (label, value) {
    switch (label) {
      case '积分':
        points['credits'] = value.replaceAll(',', '');
        break;
      case '好评':
        points['reputation'] = value;
        break;
      case '金币':
        points['goldCoins'] = value;
        break;
      case '信誉':
        points['credit'] = value;
        break;
      case '已用空间':
        points['usedSpace'] = value;
        break;
    }
  });

  if (points.isNotEmpty) profile['points'] = points;
}

/// 遍历 ul 中的 li，提取 label（em 文本）和 value（em 后的文本）
void _parseListItemsInUl(
  dom.Element ul,
  void Function(String label, String value) callback,
) {
  final lis = ul.querySelectorAll('li');
  for (final li in lis) {
    final em = li.querySelector('em');
    if (em == null) continue;
    final label = sanitizeText(em.text);
    // 移除 em 节点，获取剩余文本
    final clonedLi = li.clone(true);
    final emInClone = clonedLi.querySelector('em');
    emInClone?.remove();
    final value = sanitizeText(clonedLi.text);
    if (value.isNotEmpty) {
      callback(label, value);
    }
  }
}

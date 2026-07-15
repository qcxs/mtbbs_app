import 'dart:convert';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:mtbbs/core/html2bbcode.dart';
import 'package:mtbbs/core/page_helper.dart';
import 'package:mtbbs/core/logger.dart';

/// 用户空间个人资料响应解析
///
/// 从 home.php?mod=space&uid={uid}&do=profile 的 HTML 中提取用户信息。

Map<String, dynamic> parseResponse(String body, int statusCode) {
  if (statusCode != 200) {
    return {'success': false, 'message': 'HTTP $statusCode'};
  }

  final doc = html_parser.parse(body);

  // 统一检测 Discuz 错误页
  final pageError = checkPageError(doc, body);
  if (pageError.isError) {
    return {
      'success': false,
      'message': pageError.message ?? '页面错误',
      'loginRequired': pageError.loginRequired,
    };
  }

  final profile = <String, dynamic>{};

  // 尝试标准解析（MT论坛结构的 #uhd + .u_profile）
  _parseHeader(doc, profile);
  _parseProfileSection(doc, profile);

  // 如果标准解析没拿到昵称，尝试从 h2 直接提取（部分模板）
  if ((profile['nickname'] == null || profile['nickname'] == '') &&
      profile['uid'] != null) {
    _parseNicknameFallback(doc, profile);
  }

  // 无论如何都继续解析剩余字段
  _parseActivitySection(doc, profile);
  _parseStatsSection(doc, profile);

  // 必要内容校验：昵称和 uid 都没有，且页面上无用户内容 DOM → 判定无效
  if ((profile['nickname'] == null || profile['nickname'] == '') &&
      (profile['uid'] == null || profile['uid'] == '')) {
    final hasUserContent = doc.querySelector('#uhd, .u_profile') != null;
    if (!hasUserContent) {
      AppLogger.w('PARSE', 'space: no user content');
      return {'success': false, 'message': '页面不可用或用户不存在'};
    }
  }

  AppLogger.i(
    'PARSE',
    jsonEncode({
      'type': 'space',
      'uid': profile['uid'],
      'nickname': profile['nickname'],
    }),
  );

  return {'success': true, 'profile': profile};
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
        final bbcode = converter.convertElement(td);
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

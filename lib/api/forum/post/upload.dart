import 'dart:io';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:mtbbs/core/xml_helper.dart';

/// 上传图片到论坛
///
/// 使用 swfupload 端点，返回 `{aid, src, title}`。
/// 响应格式: DISCUZUPLOAD|{?}|{errorCode}|{aid}|{?}|{filepath}|{title}|{?}
Future<Map<String, dynamic>> uploadImage(
  Dio dio, {
  required File file,
  required String uid,
  required String uploadHash,
}) async {
  final formData = FormData.fromMap({
    'Filedata': await MultipartFile.fromFile(
      file.path,
      filename: file.path.split('/').last,
    ),
    'uid': uid,
    'hash': uploadHash,
  });

  final resp = await dio.post<String>(
    '/misc.php?mod=swfupload&operation=upload&type=image&inajax=yes&infloat=yes&simple=2',
    data: formData,
    options: Options(
      contentType: 'multipart/form-data',
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  final body = resp.data ?? '';
  // DISCUZUPLOAD|1|0|{aid}|1|{filepath}|{title}|0
  final parts = body.split('|');
  if (parts.length >= 4 && parts[2] == '0') {
    final aid = parts[3];
    final filepath = parts.length > 5 ? parts[5] : '';
    final title = parts.length > 6 ? parts[6] : '';
    final src = filepath.isNotEmpty ? 'data/attachment/forum/$filepath' : '';
    return {'aid': aid, 'src': src, 'title': title, 'success': true};
  }
  final errorMsg = parts.length > 2 ? _statusMsg(parts[2]) : '上传失败';
  return {'success': false, 'error': errorMsg};
}

/// 获取未使用的图片列表（恢复功能）
///
/// 使用 DOM 解析，支持两种响应格式：
///   格式1（未使用）：`<img id="image_{aid}" src="..." title="...">`
///   格式2（已绑定）：`<a title="..." id="imageattach{aid}"><img id="image_{aid}" src="...">`
///
/// 返回包含 aid 和 src 的列表。
Future<List<Map<String, dynamic>>> fetchUnusedImages(
  Dio dio, {
  String fid = '',
  String? tid,
}) async {
  final params = <String, dynamic>{};
  if (fid.isNotEmpty) params['fid'] = fid;
  if (tid != null && tid.isNotEmpty) params['tid'] = tid;
  final resp = await dio.get(
    '/forum.php?mod=ajax&action=imagelist',
    queryParameters: params,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

  final body = resp.data is String ? resp.data as String : '';
  final images = <Map<String, dynamic>>[];

  try {
    final xml = parseInajaxXml(body);
    final doc = xml?.htmlDoc;
    if (doc == null) return images;

    for (final img in doc.querySelectorAll('img[id^="image_"]')) {
      final imgId = img.attributes['id'] ?? '';
      final aid = imgId.replaceFirst('image_', '');
      if (aid.isEmpty || !RegExp(r'^\d+$').hasMatch(aid)) continue;
      final src = img.attributes['src'] ?? '';
      // 从父级 <a> 标签获取 title（绑定格式）
      final parentA =
          (img.parentNode is dom.Element &&
              (img.parentNode! as dom.Element).localName == 'a')
          ? img.parentNode as dom.Element
          : null;
      final title =
          parentA?.attributes['title'] ?? img.attributes['title'] ?? '';
      images.add({'aid': aid, 'src': src, 'title': title});
    }
  } catch (_) {
    // DOM 解析失败时返回空列表
  }

  return images;
}

/// 删除图片（未绑定/已绑定均可）
///
/// 传参规则：
/// - [formhash] 必传（身份校验）
/// - [tid] 可选，有则传
/// - [pid] 可选，有则传
/// - 如果 tid 和 pid 都不传，删除的是刚上传且未绑定的图片
/// - 如果 tid 和 pid 都传，删除的是该帖子下已绑定的图片
Future<bool> deleteUnusedImage(
  Dio dio, {
  required String formhash,
  String? tid,
  String? pid,
  required String aid,
}) async {
  final params = <String, dynamic>{'formhash': formhash, 'aids[]': aid};
  if (tid != null && tid.isNotEmpty) params['tid'] = tid;
  if (pid != null && pid.isNotEmpty) params['pid'] = pid;
  final resp = await dio.get(
    '/forum.php?mod=ajax&action=deleteattach&inajax=yes',
    queryParameters: params,
  );
  return resp.statusCode == 200;
}

/// 上传状态码映射
String _statusMsg(String code) {
  const msgs = {
    '-1': '内部服务器错误',
    '0': '上传成功',
    '1': '不支持此类扩展名',
    '2': '服务器限制无法上传那么大的附件',
    '3': '用户组限制无法上传那么大的附件',
    '4': '不支持此类扩展名',
    '5': '文件类型限制无法上传那么大的附件',
    '6': '今日您已无法上传更多的附件',
    '7': '请选择图片文件',
    '8': '附件文件无法保存',
    '9': '没有合法的文件被上传',
    '10': '非法操作',
    '11': '今日您已无法上传那么大的附件',
  };
  return msgs[code] ?? '未知错误($code)';
}

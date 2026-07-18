import 'dart:io';
import 'package:dio/dio.dart';

/// 图片上传 API 测试
///
/// 用法:
///   dart run lib/api/forum/post/upload_test.dart --fid=2 --tid=14 --formhash=e00030eb
void main(List<String> args) async {
  final baseUrl = _p(args, '--base-url', 'http://discuz.qcxs.top');
  final fid = _p(args, '--fid', '2');
  final tid = _p(args, '--tid', '14');
  final filePath = _p(args, '--file', r'D:\system\Downloads\头像-标清.png');
  final formhash = _p(args, '--formhash', '');
  final cookieStr = _p(args, '--cookie', '');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
      },
    ),
  );
  if (cookieStr.isNotEmpty) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          o.headers['Cookie'] = cookieStr;
          h.next(o);
        },
      ),
    );
  }

  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('文件不存在');
    exit(1);
  }

  // 获取 formhash
  String fh = formhash;
  if (fh.isEmpty) {
    final r = await dio.get(
      '/forum.php?mod=post&action=newthread&fid=$fid&mobile=2',
    );
    final m = RegExp(
      r'name="formhash"\s+value="([^"]+)"',
    ).firstMatch(r.data.toString());
    fh = m?.group(1) ?? '';
  }
  print('formhash: $fh');

  // === 1. 测试 swfupload 端点（已验证可用）===
  print('\n=== 1. misc.php?mod=swfupload ===');
  try {
    final fd = FormData.fromMap({
      'Filedata': await MultipartFile.fromFile(file.path, filename: 'test.png'),
      'uid': '2',
      'hash': '77604a6bfd653f679fce1d88988cd9d2',
    });
    final r = await dio.post(
      '/misc.php?mod=swfupload&operation=upload&type=image&inajax=yes&infloat=yes&simple=2',
      data: fd,
      options: Options(contentType: 'multipart/form-data'),
    );
    print('状态码: ${r.statusCode}');
    print('响应: ${r.data}');
    // 解析: DISCUZUPLOAD|1|0|{aid}|1|{path}|{title}|0
    final parts = r.data.toString().split('|');
    if (parts.length >= 4 && parts[2] == '0') {
      print('✅ aid: ${parts[3]}, path: ${parts[5]}');
    }
  } catch (e) {
    print('❌ $e');
  }

  // === 2. 测试 forum.php 端点（无 mobile=2）===
  print('\n=== 2. forum.php?mod=post&action=upload (PC UA) ===');
  try {
    final fd2 = FormData.fromMap({
      'Filedata': await MultipartFile.fromFile(file.path, filename: 'test.png'),
      'formhash': fh,
      'fid': fid,
      'tid': tid,
    });
    final r2 = await dio.post(
      '/forum.php?mod=post&action=upload',
      data: fd2,
      options: Options(
        contentType: 'multipart/form-data',
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ),
    );
    print('状态码: ${r2.statusCode}');
    print(
      '响应(前500): ${r2.data.toString().substring(0, r2.data.toString().length.clamp(0, 500))}',
    );
  } catch (e) {
    print('❌ $e');
  }

  // === 3. 测试列表 ===
  print('\n=== 3. imagelist ===');
  try {
    final r3 = await dio.get(
      '/forum.php?mod=ajax&action=imagelist',
      queryParameters: {'fid': fid, 'tid': tid},
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ),
    );
    print(
      '响应(前300): ${r3.data.toString().substring(0, r3.data.toString().length.clamp(0, 300))}',
    );
  } catch (e) {
    print('❌ $e');
  }

  print('\n========== 完成 ==========');
}

String _p(List<String> args, String key, String defaultVal) {
  for (int i = 0; i < args.length; i++) {
    if (args[i] == key && i + 1 < args.length) return args[i + 1];
    if (args[i].startsWith('$key=')) return args[i].substring(key.length + 1);
  }
  return defaultVal;
}

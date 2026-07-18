import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mtbbs/core/xml_helper.dart';
import 'export.dart' as api;
import 'http.dart' as http;
import 'parse.dart' as parse;
import '../../helpers.dart';

/// 发帖/回复 API 测试
///
/// 用法:
///   dart run lib/api/forum/post/test.dart --mode=thread --subject="标题" --message="内容"
///   dart run lib/api/forum/post/test.dart --mode=reply --tid=4 --message="回复内容"
///   dart run lib/api/forum/post/test.dart --mode=quote --tid=4 --repquote=7 --message="引用回复"
///   dart run lib/api/forum/post/test.dart --mode=thread --http-only
///   dart run lib/api/forum/post/test.dart --mode=thread --base-url=http://127.0.0.1
void main(List<String> args) async {
  final mode = _parseArg(args, '--mode') ?? 'thread';
  final baseUrl = _parseArg(args, '--base-url') ?? 'https://bbs.binmt.cc';
  final httpOnly = args.contains('--http-only');
  final verbose = args.contains('--verbose') || args.contains('-v');
  final fid = _parseArg(args, '--fid') ?? '2';
  final tid = _parseArg(args, '--tid') ?? '4';
  final repquote = _parseArg(args, '--repquote');
  final subject = _parseArg(args, '--subject') ?? 'API测试帖';
  final message = _parseArg(args, '--message') ?? '这是API发布的测试内容';

  print('========== 发帖/回复 API 测试 ==========');
  print('模式: $mode');
  print('baseUrl: $baseUrl');
  if (mode == 'thread') print('fid: $fid, subject: $subject');
  if (mode != 'thread') print('tid: $tid');
  if (repquote != null) print('repquote: $repquote');
  print('');

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      },
    ),
  );

  // 从 cookie 参数设置 Cookie（通过 interceptor 确保发送）
  final cookieStr = _parseArg(args, '--cookie');
  if (cookieStr != null && cookieStr.isNotEmpty) {
    final cs = cookieStr;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Cookie'] = cs;
          handler.next(options);
        },
      ),
    );
  }

  try {
    if (httpOnly) {
      await _httpOnly(dio, mode, fid, tid, repquote, verbose);
      return;
    }

    SubmitResult result;

    switch (mode) {
      case 'thread':
        result = await api.submitNewPost(
          dio,
          fid: fid,
          formhash: 'test_hash',
          posttime: '1234567890',
          subject: subject,
          message: message,
        );
        break;
      case 'reply':
        result = await api.submitReply(
          dio,
          fid: '2',
          tid: tid,
          formhash: 'test_hash',
          posttime: '1234567890',
          message: message,
        );
        break;
      case 'quote':
        result = await api.submitReply(
          dio,
          fid: '2',
          tid: tid,
          formhash: 'test_hash',
          posttime: '1234567890',
          message: message,
          reppid: repquote,
        );
        break;
      default:
        stderr.writeln('❌ 未知模式: $mode');
        exit(1);
    }

    print('结果:');
    print('  success  = ${result.success}');
    print('  message  = ${result.message}');
    if (result.tid.isNotEmpty) {
      print('  tid      = ${result.tid}');
    }
    if (result.pid.isNotEmpty) {
      print('  pid      = ${result.pid}');
    }

    if (result.success) {
      print('\n✅ 测试通过');
    } else {
      stderr.writeln('\n❌ 测试失败: ${result.message}');
      exit(1);
    }
  } catch (e) {
    stderr.writeln('❌ 异常: $e');
    exit(1);
  }
}

/// --http-only 模式：仅测试 GET 页面和提取 formhash
Future<void> _httpOnly(
  Dio dio,
  String mode,
  String fid,
  String tid,
  String? repquote,
  bool verbose,
) async {
  print('--- HTTP 请求 ---');
  try {
    if (mode == 'thread') {
      final resp = await http.getNewThreadPage(dio, fid: fid);
      final body = safeDecode(resp);
      if (verbose) {
        print(
          '响应(前500): ${body.substring(0, body.length > 500 ? 500 : body.length)}',
        );
      }
      print('状态: ${resp.statusCode}');
      print('响应长度: ${body.length}');
      final form = parse.parseFormData(body);
      print('formhash: ${form['formhash']}');
      print('posttime: ${form['posttime']}');
      if ((form['formhash'] as String).isEmpty) {
        stderr.writeln('❌ 无法从页面提取 formhash');
        exit(1);
      }
    } else {
      final resp = await http.getReplyPage(dio, tid: tid, repquote: repquote);
      final body = safeDecode(resp);
      print('状态: ${resp.statusCode}');
      print('响应长度: ${body.length}');
      final form = parse.parseFormData(body);
      print('formhash: ${form['formhash']}');
      print('posttime: ${form['posttime']}');
      print('noticeauthor: ${form['noticeauthor']}');
      print('reppid: ${form['reppid']}');
      if ((form['formhash'] as String).isEmpty) {
        stderr.writeln('❌ 无法从页面提取 formhash');
        exit(1);
      }
    }
    print('✅ HTTP 测试通过');
  } catch (e) {
    stderr.writeln('❌ HTTP 异常: $e');
    exit(1);
  }
}

String? _parseArg(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  return null;
}

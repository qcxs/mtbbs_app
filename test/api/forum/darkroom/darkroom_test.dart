import 'dart:io';
import 'package:dio/dio.dart';
import 'export.dart' as api;

void main(List<String> args) async {
  final cid = args.isNotEmpty ? args[0] : '';
  final baseUrl = args.length > 1 ? args[1] : 'https://bbs.binmt.cc';

  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  final result = await api.getList(dio, cid: cid);

  if (result['success'] != true) {
    stderr.writeln('Error: ${result['message']}');
    exit(1);
  }

  final items = result['items'] as List;
  final hasMore = result['hasMore'] as bool;
  final nextCid = result['nextCid'] as String;

  print('Items: ${items.length}');
  print('HasMore: $hasMore');
  print('NextCid: $nextCid');
  print('');
  for (final item in items) {
    final m = item as Map<String, dynamic>;
    print('  [${m['cid']}] ${m['username']} — ${m['action']}');
    print('    操作者: ${m['operator']} (${m['operatorid']})');
    print('    原因: ${m['reason']}');
    print('    时间: ${m['dateline']}');
    print('    期限: ${m['groupexpiry']}');
    print('');
  }
}

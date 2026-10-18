/// 探针侧的纯 Dart ACW 自解入口。
///
/// 算法正文已移到 `lib/core/app/acw_pure_dart.dart`，与 App 运行时兜底共用一份，
/// 避免两套实现漂移。这里只做 re-export，探针的 import 与调用方式保持不变。
library;

export 'package:mtbbs/core/app/acw_pure_dart.dart';

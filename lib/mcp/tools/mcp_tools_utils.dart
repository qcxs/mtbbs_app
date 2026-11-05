import 'package:mcp_dart/mcp_dart.dart';
import 'package:mtbbs/core/utils/codec_utils.dart';
import 'package:mtbbs/mcp/mcp_types.dart';
import 'package:mtbbs/mcp/tools/mcp_tool_definition.dart';

/// 本地工具组（`McpToolGroup.utility`）
///
/// 纯计算，不访问论坛；用于还原帖子里常见的 Base64 / URL / Hex 编码，
/// 省得 AI 自己找在线工具或写脚本。
List<McpToolDefinition> utilTools() => [
  McpToolDefinition(
    name: 'codec_text',
    group: McpToolGroup.utility,
    description:
        '本地编解码 / 哈希，不访问网络：支持 base64、url、hex 的编码与解码，'
        '以及 md5 / sha1 / sha256 摘要。base64 解码容忍换行、URL-safe 字母表与缺失的 =，'
        'hex 解码容忍空格、换行与 0x 前缀；失败时返回可读的错误原因。',
    properties: {
      'op': JsonSchema.string(
        description: '编解码类型',
        enumValues: const ['base64', 'url', 'hex', 'md5', 'sha1', 'sha256'],
      ),
      'direction': JsonSchema.string(
        description: '方向：encode 编码 / decode 解码（哈希类忽略此参数）',
        enumValues: const ['encode', 'decode'],
      ),
      'text': JsonSchema.string(description: '要处理的文本'),
    },
    requiredArgs: const ['op', 'text'],
    network: false, // 纯本地计算
    run: (args) async {
      final op = McpArgs.requireStr(args, 'op').toLowerCase();
      final text = McpArgs.requireStr(args, 'text');
      final direction = McpArgs.str(args, 'direction', fallback: 'encode');
      if (text.length > maxInputChars) {
        throw ArgumentError(
          'text 过长（${text.length} 字符，上限 $maxInputChars）；'
          '请先截取需要处理的部分再重试。',
        );
      }
      final isHash = op == 'md5' || op == 'sha1' || op == 'sha256';
      final result = switch (op) {
        'base64' => direction == 'decode'
            ? CodecUtils.base64Decode(text)
            : CodecUtils.base64Encode(text),
        'url' => direction == 'decode'
            ? CodecUtils.urlDecode(text)
            : CodecUtils.urlEncode(text),
        'hex' => direction == 'decode'
            ? CodecUtils.hexDecode(text)
            : CodecUtils.hexEncode(text),
        'md5' => CodecUtils.md5(text),
        'sha1' => CodecUtils.sha1(text),
        'sha256' => CodecUtils.sha256(text),
        _ => throw ArgumentError(
          '不支持的 op=$op，可用：base64 / url / hex / md5 / sha1 / sha256',
        ),
      };
      return {
        'op': op,
        if (!isHash) 'direction': direction,
        'inputChars': text.length,
        'outputChars': result.length,
        'result': result,
      };
    },
  ),
];

/// 单次编解码的输入上限，避免 AI 误传整篇帖子把上下文与内存撑爆
const int maxInputChars = 200000;

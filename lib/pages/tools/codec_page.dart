import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mtbbs/config/app_typography.dart';
import 'package:mtbbs/core/utils/clipboard_helper.dart';
import 'package:mtbbs/core/utils/codec_utils.dart';
import 'package:mtbbs/core/utils/url_router.dart';
import 'package:mtbbs/widgets/common/toast_utils.dart';

/// 编解码工具页：Base64 / URL / 十六进制 / MD5 / SHA-1 / SHA-256。
///
/// 入口：帖子页右上角菜单「编解码工具」、设置 → 存储与工具。
/// 解码出的链接可直接「在 App 打开」（走 [UrlRouter.resolveTarget]），
/// 解决 52pojie 等技术论坛把资源链接做 Base64 编码的情况。
class CodecPage extends StatefulWidget {
  const CodecPage({super.key});

  @override
  State<CodecPage> createState() => _CodecPageState();
}

/// 可用的处理方式。可逆项（Base64/URL/Hex）带「编码/解码」方向，
/// 哈希项（MD5/SHA）只有单向计算。
enum _CodecOp {
  base64('Base64'),
  url('URL'),
  hex('十六进制'),
  md5('MD5'),
  sha1('SHA-1'),
  sha256('SHA-256');

  const _CodecOp(this.label);

  final String label;

  bool get reversible => switch (this) {
    _CodecOp.md5 || _CodecOp.sha1 || _CodecOp.sha256 => false,
    _ => true,
  };
}

class _CodecPageState extends State<CodecPage> {
  late final TextEditingController _input;
  _CodecOp _op = _CodecOp.base64;
  bool _encode = true;
  String _output = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 计算当前操作的结果；错误不抛给 UI 之外（错误文案由页面展示）。
  ({String output, String? error}) _run(String text) {
    if (text.isEmpty) return (output: '', error: null);
    try {
      return (output: _convert(text), error: null);
    } on FormatException {
      return (output: '', error: _errorText);
    } on ArgumentError {
      // Uri.decodeComponent 对非法百分号编码抛 ArgumentError
      return (output: '', error: _errorText);
    }
  }

  String get _errorText {
    final action = _op.reversible ? (_encode ? '编码' : '解码') : '计算';
    return '格式不正确，无法$action';
  }

  String _convert(String text) => switch (_op) {
    _CodecOp.base64 =>
      _encode ? CodecUtils.base64Encode(text) : CodecUtils.base64Decode(text),
    _CodecOp.url =>
      _encode ? CodecUtils.urlEncode(text) : CodecUtils.urlDecode(text),
    _CodecOp.hex =>
      _encode ? CodecUtils.hexEncode(text) : CodecUtils.hexDecode(text),
    _CodecOp.md5 => CodecUtils.md5(text),
    _CodecOp.sha1 => CodecUtils.sha1(text),
    _CodecOp.sha256 => CodecUtils.sha256(text),
  };

  void _recompute() {
    final result = _run(_input.text);
    if (!mounted) return;
    setState(() {
      _output = result.output;
      _error = result.error;
    });
  }

  void _selectOp(_CodecOp op) {
    if (_op == op) return;
    _op = op;
    _recompute();
  }

  void _setEncode(bool value) {
    if (_encode == value) return;
    _encode = value;
    _recompute();
  }

  Future<void> _paste() async {
    final text = await ClipboardHelper.read();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      showToast('剪贴板为空或无法读取');
      return;
    }
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _recompute();
  }

  void _clear() {
    _input.clear();
    _recompute();
  }

  Future<void> _copy() async {
    final ok = await ClipboardHelper.write(_output);
    showToast(
      ok ? '已复制' : '复制到剪贴板失败',
      duration: const Duration(seconds: 1),
    );
  }

  String get _trimmedOutput => _output.trim();

  bool get _outputIsLink {
    final text = _trimmedOutput;
    return text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('${UrlRouter.appScheme}://');
  }

  bool get _outputIsHttpLink {
    final text = _trimmedOutput;
    return text.startsWith('http://') || text.startsWith('https://');
  }

  void _openInApp() {
    final target = UrlRouter.resolveTarget(_trimmedOutput);
    if (target != null) context.push(target);
  }

  void _openInBrowser() {
    context.push(
      '/browser?url=${Uri.encodeComponent(_trimmedOutput)}&intercept=false',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('编解码工具'),
        surfaceTintColor: cs.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste, size: 20),
            tooltip: '粘贴剪贴板',
            onPressed: _paste,
          ),
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            tooltip: '清空',
            onPressed: _input.text.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            '帖子里常见的 Base64 / URL 编码链接，粘贴后还原即可直接打开。',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final op in _CodecOp.values)
                ChoiceChip(
                  label: Text(op.label),
                  selected: _op == op,
                  onSelected: (_) => _selectOp(op),
                ),
            ],
          ),
          if (_op.reversible) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('编码')),
                ButtonSegment(value: false, label: Text('解码')),
              ],
              selected: {_encode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _setEncode(selection.first),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            minLines: 4,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: context.appTypography.mono.copyWith(fontSize: 13),
            decoration: const InputDecoration(
              labelText: '输入内容',
              hintText: '粘贴要处理的文本',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _recompute(),
          ),
          const SizedBox(height: 16),
          _buildOutput(cs),
        ],
      ),
    );
  }

  Widget _buildOutput(ColorScheme cs) {
    final hasError = _error != null;
    final text = _error ?? _output;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '结果',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              if (_output.isNotEmpty && !hasError)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: '复制结果',
                  visualDensity: VisualDensity.compact,
                  onPressed: _copy,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: text.isEmpty
                ? Text('—', style: TextStyle(color: cs.onSurfaceVariant))
                : SelectableText(
                    text,
                    style: context.appTypography.mono.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: hasError ? cs.error : cs.onSurface,
                    ),
                  ),
          ),
          if (_outputIsLink) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _openInApp,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('在 App 打开'),
                ),
                if (_outputIsHttpLink)
                  OutlinedButton(
                    onPressed: _openInBrowser,
                    child: const Text('在浏览器打开'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// BBCode 顶层分块器 —— 为「分块可视化」编辑器提供块级切分。
///
/// 核心约定（方案成立与否取决于此，勿破坏）：
/// 1. **只切分，不改写**：每块保留**原文切片** [BbBlock.raw]，
///    `blocks.map((b) => b.raw).join() == 输入` 恒成立。
///    因此不需要「AST → BBCode」序列化器，也不存在转换损失——
///    `[attachimg]aid[/attachimg]` 这类只在编辑器会话内有效的构造原样保留。
/// 2. **只切顶层**：块级标签内部不再细分（`[quote]` 里的 `[list]` 不单独成块），
///    避开递归结构与嵌套光标这一整类复杂度。
/// 3. **不撕开内联容器**：块级标签外侧若包着行内标签（如 `[url=x][img]…[/img][/url]`），
///    整段作为一个块，块起点回退到最外层行内标签之前，保证行内配对完整。
/// 4. **绝不抛异常**：畸形输入（未闭合、孤立闭标签、裸 `[`）一律降级为文本段。
///
/// v1 边界：只按**顶层块级标签**切分，不按空行切分——空行切分会改变块边界
/// 处空白的归属，进而与整篇渲染时「移除紧邻块级标签的 `<br>`」规则
/// （见 docs/07 #17）产生保真度差异。
library;

/// 块类型。用于编辑器的块级操作与形状提示，渲染一律走 [BbBlock.raw]。
enum BbBlockKind {
  /// 普通文本段（可含行内标签与多行）
  text,

  /// 引用
  quote,

  /// 免费可见内容
  free,

  /// 需回复/积分可见
  hide,

  /// 代码块（内容原样，不参与分块）
  code,

  /// 列表（`[list]` / `[list=1]` / `[list=a]`）
  list,

  /// 表格
  table,

  /// 对齐容器
  align,

  /// 图片（`[img]` / `[attachimg]`）
  image,

  /// 文件附件
  attach,

  /// 音视频（`[audio]` / `[flash]` / `[media]` / `[video]`）
  media,

  /// 数据载荷（`[appdata]`）：渲染层按 JSON 的 `type` 输出图片附件 /
  /// 文件附件卡片 / 编辑记录 / 隐藏提示 / 奖励 / 投票等块级内容。
  /// 解析层产出的正文里它是常态（见 `html2bbcode.dart`）。
  data,

  /// 分隔线
  hr,
}

/// 可含内容、需要配对闭合的块级容器。
const _containerTags = <String>{
  'quote',
  'free',
  'hide',
  'code',
  'list',
  'table',
  'align',
};

/// 成对出现、内容即地址的块级原子。
const _pairedAtomicTags = <String>{
  'img',
  'attachimg',
  'attach',
  'audio',
  'flash',
  'media',
  'video',
  'appdata',
};

/// 无闭合标签的块级原子。
const _standaloneTags = <String>{'hr'};

/// 行内标签。
///
/// 块级标签出现在行内标签内部时，块起点**回退到最外层行内标签之前**，
/// 使 `[url=x][img]y[/img][/url]` 作为**一个整体**成为图片块。
/// 若照直在 `[img]` 处切分，会得到「文本块 `[url=x]` + 图片块 + 文本块 `[/url]`」——
/// `[url]` 配对失败，链接失效、"点图片跳链接"也没了（docs/07 #44）。
const _inlineTags = <String>{
  'b',
  'i',
  'u',
  's',
  'color',
  'size',
  'font',
  'backcolor',
  'background',
  'url',
  'email',
  'qq',
};

/// 匹配任意 BBCode 标记：`[tag]` / `[tag=值]` / `[/tag]`
///
/// 刻意宽松（未知标签也会被匹配到），以便统一做「是否块级」的判断；
/// 非块级标记直接被忽略，不影响分块结果。
final _tagPattern = RegExp(r'\[(/)?([a-zA-Z*]+)(?:=[^\]]*)?\]');

/// 一个顶层块。
///
/// [raw] 是**原文切片**，也是唯一真相：提交、快照与增量比对都以它为准。
class BbBlock {
  /// 顶层块级标签名；普通文本段为空串
  final String tag;

  /// 原文切片（含标签本身），`splitBbcodeBlocks` 保证所有块首尾相接、无遗漏
  final String raw;

  /// [raw] 在原文中的起止偏移（闭区间起点 + 开区间终点）
  final int start;
  final int end;

  const BbBlock({
    required this.tag,
    required this.raw,
    required this.start,
    required this.end,
  });

  BbBlockKind get kind => bbBlockKindOf(tag);

  /// 是否为普通文本段
  bool get isText => tag.isEmpty;

  /// 渲染/编辑用文本：去掉首尾空白。
  ///
  /// 块间空白交给布局承载，与整篇渲染时「移除紧邻块级标签的 `<br>`」规则一致
  /// （docs/07 #17）。两个块级标签之间的空行会成为一个 `body` 为空的文本段，
  /// 渲染时跳过即可。
  String get body => raw.trim();

  @override
  String toString() => 'BbBlock($kind, ${raw.length} chars)';
}

/// 该标签是否为「可含内容、可整体包裹 / 取消包裹」的块级容器。
///
/// 供编辑器区分「能切换类型的块」（引用 / 隐藏 / 列表…）与「原子块」
/// （图片 / 附件 / 分隔线——它们的"取消包裹"没有语义，去掉标签只剩一个裸地址）。
bool isBbContainerTag(String tag) => _containerTags.contains(tag);

/// 顶层块级标签名 → 块类型。
///
/// 供文档模型/编辑器在**自行构造**块（而非从 [splitBbcodeBlocks] 切出来）时复用，
/// 保证类型判定只有一处来源。
BbBlockKind bbBlockKindOf(String tag) {
  switch (tag) {
    case '':
      return BbBlockKind.text;
    case 'quote':
      return BbBlockKind.quote;
    case 'free':
      return BbBlockKind.free;
    case 'hide':
      return BbBlockKind.hide;
    case 'code':
      return BbBlockKind.code;
    case 'list':
      return BbBlockKind.list;
    case 'table':
      return BbBlockKind.table;
    case 'align':
      return BbBlockKind.align;
    case 'img':
    case 'attachimg':
      return BbBlockKind.image;
    case 'attach':
      return BbBlockKind.attach;
    case 'audio':
    case 'flash':
    case 'media':
    case 'video':
      return BbBlockKind.media;
    case 'appdata':
      return BbBlockKind.data;
    case 'hr':
      return BbBlockKind.hr;
    default:
      return BbBlockKind.text;
  }
}

/// 把 BBCode 原文切成顶层块。
///
/// 保证：`splitBbcodeBlocks(s).map((b) => b.raw).join() == s`
/// （空串输入返回空列表）。行内标签（`[b]`/`[color]`/`[url]`…）不产生块边界。
List<BbBlock> splitBbcodeBlocks(String input) {
  if (input.isEmpty) return const <BbBlock>[];

  final ranges = <({int start, int end, String tag})>[];
  // 所有未闭合标签（行内 + 块级），元素为 (标签名, 开标签起始偏移)
  final stack = <({String tag, int start})>[];
  var blockStart = -1;
  var blockTag = '';
  var inCode = false;

  for (final m in _tagPattern.allMatches(input)) {
    final isClose = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();

    // [code] 内是原样内容：除其自身闭合标签外，其余标记一律不参与分块
    if (inCode && !(isClose && tag == 'code')) continue;

    if (_standaloneTags.contains(tag)) {
      // 自闭合块级原子：仅在最外层自成一块
      if (!isClose && stack.isEmpty) {
        ranges.add((start: m.start, end: m.end, tag: tag));
      }
      continue;
    }

    final isContainer = _containerTags.contains(tag);
    final isAtomic = _pairedAtomicTags.contains(tag);
    if (!isContainer && !isAtomic && !_inlineTags.contains(tag)) continue;

    if (!isClose) {
      // 开启新块：要求当前没有未闭合的**块级**标签（行内标签允许在外层，
      // 此时块起点回退到最外层行内标签之前，避免撕开内联容器）
      if (blockStart < 0 &&
          (isContainer || isAtomic) &&
          !_hasOpenBlock(stack)) {
        blockStart = stack.isEmpty ? m.start : stack.first.start;
        blockTag = tag;
      }
      stack.add((tag: tag, start: m.start));
      if (tag == 'code') inCode = true;
      continue;
    }

    // 闭合标签：从栈顶回溯同名开标签
    final idx = stack.lastIndexWhere((e) => e.tag == tag);
    if (idx < 0) continue; // 孤立闭标签 → 忽略
    stack.removeRange(idx, stack.length);
    if (tag == 'code') inCode = false;
    if (stack.isEmpty && blockStart >= 0) {
      ranges.add((start: blockStart, end: m.end, tag: blockTag));
      blockStart = -1;
    }
  }

  // 栈非空说明末尾有未闭合的标签：不产出块，整段自然降级为文本
  final blocks = <BbBlock>[];
  var cursor = 0;
  for (final r in ranges) {
    if (r.start > cursor) {
      blocks.add(
        BbBlock(
          tag: '',
          raw: input.substring(cursor, r.start),
          start: cursor,
          end: r.start,
        ),
      );
    }
    blocks.add(
      BbBlock(
        tag: r.tag,
        raw: input.substring(r.start, r.end),
        start: r.start,
        end: r.end,
      ),
    );
    cursor = r.end;
  }
  if (cursor < input.length) {
    blocks.add(
      BbBlock(
        tag: '',
        raw: input.substring(cursor),
        start: cursor,
        end: input.length,
      ),
    );
  }
  return blocks;
}

/// 栈中是否存在未闭合的块级标签
bool _hasOpenBlock(List<({String tag, int start})> stack) => stack.any(
  (e) => _containerTags.contains(e.tag) || _pairedAtomicTags.contains(e.tag),
);

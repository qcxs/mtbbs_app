/// Markdown → BBCode 转换模板（单一数据源）
///
/// 每个 Markdown 元素对应一个模板字符串，`${变量名}` 为占位符，渲染时替换。
/// 默认值对齐 mt-convert 的 `DEFAULT_SETTINGS`
/// （`mt-convert/src/utils/converterSettings.ts`）。
library;

/// 模板变量占位符：`${name}`
final _templateVarPattern = RegExp(r'\$\{(\w+)\}');

/// 渲染模板：把 `${key}` 替换为 `vars[key]`，缺失的变量取空串。
String renderMdTemplate(String template, Map<String, String> vars) =>
    template.replaceAllMapped(_templateVarPattern, (m) => vars[m[1]] ?? '');

/// analyzer 的正则校验不认识 Unicode 属性转义 `\p{...}`（Dart 运行时支持），
/// 该模式由 `test/md2bbcode_test.dart` 的「去除 Emoji」用例覆盖。
// ignore: valid_regexps
const _emojiCharClass = r'[\p{Extended_Pictographic}\u{FE00}-\u{FE0F}\u{200D}]';

/// 需剔除的 Emoji 字符模式（图形字符 + 变体选择器 + 零宽连字）
///
/// 必须带上变体选择器与零宽连字：只匹配 `\p{Extended_Pictographic}` 会残留
/// `\uFE0F`（如 `❤️` 变成 `❤` + 游离变体符）。
final _emojiPattern = RegExp(_emojiCharClass, unicode: true);

/// 删除文本中的 Emoji 字符
String removeMdEmoji(String text) => text.replaceAll(_emojiPattern, '');

/// Markdown → BBCode 的模板集合
class MdConvertTemplates {
  /// 标题 1（h1），可用变量：`${text}` `${level}` `${size}`
  final String heading1;

  /// 标题 2（h2）
  final String heading2;

  /// 标题 3 及以下（h3~h6）
  final String heading3;

  /// 段落，可用变量：`${text}`
  final String paragraph;

  /// 加粗 `[b]`
  final String strong;

  /// 斜体 `[i]`
  final String em;

  /// 删除线 `[s]`
  final String del;

  /// 高亮 `==text==`（非标准 Markdown 语法，见转换器内的自定义 InlineSyntax）
  final String highlight;

  /// 行内代码（Discuz 无行内代码标签，默认用着色实现）
  final String codespan;

  /// 代码块 `[code]`，可用变量：`${text}` `${lang}`
  final String code;

  /// 引用 `[quote]`
  final String blockquote;

  /// 水平线 `[hr]`
  final String hr;

  /// 链接 `[url]`，可用变量：`${text}` `${href}` `${title}`
  final String link;

  /// 图片 `[img]`，可用变量：`${href}` `${text}`
  final String image;

  /// 列表容器，可用变量：`${body}` `${tag}`（`tag` 为 `list` 或 `list=1`）
  final String list;

  /// 列表项 `[*]`，可用变量：`${text}`
  final String listitem;

  /// 表格容器，可用变量：`${header}` `${body}`
  final String table;

  /// 表格行 `[tr]`，可用变量：`${content}`
  final String tablerow;

  /// 表格单元格 `[td]`，可用变量：`${content}`
  final String tablecell;

  const MdConvertTemplates({
    required this.heading1,
    required this.heading2,
    required this.heading3,
    required this.paragraph,
    required this.strong,
    required this.em,
    required this.del,
    required this.highlight,
    required this.codespan,
    required this.code,
    required this.blockquote,
    required this.hr,
    required this.link,
    required this.image,
    required this.list,
    required this.listitem,
    required this.table,
    required this.tablerow,
    required this.tablecell,
  });

  /// 默认模板（对齐 mt-convert 的 `DEFAULT_SETTINGS`）
  ///
  /// 注意：模板里的 `${xxx}` 是**占位符**，在普通字符串中必须写成 `\${xxx}`，
  /// 否则会被 Dart 当成字符串插值。
  static const defaults = MdConvertTemplates(
    // 标题层级映射到 Discuz 的 [size]：h1=3、h2=2、h3+=1（4 - level，上限 3）
    heading1: '[size=\${size}][b]\${text}[/b][/size]',
    heading2: '[size=\${size}][b]\${text}[/b][/size]',
    heading3: '[size=\${size}][b]\${text}[/b][/size]',
    paragraph: '\${text}',
    strong: '[b]\${text}[/b]',
    em: '[i]\${text}[/i]',
    del: '[s]\${text}[/s]',
    // 黑字黄底，与 mt-convert 一致（Discuz 无 [mark] 标签）
    highlight: '[color=#000000][backcolor=#FFFF00]\${text}[/backcolor][/color]',
    codespan: '[color=#333333][backcolor=#f4f4f4]\${text}[/backcolor][/color]',
    code: '[code]\${text}\n[/code]',
    blockquote: '[quote]\${text}[/quote]',
    hr: '[hr]',
    link: '[url=\${href}]\${text}[/url]',
    image: '[img]\${href}[/img]',
    list: '[\${tag}]\n\${body}[/list]',
    listitem: '[*]\${text}',
    table: '[table]\${header}\${body}[/table]',
    tablerow: '[tr]\${content}[/tr]',
    tablecell: '[td]\${content}[/td]',
  );
}

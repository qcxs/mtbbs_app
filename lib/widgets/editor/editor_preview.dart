import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mtbbs/providers/settings_provider.dart';
import 'package:mtbbs/widgets/bbcode/post_html_widget.dart';
import 'package:mtbbs/widgets/editor/block_marker_gutter.dart';

/// 预览里的一个锚点：渲染用的 BBCode + 标记悬停提示。
///
/// 下标就是锚点序号 —— 与编辑区用的是**同一份锚点表**（见
/// `core/parser/bbcode_anchors.dart`），所以两边的 `id` 天然指同一个锚点。
class EditorPreviewBlock {
  final String bbcode;
  final String label;

  const EditorPreviewBlock(this.bbcode, this.label);

  @override
  bool operator ==(Object other) =>
      other is EditorPreviewBlock &&
      other.bbcode == bbcode &&
      other.label == label;

  @override
  int get hashCode => Object.hash(bbcode, label);
}

/// 编辑器预览数据（防抖后更新）
class EditorPreviewData {
  final String title;
  final List<EditorPreviewBlock> blocks;

  const EditorPreviewData(this.title, this.blocks);

  const EditorPreviewData.empty() : title = '', blocks = const [];

  @override
  bool operator ==(Object other) =>
      other is EditorPreviewData &&
      other.title == title &&
      listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(title, Object.hashAll(blocks));
}

/// 编辑器预览面板 —— **逐锚点**渲染 + 左侧锚点标记槽。
///
/// ## 这套定位为什么不会"越长越偏"
///
/// 预览不再整篇一次渲染，而是**每个锚点一个独立 widget**，各自挂一个
/// [GlobalKey]。于是锚点在渲染树里有了自己的节点：
///
/// * 定位 = `key.currentContext.findRenderObject()` → `localToGlobal`，
///   也就是**直接读**这个 widget 的真实坐标。没有任何估算、没有文字匹配、
///   没有"按比例换算"，所以不存在"算出来的偏移"这回事。
/// * 读取永远发生在**要用的时候**（点标记滚动前 / 画标记前的测量帧），
///   于是图片异步加载把整篇撑开、字体变化、改窗口宽度…一律自动正确，
///   也没有"快照过期"这一说。
/// * 行内标签（`[b]`/`[color]`…）不会移动锚点：锚点是源码切片，
///   标签在切片内部。
///
/// **不自动跟随光标**：光标位置变化只会让标记槽换箭头，滚动完全交给用户
/// （点标记 / 自己滚）。`revealAnchor` 只在用户点标记时被调用。
///
/// 代价：块边界处的空白处理与整篇渲染有差异 —— 整篇渲染会移除紧邻块级标签的
/// `<br>`，但它的标签清单里漏了 `hr`（`bbcode2html_tables.dart` 的四个正则），
/// 于是整篇版在每个 `[hr]` 后多留一个空行。实测（`tool/anchor_fidelity_probe_test.dart`）：
/// 纯段落、连续行、列表/表格/代码、图片（总高一致）**逐像素相同**；
/// 只有 `[hr]` 处差 16px，且 `[hr]` 越多差越多。
///
/// 这不影响定位：锚点的位置是**读**出来的，标记指着哪个锚点就画在哪个锚点上。
class EditorPreview extends StatefulWidget {
  final ValueListenable<EditorPreviewData> data;

  /// 长按预览 → 看原始 BBCode（页面自己取 `_contentCtl.text`）
  final VoidCallback onShowRaw;

  /// 当前锚点（标记槽里显示箭头）；null = 不标注
  final int? activeAnchor;

  /// 点了标记槽里某个锚点（页面据此把编辑区光标挪过去）
  final ValueChanged<int>? onTapAnchor;

  const EditorPreview({
    super.key,
    required this.data,
    required this.onShowRaw,
    this.activeAnchor,
    this.onTapAnchor,
  });

  @override
  EditorPreviewState createState() => EditorPreviewState();
}

class EditorPreviewState extends State<EditorPreview> {
  final _contentKey = GlobalKey();
  final _scrollCtl = ScrollController();

  /// 锚点序号 → key。
  ///
  /// **按序号长期保留**（不随内容变化重建）：换 key 会让对应子树被销毁重建，
  /// 表现就是每次打字图片都重新淡入一次。序号可能指向别的锚点了，但 key 只是
  /// 身份，无妨。
  final _anchorKeys = <int, GlobalKey>{};

  /// 标记槽内容（锚点 → y）。只用于**画**，定位另走 [anchorY]。
  List<BlockMark> _marks = const [];

  bool _measureScheduled = false;
  Timer? _measureDebounce;

  // 内容子树缓存。
  //
  // 改窗口大小时 Flutter 会逐像素重建整页；若每次都重跑 BBCode→HTML→Widget
  // 转换（长帖上百毫秒），拖动窗口就会卡。缓存**同一个 Widget 实例**后，
  // `Element.updateChild` 见到 identical 会直接复用 → 整棵子树不重建，
  // 但**布局照常**执行，所以尺寸变化依然正确。
  Widget? _cachedColumn;
  String? _cachedTitle;
  List<EditorPreviewBlock>? _cachedBlocks;
  Brightness? _cachedBrightness;

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_scheduleMeasure);
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(EditorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      oldWidget.data.removeListener(_scheduleMeasure);
      widget.data.addListener(_scheduleMeasure);
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    widget.data.removeListener(_scheduleMeasure);
    _measureDebounce?.cancel();
    _scrollCtl.dispose();
    super.dispose();
  }

  // ==================== 位置读取（定位的唯一来源） ====================

  GlobalKey _keyOf(int id) => _anchorKeys.putIfAbsent(id, GlobalKey.new);

  /// 锚点在**预览内容坐标系**里的 y；还没挂上渲染树时返回 null。
  ///
  /// 现场读，不缓存 —— 这是"没有过期数据"的全部秘密。
  double? anchorY(int id) {
    if (id < 0) return null;
    final root = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    final box =
        _anchorKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || box == null || !root.hasSize || !box.hasSize) {
      return null;
    }
    return root.globalToLocal(box.localToGlobal(Offset.zero)).dy;
  }

  /// 把某个锚点滚动到视口内。
  ///
  /// 这是**显式**操作（用户点了标记）才调用 —— 光标移动不会走到这里：
  /// 自动跟随滚动已取消，位置完全由用户掌握。
  /// 已经在视野里就不动，避免为几像素而跳一下。
  void revealAnchor(int id) {
    final y = anchorY(id);
    if (y == null || !_scrollCtl.hasClients) return;
    final pos = _scrollCtl.position;
    final viewport = pos.viewportDimension;
    // 上下各留 15% 余量：贴着边缘也算"看得见"
    final margin = viewport * 0.15;
    if (y >= pos.pixels + margin && y <= pos.pixels + viewport - margin) return;
    final target = (y - viewport * 0.3).clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    pos.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  // ==================== 标记槽测量 ====================

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _measure();
    });
  }

  /// 尺寸变化专用：**防抖**后再量。
  ///
  /// 拖动窗口时每帧尺寸都变，逐帧遍历渲染树会把拖动拖卡；等尺寸停下来量一次
  /// 就够了。注意这只是"标记画在哪"的刷新 —— 定位本身永远现场读，不受影响。
  void _scheduleMeasureDebounced() {
    _measureDebounce?.cancel();
    _measureDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _scheduleMeasure();
    });
  }

  void _measure() {
    if (!mounted) return;
    debugMeasureCount++;
    final blocks = widget.data.value.blocks;
    final marks = <BlockMark>[];
    for (var id = 0; id < blocks.length; id++) {
      final y = anchorY(id);
      if (y == null) continue;
      marks.add((id: id, y: y, label: blocks[id].label));
    }
    // 位置没变就别重建：这个回调可能被尺寸变化频繁触发
    if (_sameMarks(_marks, marks)) return;
    setState(() => _marks = marks);
  }

  static bool _sameMarks(List<BlockMark> a, List<BlockMark> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].y != b[i].y) return false;
    }
    return true;
  }

  // ==================== 测试钩子 ====================

  /// 测试用：某锚点的真实 y（预览内容坐标系，与滚动位置无关）
  @visibleForTesting
  double? debugAnchorY(int id) => anchorY(id);

  /// 测试用：某锚点挂在渲染树上的 key（据此断言它真的滚进了视口）
  @visibleForTesting
  GlobalKey? debugAnchorKey(int id) => _anchorKeys[id];

  /// 测试用：当前标记（锚点 → y）
  @visibleForTesting
  List<BlockMark> get debugMarks => _marks;

  /// 测试用：测量执行次数
  @visibleForTesting
  int debugMeasureCount = 0;

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<EditorPreviewData>(
      valueListenable: widget.data,
      builder: (context, data, _) {
        final settings = context.read<SettingsProvider>();
        if (data.title.isEmpty && data.blocks.isEmpty) {
          return Center(
            child: Text(
              '输入内容后即可预览',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          );
        }
        return NotificationListener<ScrollMetricsNotification>(
          // 内容尺寸变了（最典型：正文图片异步加载完成，整篇往下撑开）
          // → 标记要重画。定位不需要重算任何东西，现场读就是准的。
          onNotification: (_) {
            _scheduleMeasureDebounced();
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollCtl,
            padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
            child: Stack(
              children: [
                // 正文用内边距给标记槽让位。
                // 不让标记槽用负偏移：越界的子树能画出来但**点不到**
                // （RenderBox.hitTest 会先判 size.contains）。
                Padding(
                  padding: const EdgeInsets.only(left: kMarkerGutterWidth),
                  // 预览排除出语义树：它是只读的重复内容，帖子详情页才是给屏幕
                  // 阅读器读的那份。整个 App 已在 main.dart 全局关闭无障碍
                  // （见 docs/07 #70），这里是局部兜底 —— 万一那层被撤掉，预览
                  // 这棵"打字时每 300ms 重建一次"的 HTML 语义树也不会再让引擎的
                  // AXTree 反复失效刷屏。手势不受影响：长按、链接点击、选择照常。
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      onLongPress: widget.onShowRaw,
                      // 逐锚点渲染 → 每个块都是独立的 PostHtmlWidget，
                      // 它们各自的 SelectionArea 会把选区切成一段一段
                      // （嵌套选区作用域）。所以这里让它们都不自带，
                      // 由外面这**一个** SelectionArea 统管全文选区。
                      child: SelectionArea(child: _content(data, cs, settings)),
                    ),
                  ),
                ),
                // 标记槽：与正文同一个 Stack（同一坐标系），当前锚点显示箭头
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: BlockMarkerGutter(
                    marks: _marks,
                    activeId: widget.activeAnchor,
                    onTapId: (id) => widget.onTapAnchor?.call(id),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 正文子树（带缓存，见字段注释）
  Widget _content(
    EditorPreviewData data,
    ColorScheme cs,
    SettingsProvider settings,
  ) {
    final cached = _cachedColumn;
    if (cached != null &&
        _cachedTitle == data.title &&
        _cachedBrightness == cs.brightness &&
        listEquals(_cachedBlocks, data.blocks)) {
      return cached;
    }
    _cachedTitle = data.title;
    _cachedBrightness = cs.brightness;
    _cachedBlocks = List.of(data.blocks);
    // 正文变短 → 多出来的 key 作废（不清理会一直堆着）
    _anchorKeys.removeWhere((id, _) => id >= data.blocks.length);

    return _cachedColumn = Column(
      key: _contentKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              data.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        for (var i = 0; i < data.blocks.length; i++)
          // 锚点 = 这个 widget 本身。key 挂在它上面，位置就能直接读出来。
          KeyedSubtree(
            key: _keyOf(i),
            child: PostHtmlWidget(
              bbcode: data.blocks[i].bbcode,
              disabledTags: settings.disabledBbcodeTags,
              autoDetectUrls: settings.autoDetectUrls,
              selectable: false,
            ),
          ),
      ],
    );
  }
}

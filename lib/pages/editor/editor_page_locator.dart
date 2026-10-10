part of 'editor_page.dart';

/// 锚点标记槽与跨区定位 —— 编辑区 ↔ 预览区的"当前锚点"标注与互相跳转。
///
/// ## 对应关系从哪来
///
/// 不来自坐标，来自**锚点身份**：两边都用 [_anchors] 这一份表（
/// `bbAnchors(_session.contentCtl.text)`）。表里第 i 项在两个区指的是同一个结构
/// （第 i 个段落 / 图片 / 引用块…）。于是：
///
/// * 光标偏移 → 锚点 = 锚点表上的二分查找（`bbAnchorIndexAt`）
/// * 锚点 → 编辑区位置 = 问 `RenderEditable` 要该锚点首行的真实光标矩形
/// * 锚点 → 预览位置 = 读该锚点 widget 的 `GlobalKey` 真实坐标
///
/// 全程没有"估算偏移""按文字匹配"。
///
/// ## 行为约定（三条，都是刻意的）
///
/// 1. **不自动滚动**。光标移动只把两个标记槽的箭头换成"当前锚点"，绝不主动
///    滚动预览 —— 位置完全由用户掌握（点标记 / 自己滚）。
/// 2. **段内移动光标零动作**：只在所在锚点变化时才 `setState`。光标每动一下都
///    重建整页（两个标记槽 + 工具栏 + 预览）既费性能，又让 Windows 无障碍桥的
///    AXTree 频繁失效刷屏。
/// 3. 点标记是**显式**操作：移动光标 + 把另一侧滚到该锚点。窄屏（编辑/预览
///    二选一）下顺带切到另一侧，否则点完还停在原处等于没反应；宽屏同屏可见，
///    不切换。
extension on _EditorPageState {
  /// 宽屏 = 编辑区与预览同屏（窄屏是 IndexedStack 二选一）
  bool get _isSplitView => MediaQuery.sizeOf(context).isWide;

  // ==================== 光标/选区变化 ====================

  void _onEditingChanged() {
    final changed = _session.contentCtl.text != _lastSeenText;
    if (changed) {
      _lastSeenText = _session.contentCtl.text;
      // 结构变了才重算锚点表
      _anchors = bbAnchors(_lastSeenText);
    }

    // 只更新"当前锚点"（两个标记槽的箭头）
    final anchor = bbAnchorIndexAt(_anchors, _session.contentCtl.selection.baseOffset);
    if (anchor >= 0 && anchor != _activeAnchor) {
      _setState(() => _activeAnchor = anchor);
    }

    // 软换行位置可能变了（文本改动）→ 重算编辑区标记的 y。防抖，不必每键都量
    if (changed) _scheduleGutterMeasure();
  }

  // ==================== 编辑区标记槽测量 ====================

  void _scheduleGutterMeasure() {
    _gutterMeasureDebounce?.cancel();
    _gutterMeasureDebounce = Timer(
      const Duration(milliseconds: 350),
      _measureEditorGutter,
    );
  }

  /// 宽度变了 → 软换行位置全变，标记位置必须重算（改窗口/旋屏时会走到）
  void _syncGutterMeasureWithWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width != _lastGutterWidth) {
      _lastGutterWidth = width;
      _scheduleGutterMeasure();
    }
  }

  void _measureEditorGutter() {
    if (!mounted || _gutterMeasureScheduled) return;
    _gutterMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gutterMeasureScheduled = false;
      if (!mounted) return;
      _setState(() => _editorMarks = _measureEditorMarks());
    });
  }

  /// 编辑区锚点标记 —— y 由 `RenderEditable` 的真实光标矩形给出
  List<BlockMark> _measureEditorMarks() {
    if (_anchors.isEmpty) return const [];
    final box =
        _editorContentKey.currentContext?.findRenderObject() as RenderBox?;
    final metrics = EditorLineMetrics.measure(
      container: box,
      editableRoot: box,
      lines: bbcodeSourceLines(_session.contentCtl.text),
    );
    return [
      for (final a in _anchors)
        if (metrics.yOf(a.line) != null)
          (id: a.index, y: metrics.yOf(a.line)!, label: a.label),
    ];
  }

  // ==================== 跨区定位（点标记） ====================

  /// 点编辑区标记：光标挪到该锚点开头 + 把预览滚过去。
  ///
  /// 窄屏下顺带切到预览 —— 用户点了标记就是要看那一处。
  void _onEditorGutterTap(int id) {
    final anchor = _anchorOf(id);
    if (anchor == null) return;
    _session.contentCtl.selection = TextSelection.collapsed(offset: anchor.start);
    _setState(() {
      _activeAnchor = id;
      if (!_isSplitView) _showPreview = true;
    });
    // 只在同屏时才抢焦点：窄屏切走后再弹软键盘会盖住预览
    if (_isSplitView) _focusContent();
    _previewKey.currentState?.revealAnchor(id);
  }

  /// 点预览标记：把编辑区光标挪到该锚点开头，并把编辑区滚到看得见。
  ///
  /// 刻意**不抢焦点**：移动端抢焦点会弹软键盘，而用户此刻是在看编辑区之外的东西。
  /// 窄屏下顺带切回编辑区。
  void _onPreviewGutterTap(int id) {
    final anchor = _anchorOf(id);
    if (anchor == null) return;
    _session.contentCtl.selection = TextSelection.collapsed(offset: anchor.start);
    _setState(() {
      _activeAnchor = id;
      if (!_isSplitView) _showPreview = false;
    });
    _revealEditorAnchor(id);
  }

  BbAnchor? _anchorOf(int id) {
    if (id < 0 || id >= _anchors.length) return null;
    return _anchors[id];
  }

  /// 把编辑区滚到某个锚点看得见（y 现算：光标矩形是真实布局结果）。
  /// 已经在视野里就不动 —— 避免为几像素而跳一下。
  void _revealEditorAnchor(int id) {
    if (!_editorScrollCtl.hasClients) return;
    final marks = _measureEditorMarks();
    if (marks.isEmpty) return;
    // 取不大于目标锚点的最后一个标记
    double? y;
    for (final m in marks) {
      if (m.id <= id) {
        y = m.y;
      } else {
        break;
      }
    }
    y ??= marks.first.y;

    final pos = _editorScrollCtl.position;
    final viewport = pos.viewportDimension;
    final margin = viewport * 0.15;
    if (y >= pos.pixels + margin && y <= pos.pixels + viewport - margin) {
      return;
    }
    pos.animateTo(
      (y - viewport * 0.3).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }
}

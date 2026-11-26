import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_table.dart';
import 'markdown_table_strings.dart';
import 'markdown_view.dart';

/// 可交互的 Markdown 表格（实时预览用）。
///
/// 交互约定（参考 Obsidian / 飞书文档的表格）：
/// - 单击单元格：只把**这一个**单元格变成可编辑输入框，不再把整块表格换成源码；
/// - 悬停最后一列右侧：表格右边出现一列带 `+` 的窄条，点击新增一列；
/// - 悬停最后一行下方：表格下方出现一行带 `+` 的窄条，点击新增一行；
/// - 悬停某一列顶部：该列表头出现六点手柄，点击 / 按住即可选中整列；
/// - 选中列（或拖选出的一块矩形单元格）上右键：剪切 / 复制 / 粘贴 /
///   文本格式 / 对齐 / 清空 / 删除；
/// - 单元格内拖动是选中文字（单元格处于编辑态时由输入框自己处理），
///   拖动跨出单元格则改为「按矩形选中单元格」。
class MarkdownTableView extends StatefulWidget {
  const MarkdownTableView({
    super.key,
    required this.markdown,
    this.onChanged,
    this.onTapLink,
  });

  /// 表格源码（整块 Markdown，不带首尾空行）。
  final String markdown;

  /// 表格被修改后回传新的源码；为空表示只读。
  final ValueChanged<String>? onChanged;

  /// 单元格里链接的点击回调（为空时链接只显示样式、不可点）。
  final MarkdownTapLinkCallback? onTapLink;

  @override
  State<MarkdownTableView> createState() => _MarkdownTableViewState();
}

/// MarkdownTapLinkCallback 的签名别名，避免调用方依赖 flutter_markdown_plus。
typedef MarkdownTapLinkCallback = void Function(String text, String? href);

/// 单元格坐标：行号 0 是表头，列号从 0 开始。
@immutable
class _CellRef {
  const _CellRef(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is _CellRef && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

/// 矩形选区，坐标含端点；行号 0 是表头。
@immutable
class _CellRange {
  const _CellRange({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  factory _CellRange.single(int row, int col) =>
      _CellRange(top: row, left: col, bottom: row, right: col);

  factory _CellRange.between(_CellRef a, _CellRef b) => _CellRange(
    top: a.row < b.row ? a.row : b.row,
    left: a.col < b.col ? a.col : b.col,
    bottom: a.row > b.row ? a.row : b.row,
    right: a.col > b.col ? a.col : b.col,
  );

  final int top;
  final int left;
  final int bottom;
  final int right;

  int get rowCount => bottom - top + 1;
  int get colCount => right - left + 1;

  bool contains(int row, int col) =>
      row >= top && row <= bottom && col >= left && col <= right;

  @override
  bool operator ==(Object other) =>
      other is _CellRange &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, left, bottom, right);
}

class _MarkdownTableViewState extends State<MarkdownTableView> {
  /// 表格左右内边距（与阅读视图的 tableCellsPadding 对齐）。
  static const EdgeInsets _cellPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );

  /// 增列窄条宽度 / 增行窄条高度。
  static const double _ghostWidth = 30;
  static const double _ghostHeight = 30;

  /// 鼠标离表格边缘多近时露出「新增行列」窄条。
  static const double _edgeZone = 10;

  /// 表头顶部多高的一条带触发「整列手柄」。
  static const double _columnHandleBand = 18;

  /// 表头上方留给六点手柄的高度。
  static const double _gripBand = 16;

  late MarkdownTable _model;

  /// 当前矩形选区（null 表示没有选区）。
  _CellRange? _selection;

  /// 正在编辑的单元格。
  _CellRef? _editingCell;

  /// 进入编辑前该单元格的文本（Esc 取消时回滚）。
  String _editStartText = '';

  /// 单击单元格时光标落点（相对单元格的坐标），用于估算插入位置。
  Offset? _pendingTapOffset;

  final TextEditingController _cellController = TextEditingController();
  late final FocusNode _cellFocus;

  /// 表格整体、行、单元格的几何信息（用于鼠标命中测试）。
  final GlobalKey _rootKey = GlobalKey();
  final GlobalKey _gridKey = GlobalKey();
  final Map<int, GlobalKey> _cellKeys = {};

  /// 正在把编辑态从一个单元格搬到另一个单元格（Tab / Enter 跳格）。
  bool _switchingCell = false;

  /// 点了六点手柄（选中整列）后，紧接着落在同一位置的单元格 tap 要忽略，
  /// 否则会立刻进入表头单元格编辑、把刚选中的整列选区清掉。
  bool _ignoreNextCellTap = false;

  /// 悬停状态：整列手柄的列号、是否贴近右 / 下边缘。
  int? _hoverColumn;
  bool _hoverRightEdge = false;
  bool _hoverBottomEdge = false;

  /// 指针按下 / 拖选状态。
  bool _pointerActive = false;
  _CellRef? _pressCell;
  Offset _pressPosition = Offset.zero;
  bool _rangeDragging = false;
  _CellRef? _lastDragCell;

  /// 右键菜单。
  final MenuController _menuController = MenuController();
  Offset? _pendingMenuGlobal;

  @override
  void initState() {
    super.initState();
    _model =
        MarkdownTable.tryParse(widget.markdown) ??
        MarkdownTable(header: const [''], alignments: const [], rows: const []);
    _cellFocus = FocusNode(onKeyEvent: _handleCellKeyEvent);
    _cellController.addListener(_handleCellTextChanged);
    _cellFocus.addListener(_handleCellFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MarkdownTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.markdown, oldWidget.markdown)) return;
    if (widget.markdown == _model.toMarkdown()) return;
    final next = MarkdownTable.tryParse(widget.markdown);
    if (next == null) return;
    _model = next;
    _clampSelection();
  }

  @override
  void dispose() {
    _cellController
      ..removeListener(_handleCellTextChanged)
      ..dispose();
    _cellFocus
      ..removeListener(_handleCellFocusChanged)
      ..dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 编辑态
  // ---------------------------------------------------------------------------

  void _handleCellTextChanged() {
    final cell = _editingCell;
    if (cell == null) return;
    final text = _cellController.text;
    if (_model.cellAt(cell.row, cell.col) == text) return;
    _commit(_model.withCell(cell.row, cell.col, text));
  }

  void _handleCellFocusChanged() {
    if (_cellFocus.hasFocus) return;
    if (_editingCell == null) return;
    // 跳格时焦点由本组件自己接管：这一帧的失焦是切换过程中的中间态。
    if (_switchingCell) return;
    _finishEditing();
  }

  /// 让某个单元格进入编辑态（光标尽量落在点击位置附近）。
  void _beginEdit(int row, int col) {
    if (_ignoreNextCellTap) {
      _ignoreNextCellTap = false;
      return;
    }
    if (widget.onChanged == null) return;
    final current = _editingCell;
    if (current != null && current.row == row && current.col == col) return;
    _finishEditing();
    final text = _model.cellAt(row, col);
    final caret = _estimateCaretOffset(text, row, col);
    _editStartText = text;
    _cellController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    setState(() {
      _editingCell = _CellRef(row, col);
      _selection = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_editingCell != null) _cellFocus.requestFocus();
    });
  }

  /// 编辑态下的键盘操作（与表格软件一致）：
  /// - `Esc` 取消本次编辑并收起输入框；
  /// - `Enter` 提交并跳到下一行同一列；
  /// - `Tab` / `Shift+Tab` 提交并跳到右 / 左一个单元格。
  KeyEventResult _handleCellKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final cell = _editingCell;
    if (cell == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _finishEditing(commit: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final next = _neighborCell(cell, rowStep: 1, colStep: 0);
      if (next == null) {
        _finishEditing();
      } else {
        _switchEditingTo(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      final backwards = HardwareKeyboard.instance.isShiftPressed;
      final next = _neighborCell(
        cell,
        rowStep: 0,
        colStep: backwards ? -1 : 1,
      );
      if (next == null) {
        _finishEditing();
      } else {
        _switchEditingTo(next);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 相邻单元格（越过末列 / 末行时回到下一行的行首 / 第一行行首）。
  _CellRef? _neighborCell(
    _CellRef cell, {
    required int rowStep,
    required int colStep,
  }) {
    final columns = _model.columnCount;
    final rows = _model.totalRowCount;
    if (columns == 0 || rows == 0) return null;
    var row = cell.row + rowStep;
    var col = cell.col + colStep;
    if (colStep != 0) {
      if (col < 0) col = 0;
      if (col >= columns) col = columns - 1;
    }
    if (rowStep != 0 && row >= rows) row = rows - 1;
    if (row < 0) row = 0;
    return _CellRef(row, col);
  }

  /// 退出编辑态；[commit] 为 false 时回滚到进入编辑前的文本。
  ///
  /// [detachFocus] 为 false 时把焦点留在输入框上（Tab / Enter 跳到相邻单元格）：
  /// 先 unfocus 再立刻给新单元格 requestFocus 会收到一次「迟到的」失焦通知，
  /// 等它到达时 `_editingCell` 已经是新单元格了，于是又被误收起。
  void _finishEditing({bool commit = true, bool detachFocus = true}) {
    final cell = _editingCell;
    if (cell == null) return;
    if (!commit && _cellController.text != _editStartText) {
      _cellController.value = TextEditingValue(
        text: _editStartText,
        selection: TextSelection.collapsed(offset: _editStartText.length),
      );
      _commit(_model.withCell(cell.row, cell.col, _editStartText));
    }
    setState(() => _editingCell = null);
    if (detachFocus) _cellFocus.unfocus();
  }

  /// 把编辑态从当前单元格切到相邻单元格（Tab / Enter）。
  void _switchEditingTo(_CellRef next) {
    _switchingCell = true;
    _finishEditing(detachFocus: false);
    _beginEdit(next.row, next.col);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _switchingCell = false;
    });
  }

  /// 估算点击位置对应的源码插入点。
  ///
  /// 用编辑态的等宽样式做 TextPainter 命中测试；因为渲染态隐藏了 Markdown 标记，
  /// 这只在纯文本单元格里精确，带标记的单元格只能落在附近，但比「永远在末尾」好。
  int _estimateCaretOffset(String text, int row, int col) {
    final tap = _pendingTapOffset;
    _pendingTapOffset = null;
    if (tap == null || text.isEmpty) return text.length;
    final box = _cellBox(row, col);
    final width = box != null && box.hasSize
        ? box.size.width - _cellPadding.horizontal
        : 240.0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _editingTextStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width > 32 ? width : 32);
    final offset = painter.getPositionForOffset(
      Offset(
        tap.dx - _cellPadding.left,
        tap.dy - _cellPadding.top,
      ),
    );
    painter.dispose();
    return offset.offset.clamp(0, text.length);
  }

  TextStyle _editingTextStyle(BuildContext context) => TextStyle(
    fontFamily: 'monospace',
    fontSize: 12.5,
    height: 1.45,
    color: Theme.of(context).colorScheme.onSurface,
  );

  // ---------------------------------------------------------------------------
  // 修改与回写
  // ---------------------------------------------------------------------------

  void _commit(MarkdownTable next) {
    setState(() {
      _model = next;
      _clampSelection();
    });
    widget.onChanged?.call(next.toMarkdown());
  }

  /// 行列被删减后把选区收进新范围，避免越界高亮。
  void _clampSelection() {
    final selection = _selection;
    if (selection == null) return;
    if (_model.columnCount == 0) {
      _selection = null;
      return;
    }
    final top = selection.top.clamp(0, _model.totalRowCount - 1);
    final bottom = selection.bottom.clamp(top, _model.totalRowCount - 1);
    final left = selection.left.clamp(0, _model.columnCount - 1);
    final right = selection.right.clamp(left, _model.columnCount - 1);
    _selection = _CellRange(top: top, left: left, bottom: bottom, right: right);
    final editing = _editingCell;
    if (editing != null &&
        (editing.row >= _model.totalRowCount || editing.col >= _model.columnCount)) {
      _editingCell = null;
    }
  }

  void _addColumnRight() {
    _finishEditing();
    _commit(_model.insertColumn(_model.columnCount));
  }

  void _addRowBelow() {
    _finishEditing();
    _commit(_model.insertRow(_model.bodyRowCount));
  }

  // ---------------------------------------------------------------------------
  // 选区与指针
  // ---------------------------------------------------------------------------

  RenderBox? get _gridBox {
    final context = _gridKey.currentContext;
    if (context == null) return null;
    final object = context.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  RenderBox? _cellBox(int row, int col) {
    final key = _cellKeys[row * 1000 + col];
    final context = key?.currentContext;
    if (context == null) return null;
    final object = context.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  /// 全局坐标命中的单元格；表格之外返回 null。
  _CellRef? _cellAtGlobal(Offset global) {
    final grid = _gridBox;
    if (grid == null || _model.columnCount == 0) return null;
    final gridTopLeft = grid.localToGlobal(Offset.zero);
    final gridSize = grid.size;
    if (global.dx < gridTopLeft.dx ||
        global.dx > gridTopLeft.dx + gridSize.width ||
        global.dy < gridTopLeft.dy ||
        global.dy > gridTopLeft.dy + gridSize.height) {
      return null;
    }
    int? row;
    for (var r = 0; r < _model.totalRowCount; r++) {
      final box = _cellBox(r, 0);
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (global.dy >= top && global.dy < top + box.size.height) {
        row = r;
        break;
      }
    }
    if (row == null) return null;
    final columnWidth = gridSize.width / _model.columnCount;
    final col = ((global.dx - gridTopLeft.dx) / columnWidth)
        .floor()
        .clamp(0, _model.columnCount - 1);
    return _CellRef(row, col);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryButton) == 0) return;
    _pointerActive = true;
    _pressPosition = event.position;
    _pressCell = _cellAtGlobal(event.position);
    _rangeDragging = false;
    _lastDragCell = _pressCell;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointerActive) return;
    // 触摸端拖拽用于滚动正文，不做单元格框选；触屏用长按 / 右键菜单操作。
    if (event.kind == PointerDeviceKind.touch) return;
    if ((event.buttons & kPrimaryButton) == 0) return;
    final press = _pressCell;
    if (press == null) return;
    if (!_rangeDragging &&
        (event.position - _pressPosition).distance < 6) {
      return;
    }
    final cell = _cellAtGlobal(event.position);
    if (!_rangeDragging) {
      // 还在按下的单元格里：交给输入框自己选文字。
      if (cell != null && cell == press) return;
      _rangeDragging = true;
      if (_editingCell != null) _finishEditing();
    }
    final target = cell ?? _lastDragCell ?? press;
    _lastDragCell = target;
    final next = _CellRange.between(press, target);
    if (next != _selection) {
      setState(() => _selection = next);
    }
  }

  void _handlePointerUp() {
    _pointerActive = false;
    _pressCell = null;
    _lastDragCell = null;
    _rangeDragging = false;
  }

  void _selectColumn(int col) {
    _finishEditing();
    setState(() {
      _selection = _CellRange(
        top: 0,
        left: col,
        bottom: _model.totalRowCount - 1,
        right: col,
      );
    });
  }

  void _handleSecondaryTap(int row, int col, Offset globalPosition) {
    // 只读表格（阅读视图 / 来源正文）：不弹编辑菜单，把手势留给外层的
    // SelectionArea（右键 / 长按出系统复制菜单）。
    if (widget.onChanged == null) return;
    _finishEditing();
    final selection = _selection;
    // 无条件 setState：右键落在已选中的单元格上时也要重建一帧，
    // 否则下面注册的 post-frame 回调没有帧可跑，菜单就永远弹不出来。
    setState(() {
      if (selection == null || !selection.contains(row, col)) {
        _selection = _CellRange.single(row, col);
      }
    });
    _pendingMenuGlobal = globalPosition;
    // 等这一帧的 setState 生效，菜单才能读到最新选区
    //（菜单项里的对勾与禁用状态按上一次构建渲染）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final global = _pendingMenuGlobal;
      final rootBox = _rootKey.currentContext?.findRenderObject();
      if (global == null || rootBox is! RenderBox) return;
      _menuController.open(position: rootBox.globalToLocal(global));
    });
  }

  // ---------------------------------------------------------------------------
  // 悬停（增行 / 增列 / 整列手柄）
  // ---------------------------------------------------------------------------

  void _handleHover(PointerHoverEvent event) {
    final grid = _gridBox;
    final root = _rootKey.currentContext?.findRenderObject();
    if (grid == null || root is! RenderBox || !root.hasSize) return;
    final local = root.globalToLocal(event.position);
    final gridOrigin = root.globalToLocal(grid.localToGlobal(Offset.zero));
    final gridRect = gridOrigin & grid.size;
    final rootRect = Offset.zero & root.size;
    final columns = _model.columnCount;
    final editable = widget.onChanged != null;

    int? hoverColumn;
    // 「列的顶部边缘」= 表头单元格最上面的一条带：命中后表头里露出六点手柄。
    final headerBox = _cellBox(0, 0);
    if (editable && columns > 0 && headerBox != null) {
      final headerOrigin = root.globalToLocal(
        headerBox.localToGlobal(Offset.zero),
      );
      final top = headerOrigin.dy;
      if (local.dx >= gridRect.left &&
          local.dx <= gridRect.right &&
          local.dy >= top &&
          local.dy <= top + _columnHandleBand) {
        hoverColumn = ((local.dx - gridRect.left) / (gridRect.width / columns))
            .floor()
            .clamp(0, columns - 1);
      }
    }

    // 增列 / 增行窄条显隐带**迟滞**：窄条一出现，表格就让出 30 像素，
    // 若仍按「离表格右边缘多近」判断，指针会瞬间落到窄条外面，
    // 于是窄条反复显示/消失（表现为悬停闪烁、点不中）。
    // 规则：未显示时按表格边缘判定；已显示时只要指针还在根部区域内就保持。
    final bool nearRight;
    if (_hoverRightEdge) {
      nearRight = local.dx <= rootRect.right - 1;
    } else {
      nearRight =
          editable &&
          local.dy >= gridRect.top - 4 &&
          local.dy <= gridRect.bottom + 4 &&
          local.dx >= gridRect.right - _edgeZone &&
          local.dx <= rootRect.right + 1;
    }
    final bool nearBottom;
    if (_hoverBottomEdge) {
      nearBottom = local.dy <= rootRect.bottom - 1;
    } else {
      nearBottom =
          editable &&
          local.dx >= gridRect.left - 4 &&
          local.dx <= gridRect.right + 4 &&
          local.dy >= gridRect.bottom - _edgeZone &&
          local.dy <= rootRect.bottom + 1;
    }
    if (hoverColumn == _hoverColumn &&
        nearRight == _hoverRightEdge &&
        nearBottom == _hoverBottomEdge) {
      return;
    }
    setState(() {
      _hoverColumn = hoverColumn;
      _hoverRightEdge = nearRight;
      _hoverBottomEdge = nearBottom;
    });
  }

  void _clearHover() {
    if (_hoverColumn == null && !_hoverRightEdge && !_hoverBottomEdge) return;
    setState(() {
      _hoverColumn = null;
      _hoverRightEdge = false;
      _hoverBottomEdge = false;
    });
  }

  // ---------------------------------------------------------------------------
  // 右键菜单
  // ---------------------------------------------------------------------------

  /// 选区覆盖整列（含表头到最后一行）。
  bool get _selectionIsFullColumns {
    final selection = _selection;
    return selection != null &&
        selection.top == 0 &&
        selection.bottom == _model.totalRowCount - 1;
  }

  /// 选区覆盖整行（从第一列到最后一列）。
  bool get _selectionIsFullRows {
    final selection = _selection;
    return selection != null &&
        selection.left == 0 &&
        selection.right == _model.columnCount - 1;
  }

  List<List<String>> _selectionGrid() {
    final selection = _selection;
    if (selection == null) return const [];
    return [
      for (var row = selection.top; row <= selection.bottom; row++)
        [
          for (var col = selection.left; col <= selection.right; col++)
            _model.cellAt(row, col),
        ],
    ];
  }

  Future<void> _copySelection({required bool cut}) async {
    final selection = _selection;
    if (selection == null) return;
    final text = MarkdownTableClipboard.encode(_selectionGrid());
    await Clipboard.setData(ClipboardData(text: text));
    if (!cut) return;
    _clearSelectionCells();
  }

  Future<void> _pasteSelection() async {
    final selection = _selection;
    if (selection == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    final grid = MarkdownTableClipboard.decode(text);
    if (grid.isEmpty) return;
    var next = _model;
    final neededRows = selection.top + grid.length;
    if (neededRows > next.totalRowCount) {
      // 行号 0 是表头，缺的行补在表格末尾。
      for (var i = next.totalRowCount; i < neededRows; i++) {
        next = next.insertRow(next.bodyRowCount);
      }
    }
    final neededColumns =
        selection.left +
        grid.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    while (next.columnCount < neededColumns) {
      next = next.insertColumn(next.columnCount);
    }
    for (var row = 0; row < grid.length; row++) {
      for (var col = 0; col < grid[row].length; col++) {
        next = next.withCell(
          (selection.top + row).clamp(0, next.totalRowCount - 1),
          (selection.left + col).clamp(0, next.columnCount - 1),
          grid[row][col],
        );
      }
    }
    _commit(next);
    setState(() {
      _selection = _CellRange(
        top: selection.top,
        left: selection.left,
        bottom: (selection.top + grid.length - 1).clamp(0, _model.totalRowCount - 1),
        right: (selection.left + neededColumns - selection.left - 1)
            .clamp(selection.left, _model.columnCount - 1),
      );
    });
  }

  void _clearSelectionCells() {
    final selection = _selection;
    if (selection == null) return;
    var next = _model;
    for (var row = selection.top; row <= selection.bottom; row++) {
      for (var col = selection.left; col <= selection.right; col++) {
        next = next.withCell(row, col, '');
      }
    }
    _commit(next);
  }

  /// 删除选中区域：
  /// - 选中整列（表头到末行）→ 删除这些列；
  /// - 选中整行（首列到末列）→ 删除这些行；
  /// - 其它矩形 → Markdown 表格不能挖洞，按「清空内容」处理。
  void _deleteSelection() {
    final selection = _selection;
    if (selection == null) return;
    if (_selectionIsFullColumns) {
      _commit(_model.removeColumns(selection.left, selection.right));
      _selection = null;
    } else if (_selectionIsFullRows) {
      if (selection.bottom == 0) {
        // 只选中表头行：没有可删除的数据行，清空表头内容。
        _clearSelectionCells();
      } else {
        _commit(_model.removeRows(selection.top - 1, selection.bottom - 1));
        _selection = null;
      }
    } else {
      _clearSelectionCells();
    }
  }

  void _applyAlignment(MarkdownTableAlign align) {
    final selection = _selection;
    if (selection == null) return;
    var next = _model;
    for (var col = selection.left; col <= selection.right; col++) {
      next = next.withColumnAlign(col, align);
    }
    _commit(next);
  }

  MarkdownTableAlign? get _selectionAlignment {
    final selection = _selection;
    if (selection == null) return null;
    final first = _model.alignments[selection.left];
    for (var col = selection.left; col <= selection.right; col++) {
      if (_model.alignments[col] != first) return null;
    }
    return first;
  }

  void _toggleFormat(String marker) {
    final selection = _selection;
    if (selection == null) return;
    var next = _model;
    for (var row = selection.top; row <= selection.bottom; row++) {
      for (var col = selection.left; col <= selection.right; col++) {
        final text = next.cellAt(row, col);
        if (text.isEmpty) continue;
        final wrapped =
            text.length >= marker.length * 2 &&
            text.startsWith(marker) &&
            text.endsWith(marker);
        next = next.withCell(
          row,
          col,
          wrapped
              ? text.substring(marker.length, text.length - marker.length)
              : '$marker$text$marker',
        );
      }
    }
    _commit(next);
  }

  void _clearFormat() {
    final selection = _selection;
    if (selection == null) return;
    var next = _model;
    for (var row = selection.top; row <= selection.bottom; row++) {
      for (var col = selection.left; col <= selection.right; col++) {
        next = next.withCell(row, col, _stripInlineFormat(next.cellAt(row, col)));
      }
    }
    _commit(next);
  }

  static String _stripInlineFormat(String text) {
    var value = text;
    var changed = true;
    const markers = ['**', '__', '~~', '`', '*', '_'];
    while (changed) {
      changed = false;
      for (final marker in markers) {
        if (value.length >= marker.length * 2 &&
            value.startsWith(marker) &&
            value.endsWith(marker)) {
          value = value.substring(marker.length, value.length - marker.length);
          changed = true;
        }
      }
    }
    return value;
  }

  void _insertRowAbove() {
    final selection = _selection;
    if (selection == null) return;
    _commit(_model.insertRow((selection.top - 1).clamp(0, _model.bodyRowCount)));
  }

  void _insertRowBelow() {
    final selection = _selection;
    if (selection == null) return;
    _commit(_model.insertRow((selection.bottom).clamp(0, _model.bodyRowCount)));
  }

  void _insertColumnLeft() {
    final selection = _selection;
    if (selection == null) return;
    _commit(_model.insertColumn(selection.left));
  }

  void _insertColumnRight() {
    final selection = _selection;
    if (selection == null) return;
    _commit(_model.insertColumn(selection.right + 1));
  }

  List<Widget> _buildMenuChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSelection = _selection != null;
    final align = _selectionAlignment;
    Widget alignItem(MarkdownTableAlign value, IconData icon, String label) {
      return MenuItemButton(
        leadingIcon: Icon(icon, size: 18),
        trailingIcon: align == value
            ? Icon(Icons.check, size: 16, color: scheme.primary)
            : null,
        onPressed: () => _applyAlignment(value),
        child: Text(label),
      );
    }

    return [
      MenuItemButton(
        leadingIcon: const Icon(Icons.content_cut, size: 18),
        onPressed: hasSelection ? () => _copySelection(cut: true) : null,
        child: const Text(MarkdownTableStrings.menuCut),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.content_copy, size: 18),
        onPressed: hasSelection ? () => _copySelection(cut: false) : null,
        child: const Text(MarkdownTableStrings.menuCopy),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.content_paste, size: 18),
        onPressed: hasSelection ? _pasteSelection : null,
        child: const Text(MarkdownTableStrings.menuPaste),
      ),
      const Divider(height: 1),
      SubmenuButton(
        leadingIcon: const Icon(Icons.text_format, size: 18),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(Icons.format_bold, size: 18),
            onPressed: hasSelection
                ? () => _toggleFormat('**')
                : null,
            child: const Text(MarkdownTableStrings.formatBold),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.format_italic, size: 18),
            onPressed: hasSelection ? () => _toggleFormat('*') : null,
            child: const Text(MarkdownTableStrings.formatItalic),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.format_strikethrough, size: 18),
            onPressed: hasSelection ? () => _toggleFormat('~~') : null,
            child: const Text(MarkdownTableStrings.formatStrike),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.code, size: 18),
            onPressed: hasSelection ? () => _toggleFormat('`') : null,
            child: const Text(MarkdownTableStrings.formatCode),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.format_clear, size: 18),
            onPressed: hasSelection ? _clearFormat : null,
            child: const Text(MarkdownTableStrings.formatClear),
          ),
        ],
        child: const Text(MarkdownTableStrings.menuFormat),
      ),
      const Divider(height: 1),
      alignItem(MarkdownTableAlign.left, Icons.format_align_left, MarkdownTableStrings.alignLeft),
      alignItem(
        MarkdownTableAlign.center,
        Icons.format_align_center,
        MarkdownTableStrings.alignCenter,
      ),
      alignItem(
        MarkdownTableAlign.right,
        Icons.format_align_right,
        MarkdownTableStrings.alignRight,
      ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.add_box_outlined, size: 18),
        onPressed: hasSelection ? _insertRowAbove : null,
        child: const Text(MarkdownTableStrings.insertRowAbove),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.add_box_outlined, size: 18),
        onPressed: hasSelection ? _insertRowBelow : null,
        child: const Text(MarkdownTableStrings.insertRowBelow),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.view_column_outlined, size: 18),
        onPressed: hasSelection ? _insertColumnLeft : null,
        child: const Text(MarkdownTableStrings.insertColumnLeft),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.view_column_outlined, size: 18),
        onPressed: hasSelection ? _insertColumnRight : null,
        child: const Text(MarkdownTableStrings.insertColumnRight),
      ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.backspace_outlined, size: 18),
        onPressed: hasSelection ? _clearSelectionCells : null,
        child: const Text(MarkdownTableStrings.menuClearCells),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.delete_outline, size: 18),
        onPressed: hasSelection ? _deleteSelection : null,
        child: const Text(MarkdownTableStrings.menuDeleteCells),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styleSheet = buildMarkdownStyleSheet(theme);
    final bodyStyle =
        styleSheet.tableBody ?? theme.textTheme.bodySmall ?? const TextStyle();
    final headStyle = styleSheet.tableHead ?? bodyStyle;
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 悬停时右侧要让出增列窄条的位置，否则窄条会把表格挤出去（横向溢出）。
        final ghostSpace = _hoverRightEdge && widget.onChanged != null
            ? _ghostWidth
            : 0.0;
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 600.0;
        final width = (available - ghostSpace).clamp(160.0, available);
        final rows = <TableRow>[
          for (var row = 0; row < _model.totalRowCount; row++)
            TableRow(
              children: [
                for (var col = 0; col < _model.columnCount; col++)
                  _buildCell(row, col, bodyStyle, headStyle),
              ],
            ),
        ];
        final table = Table(
          key: _gridKey,
          defaultColumnWidth: const FlexColumnWidth(),
          // 不能用 fill：RenderTable 的 fill 单元格在第一遍测量时被跳过，
          // 行高会永远是 0（整张表塌成一条线）；middle 与默认 Markdown 表格一致。
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(color: scheme.outlineVariant, width: 0.7),
          children: rows,
        );
        final grid = Container(
          width: width,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: table,
        );

        final gridWidth = width;
        final ghostRight = _hoverRightEdge && widget.onChanged != null
            ? Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _ghostWidth,
                child: _buildAddColumn(scheme),
              )
            : null;

        // 整列手柄画在表头**上方**的悬浮带里，而不是塞进单元格内：
        // Flutter 不会对伸出父级边界的子树做命中测试，画在单元格内部的
        // `top: -8` 上看着正常却点不到。
        final hoverColumn = _hoverColumn;
        final columnWidth = gridWidth / _model.columnCount;
        final gripOverlay = hoverColumn == null || widget.onChanged == null
            ? null
            : Positioned(
                top: 0,
                left: hoverColumn * columnWidth,
                width: columnWidth,
                child: Center(
                  child: _ColumnGrip(
                    onSelect: () {
                      // 手柄压在表头单元格之上：拦下紧随其后的单元格 tap，
                      // 否则刚选中的整列会被「进入表头编辑」清掉。
                      _ignoreNextCellTap = true;
                      _selectColumn(hoverColumn);
                    },
                  ),
                ),
              );

        final tableArea = Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.only(top: _gripBand, right: ghostSpace),
              child: grid,
            ),
            if (gripOverlay != null) gripOverlay,
            if (ghostRight != null) ghostRight,
          ],
        );

        final addRow = _hoverBottomEdge && widget.onChanged != null
            ? Padding(
                padding: EdgeInsets.only(
                  top: 4,
                  right: _hoverRightEdge ? _ghostWidth : 0,
                ),
                child: _buildAddRow(scheme),
              )
            : null;

        return MenuAnchor(
          controller: _menuController,
          menuChildren: _buildMenuChildren(context),
          child: MouseRegion(
            key: _rootKey,
            onHover: _handleHover,
            onExit: (_) => _clearHover(),
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: (_) => _handlePointerUp(),
              onPointerCancel: (_) => _handlePointerUp(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  tableArea,
                  if (addRow != null) addRow,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddColumn(ColorScheme scheme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: MarkdownTableStrings.addColumnRight,
        waitDuration: const Duration(milliseconds: 80),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _addColumnRight,
          child: Container(
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant, width: 0.7),
            ),
            child: Center(
              child: Icon(Icons.add, size: 16, color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddRow(ColorScheme scheme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: MarkdownTableStrings.addRowBelow,
        waitDuration: const Duration(milliseconds: 80),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _addRowBelow,
          child: Container(
            height: _ghostHeight,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant, width: 0.7),
            ),
            child: Center(
              child: Icon(Icons.add, size: 16, color: scheme.primary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(
    int row,
    int col,
    TextStyle bodyStyle,
    TextStyle headStyle,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final editable = widget.onChanged != null;
    final header = row == 0;
    final editing =
        _editingCell != null &&
        _editingCell!.row == row &&
        _editingCell!.col == col;
    final selection = _selection;
    final selected = selection != null && selection.contains(row, col);
    final align = _model.alignments[col];
    final alignment = switch (align) {
      MarkdownTableAlign.center => Alignment.center,
      MarkdownTableAlign.right => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    final textAlign = switch (align) {
      MarkdownTableAlign.center => TextAlign.center,
      MarkdownTableAlign.right => TextAlign.right,
      _ => TextAlign.left,
    };
    final baseStyle = header ? headStyle : bodyStyle;

    final Widget content = editing
        ? SizedBox(
            width: double.infinity,
            child: TextField(
              controller: _cellController,
              focusNode: _cellFocus,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              textAlign: textAlign,
              style: _editingTextStyle(context),
              decoration: const InputDecoration(
                isCollapsed: true,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _finishEditing(),
              onTapOutside: (_) => _finishEditing(),
            ),
          )
        : Text.rich(
            _cellSpan(_model.cellAt(row, col), baseStyle),
            textAlign: textAlign,
            style: baseStyle,
          );

    final cellBody = Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: _cellPadding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
      ),
      child: content,
    );

    final decorated = Stack(
      clipBehavior: Clip.none,
      children: [
        cellBody,
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: _selectionBorder(selection, row, col, scheme),
                ),
              ),
            ),
          ),
      ],
    );

    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Listener(
        key: _cellKeys.putIfAbsent(
          row * 1000 + col,
          () => GlobalKey(debugLabel: 'md-table-$row-$col'),
        ),
        // 只读表格（阅读视图 / 来源正文 / 对话）不挂任何手势：外层的
        // SelectionArea 要靠拖动与长按做文字选择，多一个 GestureDetector
        // 会把长按抢过去，手机上就再也选不中表格里的字了。
        child: editable
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: editing
                    ? null
                    : (details) => _pendingTapOffset = details.localPosition,
                onTap: editing ? null : () => _beginEdit(row, col),
                onSecondaryTapDown: (details) =>
                    _handleSecondaryTap(row, col, details.globalPosition),
                // 触屏没有右键：长按单元格等效于右键（选中并弹出操作菜单），
                // 否则手机上完全够不到剪切 / 复制 / 插入行列这些操作。
                onLongPressStart: (details) =>
                    _handleSecondaryTap(row, col, details.globalPosition),
                child: decorated,
              )
            : decorated,
      ),
    );
  }

  Border _selectionBorder(
    _CellRange selection,
    int row,
    int col,
    ColorScheme scheme,
  ) {
    const none = BorderSide(width: 0, color: Colors.transparent);
    final accent = BorderSide(color: scheme.primary, width: 1.6);
    return Border(
      top: row == selection.top ? accent : none,
      bottom: row == selection.bottom ? accent : none,
      left: col == selection.left ? accent : none,
      right: col == selection.right ? accent : none,
    );
  }

  /// 把单元格文本渲染成富文本（加粗 / 斜体 / 行内代码 / 删除线 / 链接文字）。
  ///
  /// 用 `markdown` 的行内解析器而不是自己写正则：单元格里允许出现 `\|` 转义、
  /// 嵌套强调与行内代码，手写解析很容易在边角上出错。
  TextSpan _cellSpan(String source, TextStyle base) {
    if (source.isEmpty) return TextSpan(text: '', style: base);
    final theme = Theme.of(context);
    final sheet = buildMarkdownStyleSheet(theme);
    final codeStyle = (sheet.code ?? const TextStyle(fontFamily: 'monospace'))
        .copyWith(fontSize: (base.fontSize ?? 12) * 1.02);
    final linkStyle =
        sheet.a ?? TextStyle(color: theme.colorScheme.primary);
    final document = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    );
    final nodes = document.parseInline(transformWikiLinks(source));
    return TextSpan(
      style: base,
      children: _inlineSpans(nodes, base, codeStyle, linkStyle),
    );
  }

  List<InlineSpan> _inlineSpans(
    List<md.Node> nodes,
    TextStyle style,
    TextStyle codeStyle,
    TextStyle linkStyle,
  ) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style));
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'strong':
          spans.addAll(
            _inlineSpans(
              children,
              style.copyWith(fontWeight: FontWeight.w700),
              codeStyle,
              linkStyle,
            ),
          );
        case 'em':
          spans.addAll(
            _inlineSpans(
              children,
              style.copyWith(fontStyle: FontStyle.italic),
              codeStyle,
              linkStyle,
            ),
          );
        case 'del':
          spans.addAll(
            _inlineSpans(
              children,
              style.copyWith(decoration: TextDecoration.lineThrough),
              codeStyle,
              linkStyle,
            ),
          );
        case 'code':
          spans.add(TextSpan(text: node.textContent, style: codeStyle));
        case 'a':
          spans.addAll(
            _inlineSpans(children, linkStyle, codeStyle, linkStyle),
          );
        case 'img':
          final alt = node.attributes['alt'];
          if (alt != null && alt.isNotEmpty) {
            spans.add(TextSpan(text: alt, style: style));
          }
        case 'br':
          spans.add(const TextSpan(text: '\n'));
        default:
          spans.addAll(_inlineSpans(children, style, codeStyle, linkStyle));
      }
    }
    return spans;
  }
}

/// 表头正上方的六点手柄；按下即选中整列。
class _ColumnGrip extends StatelessWidget {
  const _ColumnGrip({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: MarkdownTableStrings.selectColumn,
      waitDuration: const Duration(milliseconds: 80),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onSelect(),
          child: Container(
            height: 14,
            width: 24,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant, width: 0.7),
            ),
            child: Icon(
              Icons.drag_indicator,
              size: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

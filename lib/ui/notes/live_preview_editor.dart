import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import 'editor_strings.dart';
import 'markdown_blocks.dart';
import 'markdown_outline.dart';
import 'markdown_toolbar.dart';
import 'markdown_view.dart';

/// 实时预览（Live Preview）编辑器。
///
/// 灵感来自 Obsidian：正文始终以渲染态呈现，**点按某个段落**时只把该段
/// 就地替换成 Markdown 源码供编辑，其余段落保持渲染。源码不使用卡片/边框
/// 包装、也没有「完成」按钮：点击别处（输入框失焦）即自动收起，回到渲染态。
/// 任务列表的复选框在渲染态可直接勾选。
///
/// 数据流：本组件不持有整篇正文，而是直接读写传入的 [controller]；
/// 编辑某段时把该段源码写回整篇正文对应的偏移区间，因此保存、字数统计、
/// 未保存拦截等既有逻辑全部复用。
class LivePreviewEditor extends StatefulWidget {
  const LivePreviewEditor({
    super.key,
    required this.controller,
    this.onToggleTask,
    this.onBlockActivated,
    this.jump,
  });

  /// 整篇笔记正文的控制器（与源码模式共用）。
  final TextEditingController controller;

  /// 切换任务复选框；参数为全篇任务项序号。
  final ValueChanged<int>? onToggleTask;

  /// 某一段被展开为源码时回调（含其源码起始偏移），供大纲高亮跟随。
  final ValueChanged<MarkdownBlock>? onBlockActivated;

  /// 大纲跳转请求：滚动到该偏移量所在段落。
  final OutlineJumpRequest? jump;

  @override
  State<LivePreviewEditor> createState() => _LivePreviewEditorState();
}

class _LivePreviewEditorState extends State<LivePreviewEditor> {
  static const double _horizontalPadding = 20;

  final TextEditingController _blockController = TextEditingController();
  late final FocusNode _blockFocus;

  /// 每个渲染块的 key，用于大纲跳转时定位滚动目标。
  final Map<int, GlobalKey> _blockKeys = <int, GlobalKey>{};

  /// 正在编辑的段的起始偏移；为空表示全部处于渲染态。
  int? _activeStart;
  String _lastCommittedText = '';

  /// 就地编辑框内部的拖选是否还在进行（按下到抬起之间）。
  ///
  /// 桌面端用鼠标「按住左键向上跨行拖动」时，[TextField] 自己的拖选手势只会
  /// 在当前段的源码里选（输入框里只有这一段），指针移出输入框后选区就不再
  /// 增长 —— 表现为「只能选中点击的那一行」。这里在拖选期间跟踪指针，越过
  /// 上/下边界就把相邻段落并进编辑范围，再按整篇源码设置选区。
  bool _draggingSelection = false;

  /// 拖选是否已经「接管」：指针第一次越出输入框后由本组件负责更新选区。
  ///
  /// 框内的普通拖选仍然交给 [TextField] 自己（保留双击选词、连点选段等行为）。
  bool _dragOwnsSelection = false;

  /// 拖选锚点在**整篇源码**里的绝对偏移；用绝对偏移是因为拖过段落边界后
  /// 就地输入框会被扩成「多段源码」，框内相对偏移会整体平移。
  int? _dragAnchor;

  /// 最近一次拖选指针的全局坐标，用于布局完成后再精修一次选区。
  Offset? _lastDragPosition;

  bool _refineScheduled = false;

  GlobalKey _keyForBlock(int start) =>
      _blockKeys.putIfAbsent(start, () => GlobalKey(debugLabel: 'block-$start'));

  @override
  void initState() {
    super.initState();
    // 段首退格要越过段落边界（输入框里只有当前段，默认行为删不动上一段），
    // 在焦点节点上先拦截 Backspace，其余按键原样交还给输入框。
    _blockFocus = FocusNode(onKeyEvent: _handleBlockKeyEvent);
    _blockController.addListener(_commitBlockEdit);
    _blockFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant LivePreviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final request = widget.jump;
    if (request == null || request == oldWidget.jump) return;
    // 这里不能写回正在编辑的段落：didUpdateWidget 处于 build 阶段，控制器写入会
    // 触发上层的标题/脏标记监听（可能改 provider）。逐字符监听已经把段落实时写回，
    // 因此直接滚动即可。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final blocks = splitMarkdownBlocks(widget.controller.text);
      if (blocks.isEmpty) return;
      final target = blocks
          .where((block) => block.start <= request.offset)
          .lastOrNull ??
          blocks.first;
      final context = _keyForBlock(target.start).currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.02,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _blockController
      ..removeListener(_commitBlockEdit)
      ..dispose();
    _blockFocus
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // 拖选期间合并段落会换掉就地输入框的 Key（起点变了），旧输入框销毁时
    // 焦点会短暂丢失；这不是「点按别处收起」，不能据此收起编辑态。
    if (_draggingSelection || _dragOwnsSelection) return;
    if (!_blockFocus.hasFocus && _activeStart != null) {
      _deactivate(scrollToTop: false);
    }
  }

  /// 外部（或本组件内置复选框）改动了整篇正文：放弃当前段编辑，重新解析。
  void _deactivate({bool scrollToTop = true}) {
    if (_activeStart == null) return;
    _resetDragState();
    setState(() {
      _activeStart = null;
      _lastCommittedText = '';
    });
    if (scrollToTop) _blockFocus.unfocus();
  }

  void _activate(int index, MarkdownBlock tapped) {
    if (_activeStart == tapped.start) return;
    // 先收起上一段（写入整篇正文），再解析最新分块定位要展开的段落：
    // 上一段编辑过之后，它后面各块的偏移量都会变化，不能直接沿用点击时的偏移。
    _commitBlockEdit();
    final blocks = splitMarkdownBlocks(widget.controller.text);
    if (blocks.isEmpty) return;
    final block = _locateBlock(blocks, index, tapped);
    setState(() {
      _activeStart = block.start;
      _lastCommittedText = block.text;
    });
    widget.onBlockActivated?.call(block);
    _blockController.value = TextEditingValue(
      text: block.text,
      selection: TextSelection.collapsed(offset: block.text.length),
    );
    _blockFocus.requestFocus();
    _revealBlock(block.start);
  }

  /// 把某个块滚进视野（展开的源码输入框也用它，保证合并后光标可见）。
  void _revealBlock(int start) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _keyForBlock(start).currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// 段首退格：越过段落边界，把上一段接进来。
  ///
  /// 实时预览的输入框里只有当前段的源码，光标在段首时退格默认什么也删不掉
  /// （表现为「删不动上一行的行尾」）。这里按普通文本编辑器的语义处理：
  /// 删掉段前的分隔换行，让上一段整段展开成源码、光标落在上一行的行尾。
  KeyEventResult _handleBlockKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final selection = _blockController.selection;
    if (!selection.isValid || !selection.isCollapsed || selection.baseOffset != 0) {
      return KeyEventResult.ignored;
    }
    return _joinPreviousBlock()
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// 把当前段并入上一段；没有上一段（已在正文开头）时返回 false。
  bool _joinPreviousBlock() {
    _commitBlockEdit();
    final start = _activeStart;
    if (start == null || start <= 0) return false;
    final document = widget.controller.text;
    if (start > document.length) return false;

    final blocks = splitMarkdownBlocks(document);
    MarkdownBlock? previous;
    for (final block in blocks) {
      if (block.end <= start) previous = block;
    }
    if (previous == null) return false;

    // 只删掉一个分隔换行：段间有多个空行时，继续按退格会逐行删掉，与普通
    // 编辑器的退格语义一致；标题行会被强制成块的场合，光标直接落到上一段末尾，
    // 上一段的源码随之展开。
    final newDocument = document.replaceRange(previous.end, start, '\n');
    final cursor = previous.end;
    final nextBlocks = newDocument == document
        ? blocks
        : splitMarkdownBlocks(newDocument);
    MarkdownBlock? target;
    for (final block in nextBlocks) {
      if (block.start > cursor) break;
      if (cursor <= block.end) {
        target = block;
        if (cursor < block.end) break;
      }
    }
    final MarkdownBlock? joined = target;
    if (joined == null) return false;

    // 先同步活动段与期望文本，再写输入框：写输入框会触发 [_commitBlockEdit]，
    // 此时两者一致，监听器直接返回，不会把刚合并的正文覆盖掉。
    setState(() {
      _activeStart = joined.start;
      _lastCommittedText = joined.text;
    });
    if (newDocument != document) {
      widget.controller.value = TextEditingValue(
        text: newDocument,
        selection: TextSelection.collapsed(offset: cursor),
      );
    }
    _blockController.value = TextEditingValue(
      text: joined.text,
      selection: TextSelection.collapsed(offset: cursor - joined.start),
    );
    widget.onBlockActivated?.call(joined);
    _blockFocus.requestFocus();
    _revealBlock(joined.start);
    return true;
  }

  // ---------------------------------------------------------------------------
  // 跨段落拖选（桌面端鼠标/触控板）
  // ---------------------------------------------------------------------------

  /// 按下：进入「可能正在拖选」状态，并记下锚点在**整篇源码**里的绝对偏移。
  ///
  /// 用绝对偏移而不是输入框内的相对偏移：拖过段落边界时输入框会被扩成
  /// 「多段源码」，框内相对偏移会整体平移，绝对偏移始终对应整篇正文。
  void _handleInlinePointerDown(PointerDownEvent event) {
    final start = _activeStart;
    final editable = _renderEditable;
    if (start == null || editable == null) {
      _draggingSelection = false;
      return;
    }
    _draggingSelection = true;
    _dragOwnsSelection = false;
    _lastDragPosition = event.position;
    // 框架的拖选把「按下点」当作 base，这里用同一套换算得到锚点；
    // 双击选词等会改写 base 的场景在接管时再按实际选区校正一次。
    final press = editable.getPositionForPoint(event.position);
    _dragAnchor = start + press.offset;
  }

  /// 输入框内的指针移动：越出输入框上下边界就把相邻段落并入编辑范围。
  ///
  /// [TextField] 自己的拖选只认自己的文本（就地展开时只有当前这一段），
  /// 指针一出框选区就不再增长 —— 这正是「向上跨行只能选中点击的那一行」。
  /// 越过边界后由本组件按「整篇正文」重算选区。
  void _handleInlinePointerMove(PointerMoveEvent event) {
    if (!_draggingSelection) return;
    _lastDragPosition = event.position;
    if (_dragAnchor == null) return;
    final box = _blockFocus.context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.inflate(2).contains(event.position)) {
      if (!_dragOwnsSelection) {
        // 接管：以当前实际选区的 base 为准（双击选词后 base 可能不在按下点）。
        final selection = _blockController.selection;
        final start = _activeStart;
        if (start != null && selection.isValid) {
          _dragAnchor = start + selection.baseOffset;
        }
        _dragOwnsSelection = true;
      }
      _expandEditingRangeTo(event.position);
    }
    if (_dragOwnsSelection) _scheduleSelectionRefine();
  }

  /// 松开：把选区交还给 [TextField] 自己管理。
  void _handleInlinePointerUp() {
    if (!_dragOwnsSelection) {
      _resetDragState();
      return;
    }
    // 松手前按指针位置再定一次，保证落在光标处的选区与最后一次移动一致。
    _applySelectionFromPointer();
    _resetDragState();
  }

  void _resetDragState() {
    _draggingSelection = false;
    _dragOwnsSelection = false;
    _dragAnchor = null;
    _lastDragPosition = null;
  }

  /// 按指针位置扩大就地输入框的编辑范围（向上并入前面的块、向下并入后面的块）。
  ///
  /// 输入框里因此变成「多段源码」，与用户预期的「选中的 Markdown 源码」一致；
  /// 松手后沿用同一套 [_commitBlockEdit] 写回整篇正文，失焦时再收起。
  ///
  /// 扩展是**单调**的：合并范围只增不减，指针继续往同一个方向拖就继续并入相邻块，
  /// 不会因为「当前编辑范围已经跨了几块」而把先前并入的块又丢出去。
  void _expandEditingRangeTo(Offset globalPosition) {
    final start = _activeStart;
    if (start == null) return;
    final document = widget.controller.text;
    final blocks = splitMarkdownBlocks(document);
    if (blocks.isEmpty) return;
    final rangeStart = start;
    final rangeEnd = start + _lastCommittedText.length;
    // 当前编辑范围覆盖的块区间：范围两端一定落在块边界上（并块时按块边界取）。
    final firstIndex = blocks.indexWhere((block) => block.start == rangeStart);
    final lastIndex = blocks.indexWhere((block) => block.end == rangeEnd);
    if (firstIndex < 0 || lastIndex < firstIndex) return;

    // 指针落在哪一块：优先用渲染态块的矩形判断；落不进任何块（例如指针已经在
    // 正文上方/下方很远）时按上下方向取与当前范围相邻的那一块。
    var targetIndex = -1;
    for (var i = 0; i < blocks.length; i++) {
      if (i >= firstIndex && i <= lastIndex) continue;
      final box = _keyForBlock(blocks[i].start).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPosition)) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      if (globalPosition.dy < _fieldRect().top) {
        for (var i = firstIndex - 1; i >= 0; i--) {
          if (blocks[i].end <= rangeStart) {
            targetIndex = i;
            break;
          }
        }
      } else {
        for (var i = lastIndex + 1; i < blocks.length; i++) {
          if (blocks[i].start >= rangeEnd) {
            targetIndex = i;
            break;
          }
        }
      }
    }
    if (targetIndex < 0) return;
    final first = firstIndex < targetIndex ? firstIndex : targetIndex;
    final last = lastIndex > targetIndex ? lastIndex : targetIndex;
    final mergedStart = blocks[first].start;
    final merged = document.substring(mergedStart, blocks[last].end);
    if (mergedStart == rangeStart && merged == _lastCommittedText) return;
    // 先同步活动段与期望文本，再写输入框：写输入框会触发 [_commitBlockEdit]，
    // 此时两者一致，监听器直接返回，不会把刚合并的正文覆盖掉。
    _activeStart = mergedStart;
    _lastCommittedText = merged;
    final anchor = _dragAnchor;
    _blockController.value = TextEditingValue(
      text: merged,
      selection: TextSelection(
        baseOffset: (anchor == null ? 0 : anchor - mergedStart).clamp(0, merged.length),
        extentOffset: _pointerOffsetIn(merged),
      ),
    );
    if (mounted) setState(() {});
    // 合并后编辑框的 Key 换成了新的起点：重建后的输入框要把焦点接回来，
    // 否则下一次移动/按键就落到别处，编辑态会随失焦被收起。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_draggingSelection) return;
      if (!_blockFocus.hasFocus) _blockFocus.requestFocus();
    });
  }

  /// 就地输入框的全局矩形（取不到时给一个空矩形，按「指针在框下方」处理）。
  Rect _fieldRect() {
    final box = _blockFocus.context?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset.zero) & box.size;
    }
    return Rect.zero;
  }

  /// 指针在就地输入框文本里的落点；指针在框外时由框架夹到首/尾。
  int _pointerOffsetIn(String text) {
    final position = _lastDragPosition;
    final editable = _renderEditable;
    if (position == null || editable == null) return text.length;
    return editable.getPositionForPoint(position).offset.clamp(0, text.length);
  }

  /// 下一帧按指针位置重算选区。
  ///
  /// 合并段落会改变输入框高度与折行，同一帧内算出来的偏移已经不准；
  /// 而且要排在框架自己的拖选更新之后，否则会被它覆盖掉。
  void _scheduleSelectionRefine() {
    if (_refineScheduled) return;
    _refineScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refineScheduled = false;
      if (!mounted || !_dragOwnsSelection) return;
      _applySelectionFromPointer();
    });
  }

  void _applySelectionFromPointer() {
    final start = _activeStart;
    if (start == null) return;
    final text = _blockController.text;
    final anchor = _dragAnchor;
    final selection = TextSelection(
      baseOffset: (anchor == null ? 0 : anchor - start).clamp(0, text.length),
      extentOffset: _pointerOffsetIn(text),
    );
    if (selection == _blockController.selection) return;
    _blockController.value = TextEditingValue(text: text, selection: selection);
  }

  RenderEditable? get _renderEditable => _blockFocus.context
      ?.findAncestorStateOfType<EditableTextState>()
      ?.renderEditable;

  /// 在最新分块里找回被点击的段落。
  ///
  /// 依次尝试：起始偏移 + 文本都没变 → 文本唯一匹配（前面段落长度变化只会让
  /// 偏移整体平移）→ 同一序号 → 最近的一块。渲染态的块文本不会因为别处输入而
  /// 改变，所以正常路径总能精确命中。
  MarkdownBlock _locateBlock(
    List<MarkdownBlock> blocks,
    int index,
    MarkdownBlock tapped,
  ) {
    for (final block in blocks) {
      if (block.start == tapped.start && block.text == tapped.text) {
        return block;
      }
    }
    final sameText = blocks.where((block) => block.text == tapped.text).toList();
    if (sameText.length == 1) return sameText.first;
    if (index >= 0 && index < blocks.length) return blocks[index];
    return blocks.last;
  }

  /// 勾选任务复选框：先提交当前段落，再同步展开中的段落到勾选后的源码，
  /// 避免下一次按键用旧文本把勾选结果覆盖掉。
  void _toggleTask(int index) {
    _commitBlockEdit();
    final activeStart = _activeStart;
    final previousText = _blockController.text;
    widget.onToggleTask?.call(index);
    if (activeStart == null) return;
    final match =
        splitMarkdownBlocks(
          widget.controller.text,
        ).where((block) => block.start == activeStart).firstOrNull;
    if (match == null) {
      _deactivate(scrollToTop: false);
      return;
    }
    if (match.text == previousText) return;
    final selection = _blockController.selection;
    _lastCommittedText = match.text;
    _blockController.value = TextEditingValue(
      text: match.text,
      selection:
          selection.isValid && selection.end <= match.text.length
              ? selection
              : TextSelection.collapsed(offset: match.text.length),
    );
  }

  /// 把当前段落的源码写回整篇正文。
  void _commitBlockEdit() {
    final start = _activeStart;
    if (start == null) return;
    final document = widget.controller.text;
    final expectedEnd = start + _lastCommittedText.length;
    // 整篇正文被外部改动（例如勾选别处的复选框）导致偏移失效时，
    // 放弃本次段落编辑，避免覆盖别人的修改。
    if (expectedEnd > document.length ||
        document.substring(start, expectedEnd) != _lastCommittedText) {
      _deactivate(scrollToTop: false);
      return;
    }
    final text = _blockController.text;
    if (text == _lastCommittedText) return;
    final newDocument = document.replaceRange(start, expectedEnd, text);
    _lastCommittedText = text;
    widget.controller.value = TextEditingValue(
      text: newDocument,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = splitMarkdownBlocks(widget.controller.text);
    final active = _activeStart;
    // 就地编辑框覆盖的源码区间：通常就是「一个块」，但桌面端跨段拖选会把相邻
    // 块并进同一个输入框，此时区间覆盖多个块，这些块不能再各自渲染一遍
    // （否则源码和渲染副本会同时出现在正文里）。
    final editEnd = active == null ? null : active + _lastCommittedText.length;
    final liveBlocks = active == null
        ? const <MarkdownBlock>[]
        : blocks
              .where(
                (block) =>
                    block.start < editEnd! && block.end > active,
              )
              .toList();
    final liveBlock = liveBlocks.isEmpty ? null : liveBlocks.first;
    // 正在编辑的段可能刚被删空：空块不会出现在分块结果里，但输入框必须留着，
    // 否则焦点随块一起消失、后续退格就再也删不动上一行（Android 上必现）。
    // 这类「空段」按纯插入位置渲染在相邻两块之间。
    final pendingOffset = active != null && liveBlocks.isEmpty ? active : null;

    // 正文被改写后偏移量会整体变化，清掉已经不存在的块的 Key，避免 Map 无限增长。
    final starts = {for (final block in blocks) block.start};
    if (pendingOffset != null) starts.add(pendingOffset);
    _blockKeys.removeWhere((start, _) => !starts.contains(start));

    // 编辑框里的源码（区间可能跨多个块，取整篇正文里对应的片段）。
    final liveText = liveBlock == null
        ? ''
        : widget.controller.text.substring(
            liveBlock.start,
            (editEnd ?? liveBlock.end).clamp(liveBlock.start, widget.controller.text.length),
          );
    final liveStarts = {for (final block in liveBlocks) block.start};

    final children = <Widget>[];
    var insertedPending = false;
    var insertedEditor = false;
    for (var index = 0; index < blocks.length; index++) {
      if (pendingOffset != null && !insertedPending && blocks[index].start > pendingOffset) {
        children.add(_buildInlineEditor(start: pendingOffset, text: ''));
        insertedPending = true;
      }
      // 被编辑区间覆盖的块只在区间起点渲染一次输入框，其余块整体跳过。
      if (liveStarts.contains(blocks[index].start)) {
        if (!insertedEditor) {
          children.add(
            _buildInlineEditor(start: liveBlock!.start, text: liveText),
          );
          insertedEditor = true;
        }
        continue;
      }
      children.add(_buildRenderedBlock(index, blocks[index]));
    }
    if (pendingOffset != null && !insertedPending) {
      children.add(_buildInlineEditor(start: pendingOffset, text: ''));
    }
    final editing = liveBlock != null || pendingOffset != null;

    if (children.isEmpty && !editing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            EditorStrings.emptyPreview,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            // 点按渲染态的空白处收起源码；具体段落由各自的手势优先处理。
            onTap: _blockFocus.unfocus,
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                _horizontalPadding,
                8,
                _horizontalPadding,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
        if (editing)
          // 工具条也算「输入框的一部分」：点按它不应收起源码编辑。
          TextFieldTapRegion(
            child: MarkdownToolbar(
              controller: _blockController,
              focusNode: _blockFocus,
            ),
          ),
      ],
    );
  }

  Widget _buildRenderedBlock(int index, MarkdownBlock block) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: _keyForBlock(block.start),
      onTap: () => _activate(index, block),
      borderRadius: BorderRadius.circular(8),
      hoverColor: scheme.primary.withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: MarkdownView(
          content: block.text,
          taskStartIndex: block.taskOffset,
          onTapText: () => _activate(index, block),
          onToggleTask: _toggleTask,
        ),
      ),
    );
  }

  /// 就地展开的源码输入框。
  ///
  /// 与渲染块共用同一位置、没有边框/底色/标题栏，也没有「完成」按钮：
  /// 界面只会看到这一段的 Markdown 源码，失焦（点按别处）即自动收起。
  /// 标题块要按渲染态同样的数值补上上边距，否则点按标题时正文会上下跳动。
  ///
  /// 外面套一层 [Listener] 监听指针移动：桌面端按住左键向上/向下拖出输入框时，
  /// [TextField] 只管自己那段文本，指针出框后选区不再增长（表现为「只能选中
  /// 点击的那一行」）。越过边界后由 [_handleInlinePointerMove] 把相邻段落并入
  /// 编辑范围，选区随之覆盖整段源码。
  Widget _buildInlineEditor({required int start, required String text}) {
    final headingLevel = markdownLeadingHeadingLevel(text);
    final topSpacing = headingLevel == null
        ? 0.0
        : markdownHeadingTopSpacing(headingLevel);
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: Listener(
        // 触摸端由长按 + 拖拽手柄选词，越界扩展没有意义，因此只接管鼠标/触控板；
        // 指针事件不参与手势竞技场，加在 Listener 上不会抢走 TextField 的拖选。
        onPointerMove: (event) {
          switch (event.kind) {
            case PointerDeviceKind.mouse:
            case PointerDeviceKind.trackpad:
            case PointerDeviceKind.stylus:
            case PointerDeviceKind.invertedStylus:
              _handleInlinePointerMove(event);
            case PointerDeviceKind.touch:
            case PointerDeviceKind.unknown:
              break;
          }
        },
        onPointerDown: (event) => _handleInlinePointerDown(event),
        onPointerUp: (_) => _handleInlinePointerUp(),
        onPointerCancel: (_) => _handleInlinePointerUp(),
        child: TextField(
          key: _keyForBlock(start),
          controller: _blockController,
          focusNode: _blockFocus,
          maxLines: null,
          minLines: 1,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          // 默认实现只在桌面端「点按外部」时失焦，移动端触摸不会。这里统一收起，
          // 保证任何平台上点别处都能自然退出源码态；工具条包在
          // [TextFieldTapRegion] 里，点它不算「外部」。
          onTapOutside: (_) => _blockFocus.unfocus(),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14.5,
            height: 1.6,
          ),
          decoration: const InputDecoration(
            hintText: EditorStrings.contentHint,
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
          ),
        ),
      ),
    );
  }
}

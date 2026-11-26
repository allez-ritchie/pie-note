import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 分隔条改变的是它**左侧**还是**右侧**面板的宽度。
enum ResizeEdge {
  /// 拖拽改变左边面板的宽度（例如「笔记本 | 笔记」双栏）。
  left,

  /// 拖拽改变右边面板的宽度（例如编辑器右侧的大纲侧栏）。
  right,
}

/// 可拖拽调宽的分隔条（桌面端）。
///
/// 视觉上就是一条 1px 分隔线，但命中区域有 [hitWidth]，鼠标悬停时变成
/// `resizeColumn` 光标并高亮，按住左右拖动即可调宽；双击恢复默认宽度、
/// 聚焦后按 ← / → 按 [keyStep] 微调（键盘可达性）。
///
/// 宽度是**受控**的：本组件不存宽度，只把新宽度通过 [onWidthChanged] 抛给父级，
/// 由父级决定怎么渲染与持久化（拖动过程中父级只改内存状态，松手时才写偏好，
/// 避免每帧一次落盘）。
class ResizableDivider extends StatefulWidget {
  const ResizableDivider({
    super.key,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.onWidthChanged,
    this.onWidthChangeEnd,
    this.onReset,
    this.dragEdge = ResizeEdge.left,
    this.tooltip,
    this.semanticLabel,
    this.keyStep = 16,
    this.hitWidth = 9,
  });

  /// 当前宽度（由父级持有）。
  final double width;

  /// 允许的最小 / 最大宽度；超出范围时自动夹取。
  final double minWidth;
  final double maxWidth;

  /// 拖动 / 键盘调整时的新宽度（已夹取到 [minWidth] ~ [maxWidth]）。
  final ValueChanged<double> onWidthChanged;

  /// 一次拖拽结束（松手）时调用：父级在这里落盘，拖动过程中只更新内存。
  final VoidCallback? onWidthChangeEnd;

  /// 双击恢复默认宽度；为 null 时双击无效果。
  final VoidCallback? onReset;

  /// 分隔条改变哪一侧面板的宽度，决定拖动与方向键的方向。
  final ResizeEdge dragEdge;

  /// 悬停提示（同时作为无障碍标签的兜底）。
  final String? tooltip;

  final String? semanticLabel;

  /// 键盘 ← / → 每次调整的像素数。
  final double keyStep;

  /// 命中区域宽度（视觉上的分隔线仍只有 1px）。
  final double hitWidth;

  @override
  State<ResizableDivider> createState() => _ResizableDividerState();
}

class _ResizableDividerState extends State<ResizableDivider> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'resizable-divider');

  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;

  /// 拖拽起点的宽度与累计位移：用「起点 + 累计」而不是「当前宽度 + 增量」，
  /// 这样父级重建有延迟时也不会丢位移、不会越拖越慢。
  double _dragStartWidth = 0;
  double _dragDelta = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  double _clamp(double width) => width.clamp(widget.minWidth, widget.maxWidth);

  void _emit(double width) => widget.onWidthChanged(_clamp(width));

  void _handleDragStart(DragStartDetails details) {
    _dragStartWidth = widget.width;
    _dragDelta = 0;
    setState(() => _dragging = true);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragDelta += details.delta.dx;
    _emit(_dragStartWidth + _signedDelta(_dragDelta));
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() => _dragging = false);
    widget.onWidthChangeEnd?.call();
  }

  void _handleDragCancel() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onWidthChangeEnd?.call();
  }

  /// 分隔条往右拖时：左侧面板变宽、右侧面板变窄。
  double _signedDelta(double pointerDelta) =>
      widget.dragEdge == ResizeEdge.left ? pointerDelta : -pointerDelta;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final double pointerStep;
    if (key == LogicalKeyboardKey.arrowRight) {
      pointerStep = widget.keyStep;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      pointerStep = -widget.keyStep;
    } else {
      return KeyEventResult.ignored;
    }
    _emit(widget.width + _signedDelta(pointerStep));
    widget.onWidthChangeEnd?.call();
    return KeyEventResult.handled;
  }

  void _handleReset() {
    final reset = widget.onReset;
    if (reset == null) return;
    reset();
    widget.onWidthChangeEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _dragging || _hovering || _focused;
    final label = widget.semanticLabel ?? widget.tooltip;
    final line = Semantics(
      label: label,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKey,
        onFocusChange: (value) => setState(() => _focused = value),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 从按下点开始算位移：默认的 DragStartBehavior.start 会把识别手势的
            // 那段滑动（约 18px 触摸阈值）吃掉，分隔条就会比指针慢半拍，
            // 桌面端鼠标拖动尤其明显。
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (_) => _focusNode.requestFocus(),
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: _handleDragCancel,
            onDoubleTap: widget.onReset == null ? null : _handleReset,
            child: SizedBox(
              width: widget.hitWidth,
              height: double.infinity,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: active ? 2 : 1,
                  color: active ? scheme.primary : scheme.outlineVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip == null) return line;
    return Tooltip(
      message: widget.tooltip!,
      waitDuration: const Duration(milliseconds: 600),
      child: line,
    );
  }
}

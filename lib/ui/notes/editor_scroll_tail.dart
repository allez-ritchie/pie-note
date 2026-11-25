import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 末尾留白的最小高度：视口很矮（比如手机横屏）时也不至于完全没有余量。
const double kEditorTailBlankMin = 32;

/// 笔记正文滚动区末尾的留白高度。
///
/// 参考 Obsidian：正文最后留出约**半个视口**的空白，最后一行才能继续上滚到
/// 屏幕中间，而不是永远贴在页面最底部。这样读者视线不用一直停在屏幕下缘，
/// 底部的 Markdown 工具条 / 悬浮胶囊也不会压住最后一行。
///
/// [viewportExtent] 是正文滚动区自身的高度（不含标题栏与工具条）；
/// 拿不到有限值时退回 0，避免在无界约束里加出无穷大。
double editorTailBlank(double viewportExtent) {
  if (!viewportExtent.isFinite || viewportExtent <= 0) return 0;
  return viewportExtent / 2;
}

/// 正文滚动区实际使用的底部内边距。
///
/// 取「常规内边距 [base]」与「半个视口减去 [innerBottom]」中的较大值，而不是
/// 两者相加：内边距就是「最后一行下方还能滚出多少」；输入框自己已有
/// [innerBottom] 的内边距时，外层只需补足剩下的一半视口，滚到底最后一行
/// 才会正好停在视口垂直中线上。
double editorBottomInset(
  double viewportExtent,
  double base, {
  double innerBottom = 0,
}) {
  final target = editorTailBlank(viewportExtent) - innerBottom;
  return math.max(target, base);
}

/// 正文滚动区的尺寸信息，供 [EditorScrollTail] 的 builder 使用。
class EditorScrollMetrics {
  const EditorScrollMetrics({required this.viewportExtent, required this.bottomInset});

  /// 滚动区自身的高度（取不到有限值时为 0）。
  final double viewportExtent;

  /// 已经在常规内边距之外补上末尾留白的底部内边距。
  final double bottomInset;

  /// 内容至少要铺满的高度，再加上末尾留白。
  ///
  /// 给「滚动区里放一个自适应高度的输入框」用：输入框本身铺满视口 + 留白，
  /// 滚动交给外层 ScrollView，输入框内部就不会只剩半个视口高。
  double get contentMinHeight => viewportExtent + bottomInset;
}

/// 按滚动区的实际高度计算末尾留白，并把结果交给 [builder]。
///
/// 三个视图（实时预览 / 源码 / 阅读）的滚动区高度各不相同，用各自的
/// [LayoutBuilder] 取视口高度最准确；不要用 `MediaQuery.sizeOf` 整个窗口高度，
/// 否则标题栏、状态行、底部工具条占掉的空间也会被算进留白。
class EditorScrollTail extends StatelessWidget {
  const EditorScrollTail({
    super.key,
    required this.base,
    this.innerBottom = 0,
    required this.builder,
  });

  /// 该滚动区原本的底部内边距（没有留白需求时的值）。
  final double base;

  /// 滚动区内容自己已经带的底部内边距（例如源码模式输入框的 contentPadding）。
  final double innerBottom;

  final Widget Function(BuildContext context, EditorScrollMetrics metrics) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        return builder(
          context,
          EditorScrollMetrics(
            viewportExtent: viewport.isFinite && viewport > 0 ? viewport : 0,
            bottomInset: editorBottomInset(
              viewport,
              math.max(base, kEditorTailBlankMin),
              innerBottom: innerBottom,
            ),
          ),
        );
      },
    );
  }
}

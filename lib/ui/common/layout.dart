import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 响应式断点（依据 Material 3 窗口尺寸类，略作简化）。
///
/// 页面不直接读 `MediaQuery.orientation`，而是按**可用宽高**决策：
/// 手机横屏与桌面窄窗口只是尺寸不同，按尺寸分支能同时适配横竖屏与桌面端。
class Breakpoints {
  const Breakpoints._();

  /// 导航从底部切换为侧边栏（NavigationRail）的宽度。
  static const double sideNavigation = 720;

  /// 「笔记本 + 笔记」双栏布局的宽度。
  static const double twoPane = 840;

  /// 双栏布局要求的最小高度：手机横屏（高度约 400）放双栏会太挤。
  static const double twoPaneMinHeight = 480;

  /// 编辑器「渲染态 + 预览」分栏的宽度。
  static const double editorSplit = 900;

  /// 编辑分栏要求的最小高度：横屏手机高度不足时用单栏。
  static const double editorSplitMinHeight = 420;

  /// 笔记大纲常驻侧栏的宽度：再窄就让大纲改用底部弹出面板，
  /// 否则侧栏会明显挤压正文。
  static const double outlineSidebar = 1080;
}

/// 当前窗口的响应式判定。
class Responsive {
  const Responsive._();

  static Size sizeOf(BuildContext context) => MediaQuery.sizeOf(context);

  static double width(BuildContext context) => sizeOf(context).width;

  static double height(BuildContext context) => sizeOf(context).height;

  /// 是否使用侧边导航（宽屏）。
  static bool useSideNavigation(BuildContext context) {
    final size = sizeOf(context);
    return size.width >= Breakpoints.sideNavigation;
  }

  /// 是否使用「笔记本 + 笔记」双栏（宽且够高）。
  static bool useTwoPane(BuildContext context) {
    final size = sizeOf(context);
    return size.width >= Breakpoints.twoPane &&
        size.height >= Breakpoints.twoPaneMinHeight;
  }

  /// 编辑器是否左右分栏（实时预览 + 预览 / 阅读 + 源码）。
  static bool useEditorSplit(BuildContext context) {
    final size = sizeOf(context);
    return size.width >= Breakpoints.editorSplit &&
        size.height >= Breakpoints.editorSplitMinHeight;
  }

  /// 笔记大纲是否作为右侧常驻侧栏（否则用底部弹出面板）。
  static bool useOutlineSidebar(BuildContext context) {
    final size = sizeOf(context);
    return size.width >= Breakpoints.outlineSidebar &&
        size.height >= Breakpoints.editorSplitMinHeight;
  }
}

/// 给页面内容加最大宽度限制并水平居中。
///
/// 手机上等同于原样铺满；桌面端把内容收在 [maxWidth] 内，避免超宽屏上
/// 一行文字过长、按钮被拉伸。
class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = 900,
    this.centered = true,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxWidth;
  final bool centered;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final available = math.min(Responsive.width(context), maxWidth);
    return Align(
      alignment: centered ? Alignment.topCenter : Alignment.topLeft,
      child: SizedBox(
        width: available,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

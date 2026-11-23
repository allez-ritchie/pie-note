import 'package:flutter/material.dart';

import 'workspace_strings.dart';

/// 悬浮胶囊工具栏的显隐控制器。
///
/// 交互参考 Obsidian 移动端：
/// - 上划（手指上移、正文向下滚动）时自动隐藏，给内容让出空间；
/// - **上划中途点按屏幕停下**不会重新显示：滚动停止事件被忽略，
///   只有反向滚动才会重新显示；
/// - 下划（回看上面的内容）时重新显示；
/// - 新建标签页、打开标签总览等显式操作可以主动 [show]。
class FloatingBarController extends ChangeNotifier {
  bool _visible = true;
  bool _disposed = false;

  bool get visible => _visible;

  void show() {
    if (_visible || _disposed) return;
    _visible = true;
    notifyListeners();
  }

  void hide() {
    if (!_visible || _disposed) return;
    _visible = false;
    notifyListeners();
  }

  void toggle() => _visible ? hide() : show();

  /// 按滚动方向切换显隐。
  ///
  /// [ScrollUpdateNotification.scrollDelta] 为正表示内容朝末尾推进（上划），
  /// 为负表示回滚（下划）。滚动结束 / 越界回弹不改变显隐 —— 这样在惯性
  /// 滚动中点按屏幕停下，工具栏仍保持隐藏，符合 Obsidian 的手感。
  void handleScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return;
    final delta = notification.scrollDelta ?? 0;
    if (delta > 0) {
      hide();
    } else if (delta < 0) {
      show();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 移动端底部悬浮胶囊工具栏。
///
/// 与桌面标签条不同，手机上不放标签条（横向空间不够），而是一个胶囊：
/// 后退 / 前进、搜索、新建笔记、标签总览（带数量徽标）、更多菜单。
class MobileFloatingBar extends StatelessWidget {
  const MobileFloatingBar({
    super.key,
    required this.controller,
    required this.tabCount,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onSearch,
    required this.onNewNote,
    required this.onTabs,
    required this.onMenu,
  });

  final FloatingBarController controller;
  final int tabCount;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onSearch;
  final VoidCallback onNewNote;
  final VoidCallback onTabs;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          return AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            offset: controller.visible ? Offset.zero : const Offset(0, 1.35),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: controller.visible ? 1 : 0,
              // 隐藏时不能挡住页面的点按。
              child: IgnorePointer(ignoring: !controller.visible, child: child),
            ),
          );
        },
        child: Center(
          child: Material(
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 56,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BarIcon(
                    icon: Icons.chevron_left_rounded,
                    tooltip: '后退',
                    onPressed: canGoBack ? onBack : null,
                  ),
                  _BarIcon(
                    icon: Icons.chevron_right_rounded,
                    tooltip: '前进',
                    onPressed: canGoForward ? onForward : null,
                  ),
                  _BarIcon(
                    icon: Icons.search_rounded,
                    tooltip: '搜索',
                    onPressed: onSearch,
                  ),
                  _BarIcon(
                    icon: Icons.add_rounded,
                    tooltip: WorkspaceStrings.newTabTooltip,
                    onPressed: onNewNote,
                  ),
                  _BarIcon(
                    icon: Icons.tab_rounded,
                    tooltip: WorkspaceStrings.tabListTooltip,
                    onPressed: onTabs,
                    badge: tabCount,
                  ),
                  _BarIcon(
                    icon: Icons.menu_rounded,
                    tooltip: WorkspaceStrings.more,
                    onPressed: onMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 非空时在图标右下角显示数量（标签页数量）。
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final iconWidget = Icon(
      icon,
      size: 22,
      color:
          enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.32),
    );
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 22,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon:
          badge == null
              ? iconWidget
              : Badge(
                isLabelVisible: badge! > 0,
                label: Text('${badge!}'),
                backgroundColor: scheme.primary,
                textColor: scheme.onPrimary,
                child: iconWidget,
              ),
    );
  }
}

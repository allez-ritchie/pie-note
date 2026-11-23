import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../state/workspace.dart';
import 'workspace_strings.dart';

/// 桌面端标签条（参考 Obsidian 桌面端 / VSCode）。
///
/// - 单行横向滚动，超出宽度时可拖动 / 滚轮横向滚动，激活标签自动滚入视野；
/// - 点击切换、`×` 或鼠标中键关闭、右键菜单批量关闭；
/// - 右侧固定「新建笔记」按钮与标签数量。
class DesktopTabStrip extends StatefulWidget {
  const DesktopTabStrip({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onActivate,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseToRight,
    required this.onCloseAll,
    required this.onNewNote,
  });

  final List<WorkspaceTab> tabs;
  final String? activeId;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onCloseOthers;
  final ValueChanged<String> onCloseToRight;
  final VoidCallback onCloseAll;
  final VoidCallback onNewNote;

  @override
  State<DesktopTabStrip> createState() => _DesktopTabStripState();
}

class _DesktopTabStripState extends State<DesktopTabStrip> {
  static const double _stripHeight = 40;
  static const double _tabMaxWidth = 220;
  static const double _tabMinWidth = 120;

  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant DesktopTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeId != oldWidget.activeId && widget.activeId != null) {
      _revealActive();
    }
  }

  /// 激活标签变化后把它滚进视野（标签很多时仍然可见）。
  void _revealActive() {
    final index = widget.tabs.indexWhere((tab) => tab.id == widget.activeId);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final viewport = position.viewportDimension;
      // 标签宽度是弹性的，用等分宽度估算即可（只用于滚动定位）。
      final estimated = viewport / widget.tabs.length;
      final width = estimated.clamp(_tabMinWidth, _tabMaxWidth);
      final start = index * width;
      final end = start + width;
      final current = position.pixels;
      if (start < current) {
        _scrollController.jumpTo(start);
      } else if (end > current + viewport) {
        _scrollController.jumpTo(
          (end - viewport).clamp(0.0, position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: _stripHeight,
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: ScrollConfiguration(
              // 桌面端允许鼠标拖动横向滚动标签条。
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: widget.tabs.length,
                itemBuilder: (context, index) {
                  final tab = widget.tabs[index];
                  return _TabChip(
                    key: ValueKey('tab-chip-${tab.id}'),
                    tab: tab,
                    active: tab.id == widget.activeId,
                    maxWidth: _tabMaxWidth,
                    minWidth: _tabMinWidth,
                    onTap: () => widget.onActivate(tab.id),
                    onClose: () => widget.onClose(tab.id),
                    onCloseOthers: () => widget.onCloseOthers(tab.id),
                    onCloseToRight: () => widget.onCloseToRight(tab.id),
                    onCloseAll: widget.onCloseAll,
                    canCloseOthers: widget.tabs.length > 1,
                    canCloseToRight: index < widget.tabs.length - 1,
                  );
                },
              ),
            ),
          ),
          Container(width: 1, height: 20, color: scheme.outlineVariant),
          IconButton(
            tooltip: WorkspaceStrings.newTabTooltip,
            onPressed: widget.onNewNote,
            icon: const Icon(Icons.add_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              WorkspaceStrings.tabCount(widget.tabs.length),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatefulWidget {
  const _TabChip({
    super.key,
    required this.tab,
    required this.active,
    required this.maxWidth,
    required this.minWidth,
    required this.onTap,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseToRight,
    required this.onCloseAll,
    required this.canCloseOthers,
    required this.canCloseToRight,
  });

  final WorkspaceTab tab;
  final bool active;
  final double maxWidth;
  final double minWidth;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onCloseOthers;
  final VoidCallback onCloseToRight;
  final VoidCallback onCloseAll;
  final bool canCloseOthers;
  final bool canCloseToRight;

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = widget.active;
    final tab = widget.tab;
    final background =
        active
            ? scheme.surface
            : _hovered
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
            : Colors.transparent;
    final foreground = active ? scheme.onSurface : scheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // 鼠标中键关闭标签页（浏览器 / VSCode 习惯）。
        onTertiaryTapUp: (_) => widget.onClose(),
        child: InkWell(
          onTap: widget.onTap,
          onSecondaryTapDown:
              (details) => _showMenu(context, details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              maxWidth: widget.maxWidth,
            ),
            decoration: BoxDecoration(
              color: background,
              border: Border(
                top: BorderSide(
                  color: active ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(tab),
                  size: 15,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foreground,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (tab.dirty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // 未激活且未悬停时隐藏关闭按钮，避免标签条过于嘈杂。
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: active || _hovered ? 1 : 0,
                  child: _CloseButton(
                    tooltip: WorkspaceStrings.closeTab,
                    onPressed: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'close',
          child: Text(WorkspaceStrings.closeCurrent),
        ),
        PopupMenuItem(
          value: 'others',
          enabled: widget.canCloseOthers,
          child: const Text(WorkspaceStrings.closeOthers),
        ),
        PopupMenuItem(
          value: 'right',
          enabled: widget.canCloseToRight,
          child: const Text(WorkspaceStrings.closeToRight),
        ),
        const PopupMenuItem(
          value: 'all',
          child: Text(WorkspaceStrings.closeAll),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'close':
        widget.onClose();
      case 'others':
        widget.onCloseOthers();
      case 'right':
        widget.onCloseToRight();
      case 'all':
        widget.onCloseAll();
    }
  }

  static IconData _iconFor(WorkspaceTab tab) {
    return switch (tab.kind) {
      WorkspaceTabKind.notebooks => Icons.folder_rounded,
      WorkspaceTabKind.search => Icons.search_rounded,
      WorkspaceTabKind.settings => Icons.settings_rounded,
      WorkspaceTabKind.notes => Icons.article_outlined,
      WorkspaceTabKind.note => Icons.description_outlined,
    };
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.close_rounded, size: 15),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      hoverColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: 0.08),
    );
  }
}

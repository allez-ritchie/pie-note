import 'package:flutter/material.dart';

import '../common/strings.dart';
import 'editor_strings.dart';
import 'markdown_outline.dart';

/// 笔记大纲面板。
///
/// - **宽窗口**：作为编辑器右侧的常驻侧栏（[showHandle] 为 false，由编辑页
///   自己控制开合），点击标题跳转到正文对应位置，并高亮当前光标所在标题；
/// - **窄窗口**：放在底部弹出面板里（[showHandle] 为 true），点标题跳转后关闭。
///
/// 面板本身不持有正文，标题与高亮状态都由编辑页传入，避免两份状态不同步；
/// 折叠状态属于「这份大纲怎么展示」，由面板自己维护。
class NotesOutlinePanel extends StatefulWidget {
  const NotesOutlinePanel({
    super.key,
    required this.headings,
    required this.onJump,
    this.activeIndex = -1,
    this.onClose,
    this.showHandle = false,
    this.padded = false,
  });

  final List<MarkdownHeading> headings;
  final ValueChanged<MarkdownHeading> onJump;

  /// 当前标题序号（[-1] 表示光标在第一个标题之前）。
  final int activeIndex;

  /// 顶部关闭按钮（宽屏侧栏用；窄屏弹出面板用系统手势关闭）。
  final VoidCallback? onClose;

  /// 是否是底部弹出面板（额外给列表顶部留出拖拽手柄的空间）。
  final bool showHandle;

  /// 是否作为常驻侧栏（需要自带内边距与背景）。
  final bool padded;

  @override
  State<NotesOutlinePanel> createState() => _NotesOutlinePanelState();
}

class _NotesOutlinePanelState extends State<NotesOutlinePanel> {
  /// 已折叠的标题序号（下标与 [NotesOutlinePanel.headings] 对应）。
  ///
  /// 用下标而不是源码偏移量：改正文不影响标题顺序时，折叠状态不会错位；
  /// 增删标题后越界的下标会被裁掉（见 [didUpdateWidget]）。
  Set<int> _collapsed = <int>{};

  @override
  void initState() {
    super.initState();
    _revealedActive = widget.activeIndex;
    _revealActiveHeading();
  }

  @override
  void didUpdateWidget(covariant NotesOutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final count = widget.headings.length;
    if (_collapsed.any((index) => index >= count)) {
      _collapsed = <int>{
        for (final index in _collapsed)
          if (index < count) index,
      };
    }
    // 只有活动标题「换了」才展开上级；用户手动收起当前章节时活动标题没变，
    // 不会立刻又被展开。
    if (widget.activeIndex != _revealedActive) {
      _revealedActive = widget.activeIndex;
      _revealActiveHeading();
    }
  }

  /// 上一次自动展开时所在的活动标题，用来判断「活动标题何时换了」。
  int _revealedActive = -1;

  /// 光标走进被折叠起来的章节时，自动展开它的上级标题。
  ///
  /// 否则「当前标题」高亮会落在看不见的行上。
  void _revealActiveHeading() {
    final index = widget.activeIndex;
    if (index < 0 || index >= widget.headings.length) return;
    final ancestors = headingAncestorIndexes(widget.headings, index);
    if (ancestors.isEmpty) return;
    final hidden = ancestors.where(_collapsed.contains).toSet();
    if (hidden.isEmpty) return;
    // didUpdateWidget / initState 阶段不能直接 setState，放到帧后做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _collapsed.removeAll(hidden));
    });
  }

  /// 所有带子项的标题序号；为空说明整篇没有层级可折叠。
  Set<int> get _collapsible =>
      collapsibleHeadingIndexes(widget.headings);

  /// 可折叠项是否**全部**处于折叠状态。「全部折叠 / 全部展开」按钮据此切换。
  bool get _allCollapsed =>
      _collapsible.isNotEmpty && _collapsed.containsAll(_collapsible);

  void _toggleAll() {
    final collapsible = _collapsible;
    if (collapsible.isEmpty) return;
    setState(() {
      _collapsed = _allCollapsed
          ? <int>{}
          // 全部折叠 = 折叠所有带子项的标题（叶子标题本来就没有子项）。
          : <int>{...collapsible};
    });
  }

  void _toggleOne(int index) {
    setState(() {
      if (!_collapsed.remove(index)) _collapsed.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headings = widget.headings;
    final visible = visibleOutlineHeadings(headings, _collapsed);
    final showCollapseButton = _collapsible.isNotEmpty;
    // 折叠后不构建隐藏行（而不是构建零高度占位），长笔记滚动更顺。
    final visibleIndexes = <int>[
      for (var i = 0; i < headings.length; i++)
        if (visible[i]) i,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, widget.padded ? 12 : 4, 6, 4),
          child: Row(
            children: [
              Icon(Icons.toc_rounded, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  EditorStrings.outline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (headings.isNotEmpty)
                Text(
                  EditorStrings.outlineCount(headings.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (showCollapseButton)
                // 直接写字而不是只放图标：手机上没有 tooltip，用户看不到「全部折叠」。
                TextButton.icon(
                  key: const ValueKey<String>('outline-toggle-all'),
                  onPressed: _toggleAll,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    _allCollapsed
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _allCollapsed
                        ? EditorStrings.outlineExpandAll
                        : EditorStrings.outlineCollapseAll,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: S.close,
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (headings.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.format_list_bulleted_rounded,
                      size: 30,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      EditorStrings.outlineEmptyTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      EditorStrings.outlineEmptyMessage,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                6,
                6,
                6,
                widget.showHandle ? 24 : 12,
              ),
              itemCount: visibleIndexes.length,
              itemBuilder: (context, position) {
                final index = visibleIndexes[position];
                final heading = headings[index];
                final active = index == widget.activeIndex;
                final hasChildren = headingHasChildren(headings, index);
                final collapsed = _collapsed.contains(index);
                final label = heading.text.isEmpty
                    ? EditorStrings.outlineUntitledHeading
                    : heading.text;
                // 用缩进表达层级：标题越深缩进越大；最多缩到 6 级。
                final indent = 6.0 + (heading.level - 1) * 12.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: active
                        ? scheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      key: ValueKey<String>('outline-heading-${heading.offset}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => widget.onJump(heading),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(indent, 2, 8, 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 折叠箭头：只出现在有子项的标题前；展开时旋转朝下。
                            SizedBox(
                              width: 22,
                              height: 28,
                              child: hasChildren
                                  ? IconButton(
                                      key: ValueKey<String>(
                                        'outline-toggle-${heading.offset}',
                                      ),
                                      tooltip: collapsed
                                          ? EditorStrings.outlineExpandOne
                                          : EditorStrings.outlineCollapseOne,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 22,
                                        minHeight: 22,
                                      ),
                                      onPressed: () => _toggleOne(index),
                                      icon: AnimatedRotation(
                                        turns: collapsed ? 0 : 0.25,
                                        duration: const Duration(
                                          milliseconds: 160,
                                        ),
                                        curve: Curves.easeOut,
                                        child: Icon(
                                          Icons.chevron_right_rounded,
                                          size: 18,
                                          color: active
                                              ? scheme.primary
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            SizedBox(
                              width: 26,
                              child: Text(
                                'H${heading.level}',
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.clip,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: active
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.35,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: active
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 窄窗口下的大纲底部面板；返回用户点击的标题（关闭面板时为 null）。
Future<MarkdownHeading?> showNotesOutlineSheet(
  BuildContext context, {
  required List<MarkdownHeading> headings,
  required int activeIndex,
}) {
  return showModalBottomSheet<MarkdownHeading>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: NotesOutlinePanel(
        headings: headings,
        activeIndex: activeIndex,
        showHandle: true,
        onJump: (heading) => Navigator.of(sheetContext).pop(heading),
      ),
    ),
  );
}

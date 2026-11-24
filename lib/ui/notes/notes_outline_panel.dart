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
/// 面板本身不持有正文，标题与高亮状态都由编辑页传入，避免两份状态不同步。
class NotesOutlinePanel extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14, padded ? 12 : 4, 6, 4),
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
              if (onClose != null)
                IconButton(
                  tooltip: S.close,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
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
              padding: EdgeInsets.fromLTRB(6, 6, 6, showHandle ? 24 : 12),
              itemCount: headings.length,
              itemBuilder: (context, index) {
                final heading = headings[index];
                final active = index == activeIndex;
                final label = heading.text.isEmpty
                    ? EditorStrings.outlineUntitledHeading
                    : heading.text;
                // 用缩进表达层级：标题越深缩进越大；最多缩到 6 级。
                final indent = 8.0 + (heading.level - 1) * 12.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: active
                        ? scheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      key: ValueKey<String>(
                        'outline-heading-${heading.offset}',
                      ),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onJump(heading),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(indent, 8, 8, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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

import 'package:flutter/material.dart';

import 'editor_strings.dart';
import 'markdown_actions.dart';

/// Markdown 快捷工具条。
///
/// 直接作用于传入的 [controller]：源码模式操作整篇正文，
/// 实时预览模式操作当前展开的段落，两者行为一致。
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;

  /// 操作后重新聚焦输入框，避免键盘收起。
  final FocusNode? focusNode;

  void _run(void Function(TextEditingController) action) {
    action(controller);
    focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              _ToolTextButton(
                label: 'H1',
                tooltip: EditorStrings.toolH1,
                onTap:
                    () =>
                        _run((c) => MarkdownActions.toggleLinePrefix(c, '# ')),
              ),
              _ToolTextButton(
                label: 'H2',
                tooltip: EditorStrings.toolH2,
                onTap:
                    () =>
                        _run((c) => MarkdownActions.toggleLinePrefix(c, '## ')),
              ),
              _ToolIconButton(
                icon: Icons.format_bold_rounded,
                tooltip: EditorStrings.toolBold,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '**',
                        '**',
                        placeholder: '加粗文本',
                      ),
                    ),
              ),
              _ToolIconButton(
                icon: Icons.format_italic_rounded,
                tooltip: EditorStrings.toolItalic,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '*',
                        '*',
                        placeholder: '斜体文本',
                      ),
                    ),
              ),
              _ToolIconButton(
                icon: Icons.format_strikethrough_rounded,
                tooltip: EditorStrings.toolStrike,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '~~',
                        '~~',
                        placeholder: '删除文本',
                      ),
                    ),
              ),
              _ToolIconButton(
                icon: Icons.code_rounded,
                tooltip: EditorStrings.toolCode,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '`',
                        '`',
                        placeholder: 'code',
                      ),
                    ),
              ),
              _ToolIconButton(
                icon: Icons.data_object_rounded,
                tooltip: EditorStrings.toolCodeBlock,
                onTap: () => _run(MarkdownActions.insertCodeBlock),
              ),
              _ToolIconButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: EditorStrings.toolBullet,
                onTap:
                    () =>
                        _run((c) => MarkdownActions.toggleLinePrefix(c, '- ')),
              ),
              _ToolIconButton(
                icon: Icons.format_list_numbered_rounded,
                tooltip: EditorStrings.toolNumbered,
                onTap:
                    () =>
                        _run((c) => MarkdownActions.toggleLinePrefix(c, '1. ')),
              ),
              _ToolIconButton(
                icon: Icons.check_box_outlined,
                tooltip: EditorStrings.toolCheckbox,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.toggleLinePrefix(c, '- [ ] '),
                    ),
              ),
              _ToolIconButton(
                icon: Icons.format_quote_rounded,
                tooltip: EditorStrings.toolQuote,
                onTap:
                    () =>
                        _run((c) => MarkdownActions.toggleLinePrefix(c, '> ')),
              ),
              _ToolIconButton(
                icon: Icons.link_rounded,
                tooltip: EditorStrings.toolLink,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '[',
                        '](https://)',
                        placeholder: '链接文本',
                      ),
                    ),
              ),
              _ToolTextButton(
                label: '[[ ]]',
                tooltip: EditorStrings.toolWiki,
                onTap:
                    () => _run(
                      (c) => MarkdownActions.wrapInline(
                        c,
                        '[[',
                        ']]',
                        placeholder: '笔记标题',
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolIconButton extends StatelessWidget {
  const _ToolIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      iconSize: 21,
      icon: Icon(icon),
    );
  }
}

class _ToolTextButton extends StatelessWidget {
  const _ToolTextButton({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

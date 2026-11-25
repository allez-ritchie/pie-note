import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../common/strings.dart';

/// 围栏代码块没有写 info string 时显示的语言标签。
const String kCodeBlockPlainLabel = 'text';

/// 代码块正文样式：等宽、无底色（底色由 [MarkdownCodeBlock] 统一提供）。
///
/// 不能直接复用 [MarkdownStyleSheet.code]：行内代码用它，且带
/// `backgroundColor`，逐块铺在代码文字后面会画出许多小色带。
TextStyle markdownCodeBlockTextStyle(ThemeData theme) => TextStyle(
  fontFamily: 'monospace',
  fontSize: 13.5,
  height: 1.55,
  color: theme.colorScheme.onSurface,
);

/// 取出围栏代码块的正文（去掉解析器补的行尾换行）。
String markdownCodeBlockText(md.Element pre) {
  final text = pre.textContent;
  // CommonMark 解析器会给非空代码补一个行尾换行；展示与复制时都去掉，
  // 否则复制出来的代码末尾会多一个空行。
  return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
}

/// 取围栏代码块 info string 里的语言（` ```python ` → `python`）。
///
/// CommonMark 规定 info string 的第一个单词是语言，其余是元数据；没有语言时
/// 返回空串，由 UI 回退到 [kCodeBlockPlainLabel]。
String markdownCodeBlockLanguage(md.Element pre) {
  final children = pre.children;
  if (children == null) return '';
  for (final child in children) {
    if (child is! md.Element || child.tag != 'code') continue;
    final className = child.attributes['class'];
    if (className == null) continue;
    const prefix = 'language-';
    if (!className.startsWith(prefix)) continue;
    final language = className.substring(prefix.length).trim();
    if (language.isNotEmpty) return language;
  }
  return '';
}

/// 把围栏代码块渲染成「右上角语言小按钮 + 可横向滚动的等宽代码」。
///
/// 没有直接使用 `flutter_markdown_plus` 默认的 `pre` 有两个原因：
/// - 默认实现既不显示语言、也不能点按复制；
/// - 默认宽度跟最长一行收缩：短代码块的底色只有半截，同一篇笔记里两块代码
///   宽度不一致。这里强制铺满正文宽度（[LayoutBuilder] 取父级最大宽度，
///   无界时退回自然宽度，避免在横向滚动容器里报无限宽度）。
///
/// 点按行为：
/// - [onTap] 为空（阅读视图 / 对话 / 来源等只读渲染）：点整块即复制；
/// - [onTap] 非空（实时预览）：点整块交给上层「就地展开这一段源码」，
///   复制走右上角的语言按钮 —— 否则实时预览里再也点不开代码块了。
class MarkdownCodeBlock extends StatefulWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.code,
    required this.language,
    required this.textStyle,
    this.onTap,
  });

  /// 代码正文（不含行尾换行）。
  final String code;

  /// info string 里的语言；为空时按 [kCodeBlockPlainLabel] 展示。
  final String language;

  /// 代码正文样式。
  final TextStyle textStyle;

  /// 点按代码块主体的动作；为空表示「点按即复制」。
  final VoidCallback? onTap;

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  /// 刚复制过：语言按钮临时变成「已复制」，就地反馈比底部 SnackBar 更轻，
  /// 也不会遮住正文。
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _copied
        ? S.codeCopied
        : (widget.language.isEmpty ? kCodeBlockPlainLabel : widget.language);
    final block = Material(
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: widget.onTap ?? _copy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 语言按钮独占顶部一行（右对齐），不压住第一行代码。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: _CodeLanguageButton(
                  label: label,
                  active: _copied,
                  onTap: _copy,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // 只横向滚动：纵向滚动交给正文所在滚动区，避免长代码块里再套一层
              // 纵向滚动区把滚轮吃掉。
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: Text(
                widget.code,
                style: widget.textStyle,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 铺满正文宽度：短代码块与长代码块底色等宽（父级宽度无界时保持自然宽度）。
        if (!constraints.hasBoundedWidth) return block;
        return SizedBox(width: constraints.maxWidth, child: block);
      },
    );
  }
}

/// 右上角的小按钮：平时显示代码块语言，点按复制。
class _CodeLanguageButton extends StatelessWidget {
  const _CodeLanguageButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;

  /// 刚复制完：换成勾选图标 + 「已复制」。
  final bool active;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: S.copyCode,
      child: Semantics(
        button: true,
        label: '${S.copyCode}（$label）',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active) ...[
                  Icon(Icons.check_rounded, size: 12, color: color),
                  const SizedBox(width: 3),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `flutter_markdown_plus` 的 `pre` 元素构建器：交给 [MarkdownCodeBlock] 渲染。
///
/// [isBlockElement] 保持 false：`pre` 本来就是包内固定的块级 tag，声明为 true
/// 会让包内的块级 tag 列表在每次解析时重复追加同一个 tag。
class MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  MarkdownCodeBlockBuilder({required this.textStyle, this.onTap});

  final TextStyle textStyle;

  /// 点按代码块主体的动作（实时预览传「就地编辑」）；为空表示点按复制。
  final VoidCallback? onTap;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // 代码正文统一在 visitElementAfterWithContext 里从 element.textContent 取，
    // 这里再产出一份就会把源码渲染两遍。
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return MarkdownCodeBlock(
      code: markdownCodeBlockText(element),
      language: markdownCodeBlockLanguage(element),
      textStyle: textStyle,
      onTap: onTap,
    );
  }
}

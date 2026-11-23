import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/providers.dart';
import '../common/navigation.dart';
import 'editor_strings.dart';

/// Markdown 预览。
///
/// 约定：
/// - `[[标题]]` 会渲染成可点击的双链，点击后在全部笔记中按标题查找并跳转；
/// - `![alt](url)` **不加载图片**，渲染为占位块（本仓库暂不处理图片链接）；
/// - `http/https` 外链交给系统浏览器打开；
/// - 传入 [onToggleTask] 时，任务列表复选框可点击切换（预览时编辑）；
/// - 传入 [onTapText] 时，点击渲染文本会回调（实时预览用来就地展开该段源码）。
class MarkdownView extends ConsumerWidget {
  const MarkdownView({
    super.key,
    required this.content,
    this.onTapText,
    this.onToggleTask,
    this.taskStartIndex = 0,
    this.selectable = false,
  });

  final String content;

  /// 点击渲染文本时回调。
  final VoidCallback? onTapText;

  /// 切换任务列表复选框；参数是**全篇**的任务项序号（第 N 个复选框）。
  final ValueChanged<int>? onToggleTask;

  /// 本段内容之前已有多少任务项，用于把局部序号换算成全篇序号。
  final int taskStartIndex;

  /// 是否允许选中文本。
  ///
  /// 桌面端在「阅读」视图里常要复制正文；而实时预览的渲染态需要点按段落
  /// 进入编辑，开启选中会与点击手势冲突，因此只在阅读视图显式开启。
  final bool selectable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styleSheet = _buildStyleSheet(theme);
    // 复选框按文档顺序构建，用闭包计数把「第几个复选框」换算成全篇序号。
    var localTaskIndex = 0;
    return MarkdownBody(
      data: transformWikiLinks(content),
      selectable: selectable,
      styleSheet: styleSheet,
      onTapText: onTapText,
      onTapLink: (text, href, title) => _handleLink(context, ref, href),
      imageBuilder: (uri, title, alt) => GestureDetector(
        onTap: onTapText,
        child: _ImagePlaceholder(uri: uri, alt: alt),
      ),
      checkboxBuilder: onToggleTask == null
          ? null
          : (checked) {
              final index = taskStartIndex + localTaskIndex++;
              return _TaskCheckbox(
                checked: checked,
                onToggle: () => onToggleTask!(index),
              );
            },
    );
  }

  Future<void> _handleLink(BuildContext context, WidgetRef ref, String? href) async {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;

    // 双链：[[笔记标题]] → wikilink:<encoded title>
    if (uri.scheme == 'wikilink') {
      final title = Uri.decodeComponent(uri.path);
      final repository = ref.read(repositoryProvider);
      if (repository == null) return;
      try {
        final note = await repository.findNoteByTitle(title);
        if (!context.mounted) return;
        if (note == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('未找到标题为「$title」的笔记')),
          );
          return;
        }
        await AppNavigator.openEditor(context, noteId: note.id);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开双链失败：$error')),
        );
      }
      return;
    }

    // 外链：交给系统浏览器；不处理图片/文件等其它 scheme。
    if (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto') {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接：$href')),
        );
      }
    }
  }

  MarkdownStyleSheet _buildStyleSheet(ThemeData theme) {
    final scheme = theme.colorScheme;
    final base = MarkdownStyleSheet.fromTheme(theme);
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.55,
      color: scheme.onSurface,
    );
    return base.copyWith(
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.4),
      ),
      p: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.5, height: 1.7),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h4: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      h5: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      h6: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      strong: const TextStyle(fontWeight: FontWeight.w700),
      em: const TextStyle(fontStyle: FontStyle.italic),
      code: mono.copyWith(
        backgroundColor: scheme.surfaceContainerHighest,
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      listBullet: theme.textTheme.bodyMedium,
      tableHead: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      tableBody: theme.textTheme.bodySmall,
      tableBorder: TableBorder.all(
        color: scheme.outlineVariant,
        width: 0.7,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
    );
  }
}

/// 任务列表复选框：预览态可直接点选，切换源码里的 `[ ]` / `[x]`。
class _TaskCheckbox extends StatelessWidget {
  const _TaskCheckbox({required this.checked, required this.onToggle});

  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: checked,
      inMutuallyExclusiveGroup: true,
      label: checked ? EditorStrings.taskDone : EditorStrings.taskTodo,
      child: InkResponse(
        onTap: onToggle,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Icon(
            checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 21,
            color: checked ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 图片占位：本仓库不处理图片链接，只展示 alt 文本与来源，避免发起网络请求。
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.uri, this.alt});

  final Uri uri;
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = (alt == null || alt!.trim().isEmpty) ? '图片' : alt!.trim();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.image_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label（图片链接暂不渲染）',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

final RegExp _wikiLinkPattern = RegExp(r'\[\[([^\[\]\n]+)\]\]');

/// 把 `[[标题]]` 转成 Markdown 链接 `[标题](wikilink:<encoded>)`，
/// 并跳过围栏代码块与行内代码，避免误伤代码内容。
String transformWikiLinks(String markdown) {
  if (!markdown.contains('[[')) return markdown;
  final lines = markdown.split('\n');
  var inFence = false;
  final output = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      output.add(line);
      continue;
    }
    if (inFence) {
      output.add(line);
      continue;
    }
    // 行内代码按反引号切分，只处理偶数段（非代码段）。
    final segments = line.split('`');
    for (var i = 0; i < segments.length; i++) {
      if (i.isEven) {
        segments[i] = segments[i].replaceAllMapped(_wikiLinkPattern, (match) {
          final title = match.group(1)!.trim();
          if (title.isEmpty) return match.group(0)!;
          final encoded = Uri.encodeComponent(title);
          return '[${_escapeInlineLinkText(title)}](wikilink:$encoded)';
        });
      }
    }
    output.add(segments.join('`'));
  }
  return output.join('\n');
}

/// 双链文本里可能出现的 `]` / `[` 会破坏 Markdown 链接语法，做最小转义。
String _escapeInlineLinkText(String text) =>
    text.replaceAll('[', '\\[').replaceAll(']', '\\]');

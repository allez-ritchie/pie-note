import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/providers.dart';
import '../../state/workspace.dart';
import '../common/navigation.dart';
import '../home/workspace_navigator.dart';
import 'editor_strings.dart';
import 'markdown_code_block.dart';

/// Markdown 预览。
///
/// 约定：
/// - `[[标题]]` 会渲染成可点击的双链，点击后在全部笔记中按标题查找并跳转；
/// - `![alt](url)` **不加载图片**，渲染为占位块（本仓库暂不处理图片链接）；
/// - `http/https` 外链交给系统浏览器打开；
/// - 围栏代码块由 [MarkdownCodeBlock] 渲染：等宽、右上角显示语言、点按复制；
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
    this.onTapCodeBlock,
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
  ///
  /// 注意：选中能力由上层 [SelectionArea] 提供（而不是给每个段落各开一个
  /// `SelectableText`）。Markdown 渲染会按段落 / 列表项 / 标题拆成多个
  /// 独立文本组件，各自开选区就只能一段一段选、跨段复制不了；套在一个
  /// [SelectionArea] 里才能像网页一样连续选择并一次复制全文。
  final bool selectable;

  /// 点按围栏代码块时的回调（实时预览用来就地展开该段源码）。
  ///
  /// 为空时点按代码块即为「复制代码」（阅读视图 / 对话 / 来源等只读场景）。
  final VoidCallback? onTapCodeBlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final styleSheet = buildMarkdownStyleSheet(theme);
    // 复选框按文档顺序构建，用闭包计数把「第几个复选框」换算成全篇序号。
    var localTaskIndex = 0;
    final body = MarkdownBody(
      data: transformWikiLinks(content),
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
      // 围栏代码块：右上角语言角标 + 点按复制（等宽铺满正文，见组件注释）。
      builders: {
        'pre': MarkdownCodeBlockBuilder(
          textStyle: markdownCodeBlockTextStyle(theme),
          onTap: onTapCodeBlock,
        ),
      },
    );
    if (!selectable) return body;
    // 选中态：整个渲染树套一个 SelectionArea，段落之间可以连续选择、一次复制。
    // 不能改用 MarkdownBody.selectable：它会给每个段落各建一个 SelectableText，
    // 选区互不相通（跨段拖选只能选中一段）。
    //
    // 上层已经提供了选区容器（阅读视图把整页包在一个 SelectionArea 里，这样
    // 跨「节」也能连续选）时不要再套一层：嵌套的 SelectionArea 会互相抢手势，
    // 外层反而选不中。
    if (SelectionContainer.maybeOf(context) != null) return body;
    return SelectionArea(child: body);
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
        // 在多标签工作区里打开为标签页；独立路由（例如单元测试）保持原行为。
        if (ref.read(workspaceProvider).hasTabs) {
          WorkspaceNavigator.openNote(
            ref,
            noteId: note.id,
            title: note.displayTitle,
          );
        } else {
          await AppNavigator.openEditor(context, noteId: note.id);
        }
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

}

/// 标题上方的额外留白（参考 Obsidian：标题上方比正文段落更松，分节更清晰）。
///
/// 级别越高留白越大；实时预览与阅读视图都按段落分块渲染，标题块要在自己
/// 内部补上这段上边距，否则标题会紧贴上一段。数值是密度适中的经验值。
double markdownHeadingTopSpacing(int level) {
  switch (level) {
    case 1:
      return 22;
    case 2:
      return 20;
    case 3:
      return 16;
    case 4:
      return 14;
    case 5:
      return 12;
    default:
      return 10;
  }
}

/// ATX 标题识别，与 `markdown_outline.dart` 的解析规则保持一致。
///
/// 末尾的 `\r` 是 CRLF 正文按 `\n` 切开后的行尾残留，必须容忍，否则混用 CRLF 的
/// 标题在实时预览里会丢掉标题上方的留白；`#标题` 这类非法 ATX 仍不算标题。
final RegExp _leadingAtxHeadingPattern = RegExp(
  r'^ {0,3}(#{1,6})(?:[ \t]|\r?$)',
);

/// 取一段源码第一行的 ATX 标题级别（不是标题时返回 null）。
///
/// 实时预览的就地输入框会替换掉 Markdown 渲染，需要按同样数值补上标题上方
/// 的留白，避免点按标题展开源码时整篇正文上下跳动。
int? markdownLeadingHeadingLevel(String text) {
  final firstLine = text.split('\n').first;
  final match = _leadingAtxHeadingPattern.firstMatch(firstLine);
  return match?.group(1)?.length;
}

/// 全 App 统一的 Markdown 渲染样式（预览、阅读、来源正文共用）。
MarkdownStyleSheet buildMarkdownStyleSheet(ThemeData theme) {
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
    // 标题上方留白：Obsidian 风格的大标题间距。
    h1Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(1), bottom: 6),
    h2Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(2), bottom: 4),
    h3Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(3), bottom: 3),
    h4Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(4), bottom: 2),
    h5Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(5), bottom: 2),
    h6Padding: EdgeInsets.only(top: markdownHeadingTopSpacing(6), bottom: 2),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    em: const TextStyle(fontStyle: FontStyle.italic),
    code: mono.copyWith(
      backgroundColor: scheme.surfaceContainerHighest,
      fontSize: 13,
    ),
    // 围栏代码块（`pre`）的外层容器由 `MarkdownCodeBlock` 自己绘制底色与圆角
    // （见 markdown_code_block.dart）。这里保持空装饰，避免包内再套一层同色
    // 容器：两层圆角叠加会在四角留下细微的双重描边。
    // 包内只在**没有**自定义 `pre` 构建器时才用这两项，因此留空是安全的。
    codeblockDecoration: const BoxDecoration(),
    codeblockPadding: EdgeInsets.zero,
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

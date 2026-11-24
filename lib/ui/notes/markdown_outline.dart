// Markdown 大纲：从源码里提取 ATX 标题（`#` ~ `######`），并给出可跳转的偏移量。
//
// 解析必须与 [MarkdownSourceMap] 的切块规则保持一致：
// - 围栏代码块（``` / ~~~）里的 `#` 不算标题；
// - 标题行最多允许 3 个前导空格（CommonMark 的 ATX 规则），`#标题` 不带空格不算；
// - 允许收尾的 `#` 序列（`## 标题 ##`），展示时去掉。

import 'markdown_blocks.dart';

/// 一个 ATX 标题及其在源码中的位置。
class MarkdownHeading {
  const MarkdownHeading({
    required this.level,
    required this.text,
    required this.raw,
    required this.offset,
    required this.end,
    required this.textStart,
  });

  /// 标题级别 1~6（对应 `#` 的数量）。
  final int level;

  /// 去掉 `#`、收尾 `#` 与行内标记后的展示文本；可能为空。
  final String text;

  /// 标题行的源码（不含换行），供调试/提示使用。
  final String raw;

  /// 标题行在整篇源码中的起始偏移量。
  final int offset;

  /// 标题行结束偏移量（不含换行）。
  final int end;

  /// 标题正文的起始偏移量（`#` 与空格之后），用于把光标/滚动定位到标题。
  final int textStart;
}

/// 一条大纲跳转请求。
///
/// 用对象而不是裸 `int`：`ValueNotifier` 按 `==` 判断变化，重复点击同一个标题
/// 也要能重新触发定位，因此每次请求都是新实例（默认按引用比较）。
class OutlineJumpRequest {
  const OutlineJumpRequest(this.offset);

  /// 目标在源码中的偏移量。
  final int offset;
}

/// ATX 标题行：0~3 个前导空格 + 1~6 个 `#` + 空白或行尾 + 正文。
final RegExp _atxHeadingPattern = RegExp(
  r'^( {0,3})(#{1,6})(?:[ \t]+(.*?))?[ \t]*$',
);

/// 可选的收尾 `#` 序列（`## 标题 ###`）。
final RegExp _closingHashesPattern = RegExp(r'[ \t]+#+[ \t]*$');

final RegExp _markdownImagePattern = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final RegExp _markdownLinkPattern = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _wikiLinkPattern = RegExp(r'\[\[([^\[\]\n]+)\]\]');
final RegExp _htmlTagPattern = RegExp(r'<[^>]+>');
final RegExp _escapedPunctuationPattern = RegExp(
  r'\\([\\`*_{}\[\]()#+\-.!~>|])',
);

/// 解析整篇 Markdown 里的标题（按出现顺序）。
List<MarkdownHeading> parseMarkdownHeadings(String markdown) {
  if (markdown.trim().isEmpty) return const <MarkdownHeading>[];
  final headings = <MarkdownHeading>[];
  var inFence = false;
  var lineStart = 0;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      // 围栏边界与代码块内容都不产生标题（与渲染分块一致）。
      inFence = !inFence;
      lineStart += line.length + 1;
      continue;
    }
    if (inFence) {
      lineStart += line.length + 1;
      continue;
    }
    final match = _atxHeadingPattern.firstMatch(line);
    if (match != null) {
      final hashes = match.group(2)!;
      final body = match.group(3) ?? '';
      final cleaned = body.replaceFirst(_closingHashesPattern, '');
      // `Match` 没有「分组起始位置」，手工跳过 `#` 后的空白得到正文起点。
      var bodyStart = line.indexOf(hashes) + hashes.length;
      while (bodyStart < line.length &&
          (line[bodyStart] == ' ' || line[bodyStart] == '\t')) {
        bodyStart++;
      }
      headings.add(
        MarkdownHeading(
          level: hashes.length,
          text: stripMarkdownInline(cleaned).trim(),
          raw: line,
          offset: lineStart,
          end: lineStart + line.length,
          textStart: lineStart + bodyStart,
        ),
      );
    }
    lineStart += line.length + 1;
  }
  return headings;
}

/// 去掉标题里的行内 Markdown 标记，得到适合在窄侧栏里展示的纯文本。
///
/// 只处理常见的展示噪音（图片/链接/双链/HTML 标签/行内代码/强调标记），
/// 不追求还原完整语法：标题在渲染时仍按原文展示。
String stripMarkdownInline(String source) {
  if (source.isEmpty) return source;
  var text = source
      .replaceAllMapped(_markdownImagePattern, (match) => match.group(1) ?? '')
      .replaceAllMapped(_markdownLinkPattern, (match) => match.group(1) ?? '')
      .replaceAllMapped(_wikiLinkPattern, (match) => match.group(1) ?? '');
  text = text
      .replaceAll(_htmlTagPattern, '')
      .replaceAllMapped(_escapedPunctuationPattern, (match) => match.group(1)!)
      .replaceAll('`', '')
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAll('~~', '')
      .replaceAll('*', '');
  return text;
}

/// 光标 / 滚动位置 [offset] 落在哪个标题上：返回最后一个起始偏移量不超过它的标题。
///
/// 用于大纲的「当前标题」高亮。位置在第一个标题之前时返回 -1。
int activeHeadingIndex(List<MarkdownHeading> headings, int? offset) {
  if (offset == null || headings.isEmpty) return -1;
  var result = -1;
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].offset > offset) break;
    result = i;
  }
  return result;
}

/// 按标题切出的一节正文：从一个标题开始，到下一个标题之前结束。
///
/// 阅读视图需要「点大纲滚到对应标题」，因此把正文按标题分组渲染，每节挂一个
/// `GlobalKey`；只在**标题行**处切开（渲染器本来就把标题当块边界），所以列表、
/// 引用、代码块不会因为切分而改变渲染结果。
class MarkdownSection {
  const MarkdownSection({
    required this.start,
    required this.end,
    required this.markdown,
    required this.taskOffset,
  });

  /// 本节在整篇源码中的起始偏移量（通常就是标题行的起点）。
  final int start;

  /// 本节结束偏移量（不含结尾空行）。
  final int end;

  /// 本节源码。
  final String markdown;

  /// 本节之前（不含本节）的任务项数量，用于把复选框映射回全篇序号。
  final int taskOffset;
}

/// 按标题把整篇 Markdown 切成若干节；没有标题时整篇是一节。
List<MarkdownSection> splitMarkdownSections(String markdown) {
  final blocks = splitMarkdownBlocks(markdown);
  if (blocks.isEmpty) return const <MarkdownSection>[];
  final headingOffsets = <int>{
    for (final heading in parseMarkdownHeadings(markdown)) heading.offset,
  };
  final sections = <MarkdownSection>[];
  for (final block in blocks) {
    final startsSection = headingOffsets.contains(block.start);
    if (sections.isEmpty || startsSection) {
      sections.add(
        MarkdownSection(
          start: block.start,
          end: block.end,
          markdown: block.text,
          taskOffset: block.taskOffset,
        ),
      );
      continue;
    }
    final last = sections.removeLast();
    sections.add(
      MarkdownSection(
        start: last.start,
        end: block.end,
        markdown: '${last.markdown}\n\n${block.text}',
        taskOffset: last.taskOffset,
      ),
    );
  }
  return sections;
}

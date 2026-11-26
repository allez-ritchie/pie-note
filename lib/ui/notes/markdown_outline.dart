// Markdown 大纲：从源码里提取 ATX 标题（`#` ~ `######`），并给出可跳转的偏移量。
//
// 解析必须与 [MarkdownSourceMap] 的切块规则保持一致：
// - 围栏代码块（``` / ~~~）里的 `#` 不算标题；
// - 标题行最多允许 3 个前导空格（CommonMark 的 ATX 规则），`#标题` 不带空格不算；
// - 允许收尾的 `#` 序列（`## 标题 ##`），展示时去掉；
// - 正文混用 CRLF 时，标题行会以 `\r` 结尾（`#### 标题\r`）：解析只容忍这个行尾
//   `\r`，不能因为 Dart 的 `$` 不允许在 `\r` 前结束匹配就把整行丢掉，
//   但也不放宽 `#标题` 这类非法 ATX 的判定。

import 'dart:convert';

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
  ///
  /// CRLF 混用的正文里会保留行尾的 `\r`，与 [offset]/[end] 的范围严格对齐。
  final String raw;

  /// 标题行在整篇源码中的起始偏移量。
  final int offset;

  /// 标题行结束偏移量（不含换行）。
  ///
  /// 行尾是 CRLF 时包含那个 `\r`：`markdown.substring(offset, end) == raw`。
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
///
/// 末尾的 `\r` 是 CRLF 正文被按 `\n` 切开后残留的行尾符：Dart 的 `$` 不允许在
/// `\r` 之前结束匹配，这里显式容忍它，否则整行标题会被丢掉。
final RegExp _atxHeadingPattern = RegExp(
  r'^( {0,3})(#{1,6})(?:[ \t]+(.*?))?[ \t]*\r?$',
);

/// 可选的收尾 `#` 序列（`## 标题 ###`），同样容忍 CRLF 残留的 `\r`。
final RegExp _closingHashesPattern = RegExp(r'[ \t]+#+[ \t]*\r?$');

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

/// 解码锚点片段（`#` 之后的部分）。
///
/// 目录里的锚点可能是原文（含中文、空格、`%`），也可能是 percent-encoded。
/// 直接用 `Uri.decodeComponent` 遇到 `100%` 这种非法编码会抛
/// `ArgumentError`（点一下目录就崩），所以先做合法的 `%XX` 解码、其余原样保留。
String decodeAnchorFragment(String fragment) {
  if (!fragment.contains('%')) return fragment;
  final buffer = StringBuffer();
  for (var i = 0; i < fragment.length; i++) {
    final char = fragment[i];
    if (char != '%' || i + 2 >= fragment.length) {
      buffer.write(char);
      continue;
    }
    final hex = fragment.substring(i + 1, i + 3);
    final value = int.tryParse(hex, radix: 16);
    if (value == null) {
      buffer.write(char);
      continue;
    }
    // 逐字节解出 UTF-8：中文锚点编码后是连续的多个 %XX。
    final bytes = <int>[value];
    var next = i + 3;
    while (next + 2 < fragment.length && fragment[next] == '%') {
      final more = int.tryParse(fragment.substring(next + 1, next + 3), radix: 16);
      if (more == null) break;
      bytes.add(more);
      next += 3;
    }
    try {
      buffer.write(utf8.decode(bytes));
      i = next - 1;
    } catch (_) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// 锚点匹配用的宽松键：只保留字母、数字与汉字，并统一小写。
///
/// 标题锚点在 Markdown 笔记里没有统一标准：GitHub 生成的是「小写 + 空格转 `-` +
/// 去标点」，编辑器 / 手工写的目录还常有全角括号、`：`、`/`、`+` 等。把这些差异
/// 全部丢掉后再比，才能让 `#1-准备段每条命令前先跑一次` 命中
/// `1. 准备段（每条命令前先跑一次）`。
final RegExp _anchorKeyChar = RegExp(r'[0-9a-z\u3400-\u4dbf\u4e00-\u9fff]');

String headingAnchorKey(String text) {
  final buffer = StringBuffer();
  for (final code in text.toLowerCase().runes) {
    final char = String.fromCharCode(code);
    if (_anchorKeyChar.hasMatch(char)) buffer.write(char);
  }
  return buffer.toString();
}

/// GitHub 风格的标题锚点：只保留字母数字汉字与 `-` / `_`，空白转 `-`。
///
/// 与 [headingAnchorKey] 的区别是它保留分隔符，用于优先精确命中标准写法；
/// 命中不了时再退到宽松键。
String headingAnchorSlug(String text) {
  final buffer = StringBuffer();
  var pendingDash = false;
  for (final code in text.toLowerCase().runes) {
    final char = String.fromCharCode(code);
    if (char == ' ' || char == '\t') {
      pendingDash = buffer.isNotEmpty;
      continue;
    }
    if (_anchorKeyChar.hasMatch(char) || char == '-' || char == '_') {
      if (pendingDash) {
        buffer.write('-');
        pendingDash = false;
      }
      buffer.write(char);
    }
  }
  return buffer.toString();
}

/// 按锚点片段（`[目录](#这里)` 里 `#` 之后的部分）找标题。
///
/// 匹配顺序（越往后越宽松，但**只在没有歧义时**才接受，绝不猜）：
/// 1. GitHub 风格 slug 精确匹配（`#1-准备段每条命令前先跑一次`）；
/// 2. 宽松键精确匹配（忽略标点 / 空格 / 大小写 / 全角符号，`#1. 准备段`）；
/// 3. 唯一前缀匹配（目录里省略了副标题）；
/// 4. 唯一包含匹配（锚点只写了标题中间一段）。
/// 都命中不了返回 null（调用方负责提示「找不到这个锚点」）。
///
/// 同名标题（锚点重复）取文档里第一个，与 GitHub 的行为一致到「至少不会跳错章节」；
/// 有多个候选的宽松匹配一律返回 null，宁可提示也不跳到错误章节。
MarkdownHeading? findHeadingByAnchor(
  List<MarkdownHeading> headings,
  String fragment,
) {
  // 目录里的锚点可能带编码、也可能用缩略写法，统一解一次。
  final target = decodeAnchorFragment(fragment).trim();
  if (target.isEmpty || headings.isEmpty) return null;

  // 1. GitHub 风格 slug 精确命中（标准写法，优先级最高）。
  for (final heading in headings) {
    if (headingAnchorSlug(heading.text) == target) return heading;
  }

  // 2. 宽松键精确命中（忽略标点 / 空格 / 大小写 / 全角半角）。
  final key = headingAnchorKey(target);
  if (key.isEmpty) return null;
  for (final heading in headings) {
    if (headingAnchorKey(heading.text) == key) return heading;
  }

  // 3. 唯一前缀：目录里常省略标题的后半段（`#1-准备段` 指向
  //    `1. 准备段（每条命令前先跑一次）`）。要求锚点足够长，避免「1」这种
  //    短锚点命中一串章节；多个候选说明锚点太模糊，不作猜测。
  if (key.length >= 4) {
    final prefixHits = <MarkdownHeading>[
      for (final heading in headings)
        if (headingAnchorKey(heading.text).startsWith(key)) heading,
    ];
    if (prefixHits.length == 1) return prefixHits.first;
    if (prefixHits.length > 1) return null;
  }

  // 4. 唯一包含：锚点只写了标题中间的一段。多条命中说明锚点太模糊，
  //    宁可提示找不到也不跳错章节。
  if (key.length >= 2) {
    final containsHits = <MarkdownHeading>[
      for (final heading in headings)
        if (headingAnchorKey(heading.text).contains(key)) heading,
    ];
    if (containsHits.length == 1) return containsHits.first;
  }
  return null;
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

/// 标题 [index] 是否拥有子标题（紧随其后、级别更深的任意标题）。
///
/// 大纲的折叠箭头只在「有子项」的标题上出现；`## A` 后面直接跟着另一个
/// `## B` 时两者是兄弟，A 没有子项。
bool headingHasChildren(List<MarkdownHeading> headings, int index) {
  if (index < 0 || index + 1 >= headings.length) return false;
  // 标题按文档顺序排列：紧随其后的标题若更深，它就是本标题的子项；
  // 同级或更浅则本标题没有子项（后面的属于兄弟或更上层）。
  return headings[index + 1].level > headings[index].level;
}

/// 标题 [index] 的所有祖先标题序号（由浅到深），不含自身。
///
/// 用于「光标进入被折叠的章节时自动展开它的上级标题」。
List<int> headingAncestorIndexes(List<MarkdownHeading> headings, int index) {
  if (index <= 0 || index >= headings.length) return const <int>[];
  final level = headings[index].level;
  final ancestors = <int>[];
  // 从本项往前扫，每遇到更浅的标题就记一个祖先，直到没有更浅的。
  var currentLevel = level;
  for (var i = index - 1; i >= 0 && currentLevel > 1; i--) {
    if (headings[i].level < currentLevel) {
      ancestors.insert(0, i);
      currentLevel = headings[i].level;
    }
  }
  return ancestors;
}

/// 折叠状态 [collapsed] 下，每个标题是否是「可见」的。
///
/// 折叠语义与 Obsidian 一致：折叠某个标题只隐藏它的**子孙标题**，
/// 兄弟标题不受影响。因此只要某个标题的任意祖先被折叠，它就不可见。
/// 返回值与 [headings] 等长、一一对应。
List<bool> visibleOutlineHeadings(
  List<MarkdownHeading> headings,
  Set<int> collapsed,
) {
  if (headings.isEmpty) return const <bool>[];
  final visible = List<bool>.filled(headings.length, true);
  // 祖先栈：每一层记录「最近一个该级别的标题索引」。
  final levelStack = <int>[];
  final indexByLevel = <int, int>{};
  for (var i = 0; i < headings.length; i++) {
    final level = headings[i].level;
    // 弹出所有同级或更深的层级，栈顶就是最近的父级标题。
    while (levelStack.isNotEmpty && levelStack.last >= level) {
      levelStack.removeLast();
    }
    final parent = levelStack.isEmpty ? null : indexByLevel[levelStack.last];
    levelStack.add(level);
    indexByLevel[level] = i;
    if (parent == null) {
      visible[i] = true;
      continue;
    }
    // 父级可见且未折叠，本项才可见（父级自身的可见性已在前面确定）。
    visible[i] = visible[parent] && !collapsed.contains(parent);
  }
  return visible;
}

/// 需要折叠的全部标题序号：所有带子项的标题（「全部折叠」按钮用）。
Set<int> collapsibleHeadingIndexes(List<MarkdownHeading> headings) {
  return <int>{
    for (var i = 0; i < headings.length; i++)
      if (headingHasChildren(headings, i)) i,
  };
}

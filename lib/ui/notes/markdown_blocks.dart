import 'markdown_tasks.dart';

/// Markdown 源码分块：把整篇笔记切成「渲染块」。
///
/// 实时预览（Live Preview）需要「点哪个段落就编辑哪个段落」，因此必须能在
/// 「渲染态」和「源码」之间来回切换，同时保证**保存时字节级还原**。
///
/// 这里把源码切成 `前导空白 + 块文本` 的序列（[MarkdownSegment]）：
/// - 块之间只按空行分隔，围栏代码块内部的空行不切（否则会破坏代码块）；
/// - ATX 标题行后强制切块，便于只编辑标题本身；
/// - [MarkdownSourceMap.join] 能拼回原文，编辑某一块不会吞掉段落分隔。
class MarkdownSegment {
  const MarkdownSegment({required this.gap, required this.text});

  /// 与上一块之间的空白（第一块为全文开头空白）。
  final String gap;

  /// 块的源码文本。
  final String text;

  MarkdownSegment copyWith({String? gap, String? text}) {
    return MarkdownSegment(gap: gap ?? this.gap, text: text ?? this.text);
  }
}

/// 一篇 Markdown 的分块结果，以及可逆的拼接操作。
class MarkdownSourceMap {
  const MarkdownSourceMap._({required this.segments, required this.tail});

  final List<MarkdownSegment> segments;

  /// 最后一个块之后的空白（通常是文件末尾换行）。
  final String tail;

  static const MarkdownSourceMap empty = MarkdownSourceMap._(
    segments: <MarkdownSegment>[],
    tail: '',
  );

  /// 切分源码。空内容返回 [empty]。
  factory MarkdownSourceMap.parse(String markdown) {
    if (markdown.trim().isEmpty) return empty;
    final ranges = _scanBlockRanges(markdown);
    if (ranges.isEmpty) return empty;
    final segments = <MarkdownSegment>[];
    var previousEnd = 0;
    for (final range in ranges) {
      segments.add(
        MarkdownSegment(
          gap: markdown.substring(previousEnd, range.start),
          text: markdown.substring(range.start, range.end),
        ),
      );
      previousEnd = range.end;
    }
    return MarkdownSourceMap._(
      segments: segments,
      tail: markdown.substring(previousEnd),
    );
  }

  /// 拼回完整源码。
  String join() {
    final buffer = StringBuffer();
    for (final segment in segments) {
      buffer
        ..write(segment.gap)
        ..write(segment.text);
    }
    buffer.write(tail);
    return buffer.toString();
  }

  /// 用 [text] 替换第 [index] 块的源码，返回新的分块结果（首尾空白保持不变）。
  MarkdownSourceMap replaceText(int index, String text) {
    if (index < 0 || index >= segments.length) return this;
    final next = List<MarkdownSegment>.of(segments);
    next[index] = next[index].copyWith(text: text);
    return MarkdownSourceMap._(segments: next, tail: tail);
  }

  /// 第 [index] 块在源码中的起始偏移量。
  int startOf(int index) {
    var offset = 0;
    for (var i = 0; i < segments.length && i <= index; i++) {
      offset += segments[i].gap.length;
      if (i == index) break;
      offset += segments[i].text.length;
    }
    return offset;
  }

  /// 渲染块列表：附带源码偏移量与任务项序号，便于把点击/勾选映射回源码。
  List<MarkdownBlock> get blocks {
    final blocks = <MarkdownBlock>[];
    var offset = 0;
    var taskOffset = 0;
    for (final segment in segments) {
      offset += segment.gap.length;
      blocks.add(
        MarkdownBlock(
          start: offset,
          text: segment.text,
          taskOffset: taskOffset,
        ),
      );
      offset += segment.text.length;
      taskOffset += MarkdownTasks.count(segment.text);
    }
    return blocks;
  }
}

/// 渲染块：一段可独立渲染的 Markdown，以及它在源码中的位置。
class MarkdownBlock {
  const MarkdownBlock({
    required this.start,
    required this.text,
    required this.taskOffset,
  });

  /// 在整篇 Markdown 源码中的起始偏移量。
  final int start;

  /// 块的源码文本。
  final String text;

  /// 本块之前（不含本块）的任务项数量，用于把渲染态复选框映射回源码。
  final int taskOffset;

  int get end => start + text.length;
}

/// 是否为围栏代码块的边界行（``` 或 ~~~）。
bool _isFenceLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('```') || trimmed.startsWith('~~~');
}

/// 是否为 ATX 标题行（`# 标题`）。标题总是独立成块。
final RegExp _headingPattern = RegExp(r'^ {0,3}#{1,6}(?:[ \t]|$)');

/// 扫描出每个非空块的 `[start, end)` 范围。
///
/// 未闭合的围栏代码块会把剩余内容作为一个块（与渲染一致，容忍不规范文本）。
List<({int start, int end})> _scanBlockRanges(String markdown) {
  final ranges = <({int start, int end})>[];
  int? currentStart;
  var currentEnd = 0;
  var lineStart = 0;
  var inFence = false;

  void flush() {
    final start = currentStart;
    if (start == null) return;
    // 块尾统一去掉换行：换行属于块间空白，编辑时不应带进输入框。
    var end = currentEnd;
    while (end > start && markdown.codeUnitAt(end - 1) == 0x0A) {
      end--;
    }
    if (end > start) ranges.add((start: start, end: end));
    currentStart = null;
  }

  for (final line in markdown.split('\n')) {
    final lineEnd = lineStart + line.length;
    if (_isFenceLine(line)) {
      // 围栏边界属于当前块；进入/离开代码块都不切块。
      inFence = !inFence;
      currentStart ??= lineStart;
      currentEnd = lineEnd;
      lineStart = lineEnd + 1;
      continue;
    }
    if (inFence) {
      currentStart ??= lineStart;
      currentEnd = lineEnd;
      lineStart = lineEnd + 1;
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      lineStart = lineEnd + 1;
      continue;
    }
    currentStart ??= lineStart;
    currentEnd = lineEnd;
    if (_headingPattern.hasMatch(line)) {
      flush();
    }
    lineStart = lineEnd + 1;
  }
  flush();
  return ranges;
}

/// 按块切分整篇 Markdown（保留首尾空白时用 [MarkdownSourceMap]）。
List<MarkdownBlock> splitMarkdownBlocks(String markdown) =>
    MarkdownSourceMap.parse(markdown).blocks;

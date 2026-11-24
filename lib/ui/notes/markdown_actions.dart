import 'package:flutter/widgets.dart';

/// Markdown 工具条的纯文本编辑操作。
///
/// 从编辑器 State 中抽出来，便于源码模式与实时预览的「段落编辑」共用，
/// 也便于用单元测试覆盖光标/选区行为。
class MarkdownActions {
  const MarkdownActions._();

  /// 用 [prefix] + 选中文本（或占位词）+ [suffix] 包裹当前选区。
  static void wrapInline(
    TextEditingController controller,
    String prefix,
    String suffix, {
    String placeholder = '',
  }) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final body = selected.isEmpty ? placeholder : selected;
    final newText = text.replaceRange(start, end, '$prefix$body$suffix');
    final int cursor;
    int selectionStart = -1;
    int selectionEnd = -1;
    if (selected.isEmpty && placeholder.isNotEmpty) {
      selectionStart = start + prefix.length;
      selectionEnd = selectionStart + placeholder.length;
      cursor = selectionEnd;
    } else {
      cursor = start + prefix.length + body.length + suffix.length;
    }
    controller.value = TextEditingValue(
      text: newText,
      selection:
          selectionStart >= 0
              ? TextSelection(
                baseOffset: selectionStart,
                extentOffset: selectionEnd,
              )
              : TextSelection.collapsed(offset: cursor),
    );
  }

  /// 在当前行行首切换 [prefix]（已有则移除）。
  ///
  /// 选中多行时**逐行**处理：
  /// - 选区内所有非空行都已有前缀 → 整体移除，否则只给缺前缀的行补上
  ///   （不会对已有前缀的行「先删再加」，避免选区被反复折损）；
  /// - 空行跳过，避免产生空的列表项 / 空标题；
  /// - 多行选区改写后重新覆盖「被改写的整行」，方向保持不变，连点多个工具按钮
  ///   不会让选区逐次缩水。
  static void toggleLinePrefix(
    TextEditingController controller,
    String prefix,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final selStart = selection.isValid ? selection.start : text.length;
    final selEnd = selection.isValid ? selection.end : text.length;
    final collapsed = selection.isValid && selection.isCollapsed;

    final lineAtStart = _lineAt(text, selStart);
    // 选区末端落在下一行行首时，那一行并没有被选中。
    final lastOffset = collapsed || selEnd == 0 ? selEnd : selEnd - 1;
    final lineAtEnd = _lineAt(text, lastOffset);
    final lines = _linesBetween(text, lineAtStart.start, lineAtEnd.end);

    final editable = lines.where((line) => !line.isBlank).toList();
    if (editable.isEmpty) return; // 只选中了空行：保持原样。
    final removePrefix = editable.every((line) => line.text.startsWith(prefix));

    // 逐行改写，同时记录每行在**新文本**里的起点。
    final buffer = StringBuffer();
    final newLineStarts = <int, int>{};
    final newLineLengths = <int, int>{};
    var cursor = 0;
    for (final line in lines) {
      if (line.start > cursor) buffer.write(text.substring(cursor, line.start));
      newLineStarts[line.start] = buffer.length;
      final String rewritten;
      if (line.isBlank) {
        rewritten = line.text;
      } else if (removePrefix) {
        rewritten = line.text.startsWith(prefix)
            ? line.text.substring(prefix.length)
            : line.text;
      } else {
        rewritten = line.text.startsWith(prefix)
            ? line.text
            : '$prefix${line.text}';
      }
      newLineLengths[line.start] = rewritten.length;
      buffer.write(rewritten);
      cursor = line.end;
    }
    if (cursor < text.length) buffer.write(text.substring(cursor));
    final newText = buffer.toString();

    if (collapsed) {
      // 光标跟着前缀长度平移，仍落在原来那一行的同一相对位置。
      final line = lineAtStart;
      final newStart = newLineStarts[line.start] ?? line.start;
      final shift = (newLineLengths[line.start] ?? line.text.length) - line.text.length;
      final offset = (newStart + (selStart - line.start) + shift).clamp(
        newStart,
        newText.length,
      );
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: offset),
      );
      return;
    }

    // 多行选区：重新覆盖被改写的整行（首行行首 → 末行行尾）。
    final firstStart = newLineStarts[lines.first.start] ?? 0;
    final lastLine = lines.last;
    final newEnd =
        (newLineStarts[lastLine.start] ?? firstStart) +
        (newLineLengths[lastLine.start] ?? lastLine.text.length);
    final baseIsStart = selection.baseOffset <= selection.extentOffset;
    controller.value = TextEditingValue(
      text: newText,
      selection:
          baseIsStart
              ? TextSelection(baseOffset: firstStart, extentOffset: newEnd)
              : TextSelection(baseOffset: newEnd, extentOffset: firstStart),
    );
  }

  /// 插入三反引号代码块，光标置于块内末尾。
  static void insertCodeBlock(TextEditingController controller) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final selected = text.substring(start, end);
    final needsLeadingBreak = start > 0 && text[start - 1] != '\n';
    final insertion = '${needsLeadingBreak ? '\n' : ''}```\n$selected\n```\n';
    final newText = text.replaceRange(start, end, insertion);
    final offset = start + insertion.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, newText.length),
      ),
    );
  }

  /// [offset] 所在行的范围（`end` 不含换行符）。
  static _Line _lineAt(String text, int offset) {
    final clamped = offset.clamp(0, text.length);
    final previousBreak = text.lastIndexOf('\n', clamped == 0 ? 0 : clamped - 1);
    final start = previousBreak == -1 ? 0 : previousBreak + 1;
    final nextBreak = text.indexOf('\n', clamped);
    final end = nextBreak == -1 ? text.length : nextBreak;
    return _Line(start: start, end: end, text: text.substring(start, end));
  }

  /// `[from, to]` 覆盖到的所有行（按文档顺序）。
  static List<_Line> _linesBetween(String text, int from, int to) {
    final lines = <_Line>[];
    var offset = from;
    while (true) {
      final line = _lineAt(text, offset);
      lines.add(line);
      if (line.end >= to || line.end >= text.length) break;
      offset = line.end + 1;
    }
    return lines;
  }
}

/// 一行源码的范围（`end` 不含换行符）。
class _Line {
  const _Line({required this.start, required this.end, required this.text});

  final int start;
  final int end;
  final String text;

  /// 去掉首尾空白后为空的行：切换前缀时跳过。
  bool get isBlank => text.trim().isEmpty;
}

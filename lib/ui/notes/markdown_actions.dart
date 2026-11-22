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
  static void toggleLinePrefix(
    TextEditingController controller,
    String prefix,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.start : text.length;
    final previousBreak = text.lastIndexOf('\n', cursor == 0 ? 0 : cursor - 1);
    final lineStart = previousBreak == -1 ? 0 : previousBreak + 1;
    final nextBreak = text.indexOf('\n', cursor);
    final lineEnd = nextBreak == -1 ? text.length : nextBreak;
    final line = text.substring(lineStart, lineEnd);
    final newLine =
        line.startsWith(prefix)
            ? line.substring(prefix.length)
            : '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    final offset = (cursor + (newLine.length - line.length)).clamp(
      0,
      newText.length,
    );
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
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
}

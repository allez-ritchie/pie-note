/// 任务列表（`- [ ]` / `1. [x]`）的纯文本操作，供预览态直接勾选复选框使用。
///
/// 与 `flutter_markdown_plus` 的解析保持一致的判定：
/// - 列表标记后必须有空白，然后是 `[ ]` / `[x]` / `[X]`，再跟空白或行尾；
/// - 围栏代码块（``` / ~~~）中的内容**不算**任务项（渲染时也只是代码）。
///
/// 任务项在整篇 Markdown 中的顺序就是渲染顺序，因此可以用「第 N 个任务项」
/// 的索引在预览态反查源码位置。
class MarkdownTasks {
  const MarkdownTasks._();

  /// 任务项整行匹配：分组 1 是列表标记（含缩进），分组 2 是方括号内的字符。
  static final RegExp taskPattern = RegExp(
    r'^([ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+)\[([ xX])\](?=[ \t\r]|$)',
  );

  /// 围栏代码块的起始行。
  static bool _isFence(String line) {
    final trimmed = line.trimLeft();
    return trimmed.startsWith('```') || trimmed.startsWith('~~~');
  }

  /// 统计任务项数量，并返回每个任务项方括号内字符的源码偏移量。
  ///
  /// 偏移量递增，长度即任务项总数。
  static List<int> checkboxOffsets(String markdown) {
    if (!markdown.contains('[')) return const <int>[];
    final offsets = <int>[];
    var lineStart = 0;
    var inFence = false;
    for (final line in markdown.split('\n')) {
      if (_isFence(line)) {
        inFence = !inFence;
        lineStart += line.length + 1;
        continue;
      }
      if (!inFence) {
        final match = taskPattern.firstMatch(line);
        if (match != null) {
          // 偏移 = 行首偏移 + 列表标记长度 + 1（跳过左方括号）。
          offsets.add(lineStart + match.group(1)!.length + 1);
        }
      }
      lineStart += line.length + 1;
    }
    return offsets;
  }

  /// 任务项总数；渲染预览时用于把点击换算回源码顺序。
  static int count(String markdown) => checkboxOffsets(markdown).length;

  /// 切换第 [index] 个任务项的完成状态；越界返回 `null`。
  static String? toggle(String markdown, int index) {
    final offsets = checkboxOffsets(markdown);
    if (index < 0 || index >= offsets.length) return null;
    final offset = offsets[index];
    if (offset < 0 || offset >= markdown.length) return null;
    final next = markdown[offset] == ' ' ? 'x' : ' ';
    return markdown.replaceRange(offset, offset + 1, next);
  }
}

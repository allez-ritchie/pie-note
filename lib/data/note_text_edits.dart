/// 笔记「标题 / 正文」之间的纯文本编辑操作。
///
/// 后端把标题与正文分开存（`title` + `content`），但很多笔记习惯把标题
/// 写成正文第一行的 `# 标题`。重命名时若只改 `title`，正文首行会与标题
/// 打架，因此在满足条件时**同时**改写正文首行；不满足条件则只改 `title`。
class NoteTextEdits {
  const NoteTextEdits._();

  /// 正文首行是否「就是标题行」（`# 标题` 形式的 ATX 标题）。
  ///
  /// 仅在首行是 1~6 级标题、且没有额外内容时返回 true；这样重命名只动
  /// 已经存在的标题行，不会凭空往正文里塞标题。
  static bool hasHeadingFirstLine(String content) =>
      _firstLineHeading(content) != null;

  /// 把正文首行的 `# 标题` 改写成 [title]；没有标题行时原样返回。
  ///
  /// 保留原来的 `#` 级数与行尾换行，其余内容逐字节不变（不重排空行，
  /// 与 `MarkdownSourceMap` 的可逆约定一致）。
  static String renameFirstHeading(String content, String title) {
    final heading = _firstLineHeading(content);
    if (heading == null) return content;
    final newlineIndex = content.indexOf('\n');
    final rest = newlineIndex < 0 ? '' : content.substring(newlineIndex);
    final hashes = content.substring(0, heading.hashLength);
    return '$hashes $title$rest';
  }

  /// 解析首行标题，返回 `#` 的数量；首行不是唯一标题时返回 null。
  static ({int hashLength})? _firstLineHeading(String content) {
    if (content.isEmpty) return null;
    final newlineIndex = content.indexOf('\n');
    final firstLine =
        (newlineIndex < 0 ? content : content.substring(0, newlineIndex)).trimRight();
    if (firstLine.isEmpty) return null;
    final match = RegExp(r'^(#{1,6})[ \t]+(\S.*)$').firstMatch(firstLine);
    if (match == null) return null;
    // 首行必须正好是「# 标题」，尾部不允许再跟别的块（避免误改正文）。
    return (hashLength: match.group(1)!.length);
  }

  /// 从 Markdown 正文推导一个可用的标题（正文首行 / 首个标题行）。
  ///
  /// 用于「正文有内容但 `title` 为空」时给重命名对话框一个合理的初始值。
  static String suggestedTitle(String content) {
    for (final rawLine in content.split('\n')) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      final heading = RegExp(r'^#{1,6}[ \t]+(.*)$').firstMatch(line);
      if (heading != null) line = heading.group(1)!.trim();
      if (line.isEmpty) continue;
      return line;
    }
    return '';
  }
}

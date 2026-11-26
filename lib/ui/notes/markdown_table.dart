/// GFM 表格的源码模型：解析、序列化与行列编辑。
///
/// 实时预览里的表格不再是「一大段源码」，而是可点击编辑的网格（见
/// `markdown_table_view.dart`）。那套交互需要以「行 × 列」为单位改内容，
/// 因此这里把表格源码解析成不可变模型，并在每次改动后重新序列化回 Markdown。
///
/// 约定：
/// - 表格块是**整块** Markdown（首行表头、次行对齐分隔线、其余为数据行）；
/// - 单元格里的 `\|` 在解析时还原成 `|`，序列化时再转义回去；
/// - 对齐方式保留在分隔线里（`:---` / `:---:` / `---:`）；
/// - 不是合法表格时 [MarkdownTable.tryParse] 返回 null，调用方回退到普通渲染。
library;

/// 列对齐方式，对应分隔线里的冒号。
enum MarkdownTableAlign { none, left, center, right }

/// 一张 GFM 表格：表头 + 对齐方式 + 数据行，全部不可变。
class MarkdownTable {
  MarkdownTable({
    required List<String> header,
    required List<MarkdownTableAlign> alignments,
    required List<List<String>> rows,
  }) : header = List<String>.unmodifiable(header),
       alignments = List<MarkdownTableAlign>.unmodifiable(alignments),
       rows = List<List<String>>.unmodifiable(
         rows.map((row) => List<String>.unmodifiable(row)),
       );
  /// 表头单元格。
  final List<String> header;

  /// 每列的对齐方式（长度与 [header] 一致）。
  final List<MarkdownTableAlign> alignments;

  /// 数据行（不含表头）。
  final List<List<String>> rows;

  int get columnCount => header.length;

  /// 数据行数（不含表头）。
  int get bodyRowCount => rows.length;

  /// 含表头的总行数。行号 0 表示表头。
  int get totalRowCount => rows.length + 1;

  /// 取单元格文本；行号 0 是表头。越界返回空串。
  String cellAt(int row, int col) {
    if (col < 0 || col >= columnCount) return '';
    if (row == 0) return header[col];
    final index = row - 1;
    if (index < 0 || index >= rows.length) return '';
    final dataRow = rows[index];
    return col < dataRow.length ? dataRow[col] : '';
  }

  /// 改写一个单元格（行号 0 是表头）。
  MarkdownTable withCell(int row, int col, String text) {
    if (col < 0 || col >= columnCount) return this;
    if (row == 0) {
      if (header[col] == text) return this;
      final next = List<String>.of(header);
      next[col] = text;
      return MarkdownTable(header: next, alignments: alignments, rows: rows);
    }
    final index = row - 1;
    if (index < 0 || index >= rows.length) return this;
    if (rows[index][col] == text) return this;
    final next = List<List<String>>.of(rows);
    final nextRow = List<String>.of(next[index]);
    nextRow[col] = text;
    next[index] = nextRow;
    return MarkdownTable(header: header, alignments: alignments, rows: next);
  }

  /// 改一列的对齐方式。
  MarkdownTable withColumnAlign(int col, MarkdownTableAlign align) {
    if (col < 0 || col >= columnCount) return this;
    if (alignments[col] == align) return this;
    final next = List<MarkdownTableAlign>.of(alignments);
    next[col] = align;
    return MarkdownTable(header: header, alignments: next, rows: rows);
  }

  /// 在 [index] 处插入一列（0..columnCount），新增列为空单元格。
  MarkdownTable insertColumn(int index) {
    final at = index.clamp(0, columnCount);
    final nextHeader = List<String>.of(header)..insert(at, '');
    final nextAlign = List<MarkdownTableAlign>.of(alignments)
      ..insert(at, MarkdownTableAlign.none);
    final nextRows = [
      for (final row in rows) (List<String>.of(row)..insert(at, '')),
    ];
    return MarkdownTable(
      header: nextHeader,
      alignments: nextAlign,
      rows: nextRows,
    );
  }

  /// 删除 `[start, end]` 范围内的列；至少保留一列。
  MarkdownTable removeColumns(int start, int end) {
    final from = start.clamp(0, columnCount - 1);
    final to = end.clamp(from, columnCount - 1);
    if (columnCount - (to - from + 1) < 1) return this;
    final nextHeader = List<String>.of(header)..removeRange(from, to + 1);
    final nextAlign = List<MarkdownTableAlign>.of(alignments)
      ..removeRange(from, to + 1);
    final nextRows = [
      for (final row in rows) (List<String>.of(row)..removeRange(from, to + 1)),
    ];
    return MarkdownTable(
      header: nextHeader,
      alignments: nextAlign,
      rows: nextRows,
    );
  }

  /// 在数据行 [index]（0..bodyRowCount）处插入一个空行。
  MarkdownTable insertRow(int index) {
    final at = index.clamp(0, rows.length);
    final nextRows = List<List<String>>.of(rows)
      ..insert(at, List<String>.filled(columnCount, ''));
    return MarkdownTable(header: header, alignments: alignments, rows: nextRows);
  }

  /// 删除 `[start, end]` 范围的数据行。
  MarkdownTable removeRows(int start, int end) {
    if (rows.isEmpty) return this;
    final from = start.clamp(0, rows.length - 1);
    final to = end.clamp(from, rows.length - 1);
    final nextRows = List<List<String>>.of(rows)..removeRange(from, to + 1);
    return MarkdownTable(
      header: header,
      alignments: alignments,
      rows: nextRows,
    );
  }

  /// 序列化成 GFM 表格源码（不含首尾空行，末尾不带换行）。
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln(_formatRow(header));
    buffer.writeln(
      _formatRow([for (final align in alignments) _alignmentMarker(align)]),
    );
    for (final row in rows) {
      buffer.writeln(_formatRow(row));
    }
    final text = buffer.toString();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  static String _formatRow(List<String> cells) {
    final escaped = [for (final cell in cells) _escapeCell(cell)];
    return '| ${escaped.join(' | ')} |';
  }

  static String _alignmentMarker(MarkdownTableAlign align) {
    switch (align) {
      case MarkdownTableAlign.left:
        return ':---';
      case MarkdownTableAlign.center:
        return ':---:';
      case MarkdownTableAlign.right:
        return '---:';
      case MarkdownTableAlign.none:
        return '---';
    }
  }

  /// 单元格里的竖线必须转义，否则会被拆成两列。
  static String _escapeCell(String text) => text.replaceAll('|', r'\|');

  /// 解析一整块 Markdown；不是合法表格时返回 null。
  ///
  /// 只接受「整块都是表格」的文本：首行表头、次行对齐分隔线、其余为数据行。
  /// 行首尾的竖线可省略，单元格数量不足时补空、超出时截断（与 GFM 一致）。
  static MarkdownTable? tryParse(String markdown) {
    final lines = markdown
        .split('\n')
        .map((line) => line.trimRight())
        .toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.length < 2) return null;
    // 没有竖线的块不可能是表格（避免把「标题 + ---」这类 setext 标题当表格）。
    if (!lines[0].contains('|')) return null;
    if (lines.skip(2).any((line) => line.trim().isEmpty)) return null;

    final header = _splitRow(lines[0]);
    final delimiter = _splitRow(lines[1]);
    if (header == null || delimiter == null) return null;
    if (header.isEmpty || delimiter.length != header.length) return null;

    final alignments = <MarkdownTableAlign>[];
    for (final cell in delimiter) {
      final marker = cell.trim();
      if (!_delimiterPattern.hasMatch(marker)) return null;
      final left = marker.startsWith(':');
      final right = marker.endsWith(':');
      if (left && right) {
        alignments.add(MarkdownTableAlign.center);
      } else if (left) {
        alignments.add(MarkdownTableAlign.left);
      } else if (right) {
        alignments.add(MarkdownTableAlign.right);
      } else {
        alignments.add(MarkdownTableAlign.none);
      }
    }

    final rows = <List<String>>[];
    for (final line in lines.skip(2)) {
      final cells = _splitRow(line) ?? const <String>[];
      final normalized = List<String>.generate(
        header.length,
        (index) => index < cells.length ? cells[index] : '',
      );
      rows.add(normalized);
    }
    return MarkdownTable(header: header, alignments: alignments, rows: rows);
  }

  /// 对齐分隔线单元格：`---` / `:---` / `:---:` / `---:`。
  static final RegExp _delimiterPattern = RegExp(r'^:?-+:?$');

  /// 把一行拆成单元格；还原 `\|`，并跳过行内代码里的竖线。
  static List<String>? _splitRow(String line) {
    var text = line.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('|')) text = text.substring(1);
    final cells = <String>[];
    final buffer = StringBuffer();
    var inCode = false;
    var endedWithPipe = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == r'\' && i + 1 < text.length && text[i + 1] == '|') {
        buffer.write('|');
        i++;
        endedWithPipe = false;
        continue;
      }
      if (char == '`') {
        inCode = !inCode;
        buffer.write(char);
        endedWithPipe = false;
        continue;
      }
      if (char == '|' && !inCode) {
        cells.add(buffer.toString().trim());
        buffer.clear();
        endedWithPipe = true;
        continue;
      }
      buffer.write(char);
      endedWithPipe = false;
    }
    if (!endedWithPipe) cells.add(buffer.toString().trim());
    return cells;
  }
}

/// 复制 / 粘贴用的网格编解码：行用换行分隔、单元格用制表符分隔。
///
/// 与 Excel、飞书表格等应用一致，粘进来的表格数据可以直接落进选中区域。
class MarkdownTableClipboard {
  const MarkdownTableClipboard._();

  /// 把 `[行][列]` 的单元格文本编码成剪贴板文本。
  static String encode(List<List<String>> grid) {
    return [
      for (final row in grid)
        row
            .map((cell) => cell.replaceAll('\t', ' ').replaceAll('\n', ' '))
            .join('\t'),
    ].join('\n');
  }

  /// 把剪贴板文本解析成 `[行][列]`；空文本返回空列表。
  static List<List<String>> decode(String text) {
    if (text.isEmpty) return const [];
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    // 末尾换行是复制时的常见产物，去掉可以避免多粘一行空行。
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return [
      for (final line in lines) line.split('\t'),
    ];
  }
}

/// 一段 Markdown：[text] 是源码片段；[table] 非空表示这段是一张表。
class MarkdownTableSegment {
  const MarkdownTableSegment({
    required this.text,
    required this.tableStart,
    required this.taskOffset,
    this.table,
  });

  /// 该片段的源码（拼接所有片段即可还原原文）。
  final String text;

  /// 片段在整篇源码里的起始偏移（[table] 非空时是表格块起点）。
  final int tableStart;

  /// 片段之前已有的任务项数量（渲染阶段换算全篇复选框序号用）。
  final int taskOffset;

  /// 解析好的表格；为 null 表示这是普通 Markdown 片段。
  final MarkdownTable? table;

  bool get isTable => table != null;
}

/// 把一段 Markdown 按「表格块 / 非表格块」切开，保持原文可拼接还原。
///
/// 只在**空行分隔的块边界**上判断表格，围栏代码块里出现的竖线不会被误判。
List<MarkdownTableSegment> splitMarkdownTables(String markdown) {
  if (markdown.trim().isEmpty) return const [];
  final segments = <MarkdownTableSegment>[];
  var taskOffset = 0;
  var plainStart = 0;

  void flushPlain(int end) {
    if (end <= plainStart) return;
    final text = markdown.substring(plainStart, end);
    if (text.trim().isEmpty) return;
    segments.add(
      MarkdownTableSegment(
        text: text,
        tableStart: plainStart,
        taskOffset: taskOffset,
      ),
    );
    taskOffset += countMarkdownTasks(text);
  }

  for (final block in _scanBlocks(markdown)) {
    final text = markdown.substring(block.start, block.end);
    if (MarkdownTable.tryParse(text) == null) continue;
    flushPlain(block.start);
    segments.add(
      MarkdownTableSegment(
        text: text,
        tableStart: block.start,
        taskOffset: taskOffset,
        table: MarkdownTable.tryParse(text),
      ),
    );
    plainStart = block.end;
  }
  flushPlain(markdown.length);
  return segments;
}

/// 任务项数量：`- [ ] xxx` / `1. [x] xxx`，跳过围栏代码块。
int countMarkdownTasks(String markdown) {
  var count = 0;
  var inFence = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    if (_taskPattern.hasMatch(line)) count++;
  }
  return count;
}

final RegExp _taskPattern = RegExp(r'^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+\[[ xX]\]');

/// 扫描块边界：空行分隔块，围栏代码块内部的空行不切。
List<({int start, int end})> _scanBlocks(String markdown) {
  final blocks = <({int start, int end})>[];
  var start = -1;
  var end = 0;
  var lineStart = 0;
  var inFence = false;

  void flush() {
    if (start >= 0) blocks.add((start: start, end: end));
    start = -1;
  }

  for (final line in markdown.split('\n')) {
    final lineEnd = lineStart + line.length;
    final trimmed = line.trimLeft();
    final fence = trimmed.startsWith('```') || trimmed.startsWith('~~~');
    if (fence) inFence = !inFence;
    if (!inFence && line.trim().isEmpty) {
      flush();
      lineStart = lineEnd + 1;
      continue;
    }
    if (start < 0) start = lineStart;
    end = lineEnd;
    lineStart = lineEnd + 1;
  }
  flush();
  return blocks;
}

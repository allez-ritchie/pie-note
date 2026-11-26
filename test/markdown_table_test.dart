import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_table.dart';

void main() {
  const source = '| 分组 | 引脚 |\n| --- | --- |\n| 5V | 2、3 |\n| GND | 1、4 |';

  test('解析表头/对齐/数据行，并能原样序列化', () {
    final table = MarkdownTable.tryParse(source)!;
    expect(table.columnCount, 2);
    expect(table.bodyRowCount, 2);
    expect(table.cellAt(0, 0), '分组');
    expect(table.cellAt(2, 1), '1、4');
    expect(table.toMarkdown(), source);
  });

  test('对齐分隔线保留为对齐方式', () {
    final table = MarkdownTable.tryParse(
      '| a | b | c |\n| :--- | :---: | ---: |\n| 1 | 2 | 3 |',
    )!;
    expect(table.alignments, [
      MarkdownTableAlign.left,
      MarkdownTableAlign.center,
      MarkdownTableAlign.right,
    ]);
    expect(table.toMarkdown(), contains('| :--- | :---: | ---: |'));
  });

  test('单元格里的竖线与行内代码竖线不被拆列', () {
    final table = MarkdownTable.tryParse(
      r'| a | b |' '\n' r'| --- | --- |' '\n' r'| x\|y | `1\|2` |',
    )!;
    expect(table.cellAt(1, 0), 'x|y');
    expect(table.toMarkdown(), contains(r'x\|y'));
  });

  test('新增列 / 行与删除列 / 行', () {
    final table = MarkdownTable.tryParse(source)!;
    final withColumn = table.insertColumn(2);
    expect(withColumn.columnCount, 3);
    expect(withColumn.cellAt(1, 2), '');
    expect(withColumn.toMarkdown().split('\n').first, '| 分组 | 引脚 |  |');

    // insertRow 的下标是「数据行下标」：1 表示插在第二行 5V 之后。
    final withRow = table.insertRow(1);
    expect(withRow.bodyRowCount, 3);
    expect(withRow.cellAt(1, 0), '5V');
    expect(withRow.cellAt(2, 0), '');
    expect(withRow.cellAt(3, 0), 'GND');

    expect(table.removeColumns(0, 0).columnCount, 1);
    expect(table.removeColumns(0, 0).removeColumns(0, 0).columnCount, 1);
    expect(table.removeRows(0, 1).bodyRowCount, 0);
  });

  test('非表格块解析为 null', () {
    expect(MarkdownTable.tryParse('# 标题'), isNull);
    expect(MarkdownTable.tryParse('普通段落\n\n第二段'), isNull);
    expect(MarkdownTable.tryParse('| a | b |'), isNull);
    expect(MarkdownTable.tryParse('| a | b |\n| --- |'), isNull);
    expect(MarkdownTable.tryParse('| a | b |\n| --- | --- |\n\n| c |'), isNull);
  });

  test('剪贴板网格编解码', () {
    const text = 'a\tb\nc\td\n';
    expect(MarkdownTableClipboard.decode(text), [
      ['a', 'b'],
      ['c', 'd'],
    ]);
    expect(MarkdownTableClipboard.encode([['a', 'b'], ['c\nd', 'e']]), 'a\tb\nc d\te');
    expect(MarkdownTableClipboard.decode(''), isEmpty);
  });
}

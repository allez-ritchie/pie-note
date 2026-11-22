import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_blocks.dart';
import 'package:pie_note/ui/notes/markdown_tasks.dart';

void main() {
  group('MarkdownTasks.checkboxOffsets', () {
    test('识别无序 / 有序 / 缩进任务项，忽略非任务列表', () {
      const markdown = '''
- [ ] 未完成 A
- [x] 已完成 B
  - [X] 嵌套已完成 C
1. [ ] 有序未完成 D
- 普通列表项
- [ ]收尾无空格的任务不算
''';
      // 最后一行 `[ ]收尾` 缺空白，渲染时不会变成复选框，这里也不计。
      final offsets = MarkdownTasks.checkboxOffsets(markdown);
      expect(offsets, hasLength(4));
      // 偏移量严格递增，且每个偏移都指向方括号内的字符。
      for (var i = 0; i < offsets.length; i++) {
        expect(' xX'.contains(markdown[offsets[i]]), isTrue);
        if (i > 0) expect(offsets[i], greaterThan(offsets[i - 1]));
      }

      final toggled = MarkdownTasks.toggle(markdown, 0)!;
      expect(toggled, contains('- [x] 未完成 A'));
      expect(MarkdownTasks.toggle(toggled, 0), markdown);
    });

    test('围栏代码块里的任务语法不算任务项', () {
      const markdown = '''
- [ ] 真任务

```md
- [ ] 代码里的假任务
```

~~~
- [x] 另一个假任务
~~~
''';
      expect(MarkdownTasks.count(markdown), 1);
      final toggled = MarkdownTasks.toggle(markdown, 0)!;
      expect(toggled, contains('- [x] 真任务'));
      expect(toggled, contains('- [ ] 代码里的假任务'));
      expect(MarkdownTasks.toggle(toggled, 1), isNull);
    });

    test('空内容与无任务内容返回空', () {
      expect(MarkdownTasks.checkboxOffsets(''), isEmpty);
      expect(MarkdownTasks.checkboxOffsets('# 标题\n\n正文'), isEmpty);
      expect(MarkdownTasks.toggle('正文', 0), isNull);
    });
  });

  group('MarkdownSourceMap', () {
    test('分块后 join 能逐字节还原原文', () {
      const markdown =
          '\n\n# 标题\n正文第一段\n\n- [ ] 任务\n- [x] 完成\n\n\n'
          '```dart\nvoid main() {\n\n  print(1);\n}\n```\n\n尾段\n\n';
      final map = MarkdownSourceMap.parse(markdown);
      expect(map.segments, isNotEmpty);
      expect(map.join(), markdown);
    });

    test('标题 / 空行 / 围栏代码块的分块边界', () {
      const markdown =
          '# 标题\n## 二级标题\n\n'
          '正文一行\n正文两行\n\n'
          '```dart\ncode line\n\ncode after blank\n```\n';
      final blocks = splitMarkdownBlocks(markdown);

      expect(blocks.map((block) => block.text), [
        '# 标题',
        '## 二级标题',
        '正文一行\n正文两行',
        '```dart\ncode line\n\ncode after blank\n```',
      ]);
      // 每个块的偏移量与源码切片一致。
      for (final block in blocks) {
        expect(markdown.substring(block.start, block.end), block.text);
      }
    });

    test('块内任务项序号按全篇顺序累加', () {
      const markdown = '- [ ] A\n- [ ] B\n\n正文\n\n- [x] C\n';
      final blocks = splitMarkdownBlocks(markdown);
      expect(blocks.map((block) => block.taskOffset), [0, 2, 2]);
    });

    test('replaceText 只改目标块，其余空白原样保留', () {
      const markdown = '第一段\n\n第二段\n\n\n第三段\n';
      final map = MarkdownSourceMap.parse(markdown);
      final next = map.replaceText(1, '新的第二段');
      expect(next.join(), '第一段\n\n新的第二段\n\n\n第三段\n');
      expect(next.startOf(1), 5);
    });

    test('未闭合围栏与全空白内容都能容忍', () {
      const unclosed = '正文\n\n```\n- [ ] 还在代码里\n';
      final blocks = splitMarkdownBlocks(unclosed);
      expect(blocks.map((block) => block.text), ['正文', '```\n- [ ] 还在代码里']);
      expect(blocks.last.taskOffset, 0);
      expect(MarkdownTasks.count(blocks.last.text), 0);

      expect(splitMarkdownBlocks(''), isEmpty);
      expect(splitMarkdownBlocks('  \n\n\t\n'), isEmpty);
      expect(MarkdownSourceMap.parse('').join(), '');
    });
  });
}

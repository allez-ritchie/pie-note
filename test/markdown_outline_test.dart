import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/markdown_outline.dart';

void main() {
  group('parseMarkdownHeadings', () {
    test('识别各级标题并给出可定位的源码偏移量', () {
      const markdown = '# 一级标题\n正文\n\n## 二级标题\n\n###### 六级\n';
      final headings = parseMarkdownHeadings(markdown);

      expect(headings.map((h) => h.level), [1, 2, 6]);
      expect(headings.map((h) => h.text), ['一级标题', '二级标题', '六级']);
      // 偏移量能切回原文，正文起点指向标题文字（`#` 之后）。
      for (final heading in headings) {
        expect(markdown.substring(heading.offset, heading.end), heading.raw);
        expect(
          markdown.substring(heading.textStart).startsWith(heading.text.isEmpty ? '' : heading.text),
          isTrue,
        );
      }
      expect(headings.first.textStart, 2);
      expect(headings[1].offset, markdown.indexOf('## 二级标题'));
    });

    test('跳过围栏代码块里的 #，未闭合围栏吞掉剩余内容', () {
      const markdown = '''
# 真标题

```md
# 代码里的假标题
```

~~~
## 仍在代码块里
~~~

## 真二级标题
''';
      final headings = parseMarkdownHeadings(markdown);
      expect(headings.map((h) => h.text), ['真标题', '真二级标题']);
    });

    test('`#标题` 不带空格不算标题，缩进超过 3 空格也不算', () {
      const markdown = '#标题\n\n   ## 缩进三格算\n\n    # 缩进四格是代码块\n';
      expect(
        parseMarkdownHeadings(markdown).map((h) => h.text),
        ['缩进三格算'],
      );
    });

    test('去掉收尾 # 序列与展示用的行内标记', () {
      const markdown =
          '## 标题二 ##\n\n# **加粗**与`代码`\n\n### 带 [链接](http://a) 与 [[双链]]\n';
      final headings = parseMarkdownHeadings(markdown);
      expect(headings.map((h) => h.text), ['标题二', '加粗与代码', '带 链接 与 双链']);
    });

    test('空内容与无标题内容返回空列表', () {
      expect(parseMarkdownHeadings(''), isEmpty);
      expect(parseMarkdownHeadings('  \n\n'), isEmpty);
      expect(parseMarkdownHeadings('正文\n\n- 列表\n'), isEmpty);
    });
  });

  group('activeHeadingIndex', () {
    test('返回光标之前最后一个标题；第一个标题之前为 -1', () {
      const markdown = '前言\n\n# A\n\n正文\n\n## B\n\n正文\n';
      final headings = parseMarkdownHeadings(markdown);
      final a = markdown.indexOf('# A');
      final b = markdown.indexOf('## B');

      expect(activeHeadingIndex(headings, null), -1);
      expect(activeHeadingIndex(headings, 0), -1);
      expect(activeHeadingIndex(headings, a - 1), -1);
      expect(activeHeadingIndex(headings, a), 0);
      expect(activeHeadingIndex(headings, b - 1), 0);
      expect(activeHeadingIndex(headings, b), 1);
      expect(activeHeadingIndex(headings, markdown.length), 1);
      expect(activeHeadingIndex(const <MarkdownHeading>[], 10), -1);
    });
  });

  group('splitMarkdownSections', () {
    test('按标题分节，节内保持原文（列表/代码块不被切开）', () {
      const markdown = '''
前言

# 第一节

正文 A

## 第二节

- [ ] 任务
- [x] 完成

```dart
# 代码里的假标题
```
''';
      final sections = splitMarkdownSections(markdown);
      expect(sections, hasLength(3));
      expect(sections.map((s) => s.start), [
        0,
        markdown.indexOf('# 第一节'),
        markdown.indexOf('## 第二节'),
      ]);
      expect(sections[1].markdown, startsWith('# 第一节'));
      expect(sections[2].markdown, contains('```dart'));
      expect(sections[2].markdown, contains('# 代码里的假标题'));
      // 任务序号：第二节里的两个任务项之前的数量。
      expect(sections.map((s) => s.taskOffset), [0, 0, 0]);
    });

    test('没有标题时整篇是一节；空内容没有节', () {
      final sections = splitMarkdownSections('正文一\n\n正文二\n');
      expect(sections, hasLength(1));
      expect(sections.single.markdown, '正文一\n\n正文二');
      expect(splitMarkdownSections('   \n'), isEmpty);
    });

    test('每节内容由原有块拼接，不吞掉块间空白以外的内容', () {
      const markdown = '# A\n\n段落\n\n# B\n\n```md\ncode\n```\n\n尾巴\n';
      for (final section in splitMarkdownSections(markdown)) {
        expect(markdown.substring(section.start, section.end), section.markdown);
      }
    });
  });

  group('stripMarkdownInline', () {
    test('去掉链接/图片/双链/行内代码与强调标记', () {
      // 图片保留 alt 文本、丢弃路径（本仓库不渲染图片）。
      expect(stripMarkdownInline('![图](a.png) 标题'), '图 标题');
      expect(stripMarkdownInline('**粗** *斜* ~~删~~'), '粗 斜 删');
      expect(stripMarkdownInline(r'\# 转义'), '# 转义');
      expect(stripMarkdownInline('无标记'), '无标记');
    });
  });

  group('headingHasChildren / collapsibleHeadingIndexes', () {
    test('只有紧跟更深标题的项才算有子项', () {
      const markdown = '# A\n\n### A1\n\n## B\n\n## C\n\n### C1\n';
      final headings = parseMarkdownHeadings(markdown);
      expect(headings.map((h) => h.text), ['A', 'A1', 'B', 'C', 'C1']);

      expect(headingHasChildren(headings, 0), isTrue); // A → A1
      expect(headingHasChildren(headings, 1), isFalse); // A1 后面是更浅的 B
      expect(headingHasChildren(headings, 2), isFalse); // B 后面是同级 C
      expect(headingHasChildren(headings, 3), isTrue); // C → C1
      expect(headingHasChildren(headings, 4), isFalse);
      expect(headingHasChildren(headings, -1), isFalse);
      expect(headingHasChildren(headings, 99), isFalse);

      expect(collapsibleHeadingIndexes(headings), {0, 3});
      expect(collapsibleHeadingIndexes(const <MarkdownHeading>[]), isEmpty);
    });
  });

  group('visibleOutlineHeadings', () {
    const markdown = '''
# A

## A1

### A1a

## A2

# B

## B1
''';

    test('未折叠时全部可见', () {
      final headings = parseMarkdownHeadings(markdown);
      expect(visibleOutlineHeadings(headings, <int>{}), everyElement(isTrue));
    });

    test('折叠父标题只隐藏其子孙，兄弟标题仍可见', () {
      final headings = parseMarkdownHeadings(markdown);
      // 索引：0=A 1=A1 2=A1a 3=A2 4=B 5=B1
      expect(
        visibleOutlineHeadings(headings, {0}),
        [true, false, false, false, true, true],
      );
      // 折叠 A1 只藏 A1a，A2 是 A1 的兄弟，仍然可见。
      expect(
        visibleOutlineHeadings(headings, {1}),
        [true, true, false, true, true, true],
      );
      // 祖先折叠时，即使自己没被折叠也不可见（嵌套折叠不叠加）。
      expect(
        visibleOutlineHeadings(headings, {0, 1}),
        [true, false, false, false, true, true],
      );
    });

    test('空列表返回空', () {
      expect(visibleOutlineHeadings(const <MarkdownHeading>[], {0}), isEmpty);
    });
  });
}

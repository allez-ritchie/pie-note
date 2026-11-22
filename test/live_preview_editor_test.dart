import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/live_preview_editor.dart';

Widget _wrap({required TextEditingController controller, ValueChanged<int>? onToggleTask}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: LivePreviewEditor(
          controller: controller,
          onToggleTask: onToggleTask,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('渲染态不显示 Markdown 标记，点按段落后就地展开源码', (tester) async {
    final controller = TextEditingController(
      text: '# 标题\n\n正文**加粗**内容\n\n- 列表项\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    // 渲染态：标题不带 `#`，加粗不带 `**`。
    expect(find.text('标题'), findsOneWidget);
    expect(find.textContaining('**加粗**'), findsNothing);
    expect(find.textContaining('# 标题'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    // 点按标题段落 → 只有该段展开为源码输入框。
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(EditorStrings.liveEditingBlock), findsOneWidget);

    // 就地改写标题，失焦后写回整篇正文，其余段落保持不变。
    await tester.enterText(find.byType(TextField), '## 新标题');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(controller.text, '## 新标题\n\n正文**加粗**内容\n\n- 列表项\n');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('编辑某段时保持其他段落的源码空白不变', (tester) async {
    const original = '第一段\n\n\n第二段\n\n第三段';
    final controller = TextEditingController(text: original);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二段'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第二段（改）');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(controller.text, '第一段\n\n\n第二段（改）\n\n第三段');
  });

  testWidgets('渲染态点击任务复选框直接勾选整篇正文', (tester) async {
    final toggles = <int>[];
    final controller = TextEditingController(
      text: '- [ ] 任务 A\n- [x] 任务 B\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(controller: controller, onToggleTask: toggles.add),
    );
    await tester.pumpAndSettle();

    expect(find.text('任务 A'), findsOneWidget);
    final boxes = find.byIcon(Icons.check_box_outline_blank_rounded);
    expect(boxes, findsOneWidget);
    expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);

    await tester.tap(boxes);
    await tester.pumpAndSettle();

    // 第 0 个复选框被点击；上层据此改写源码（这里由测试记录序号）。
    expect(toggles, [0]);
  });

  testWidgets('当前段落展开时点击别处复选框，勾选结果不会丢失', (tester) async {
    final controller = TextEditingController(
      text: '- [ ] 任务 A\n\n正文段落\n\n- [ ] 任务 C\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        controller: controller,
        onToggleTask: (index) {
          // 模拟上层用 MarkdownTasks.toggle 改写正文。
          final text = controller.text;
          final offset = _taskCharOffset(text, index);
          controller.value = TextEditingValue(
            text: text.replaceRange(offset, offset + 1, 'x'),
            selection: controller.selection,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    // 先展开正文段落。
    await tester.tap(find.text('正文段落'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 再勾选第 2 个复选框（任务 C）。
    final boxes = find.byIcon(Icons.check_box_outline_blank_rounded);
    expect(boxes, findsNWidgets(2));
    await tester.tap(boxes.last);
    await tester.pumpAndSettle();

    // 只勾选了任务 C；任务 A 保持未完成，正文段落仍处于展开编辑态。
    expect(controller.text, contains('- [ ] 任务 A'));
    expect(controller.text, contains('- [x] 任务 C'));
    expect(find.textContaining('正文段落'), findsWidgets);
  });
}

/// 测试内联版「第 N 个任务项方括号内字符」偏移（与 MarkdownTasks 同语义）。
int _taskCharOffset(String markdown, int index) {
  final pattern = RegExp(r'^([ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]+)\[([ xX])\]');
  var seen = 0;
  var lineStart = 0;
  for (final line in markdown.split('\n')) {
    final match = pattern.firstMatch(line);
    if (match != null) {
      if (seen == index) return lineStart + match.group(1)!.length + 1;
      seen++;
    }
    lineStart += line.length + 1;
  }
  throw ArgumentError('index $index 越界');
}

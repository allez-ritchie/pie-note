import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

    // 点按标题段落 → 只有该段就地变成源码输入框：无边框、无「完成」按钮。
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '# 标题');
    expect(field.minLines, 1);
    expect(field.decoration!.filled, isFalse);
    expect(field.decoration!.border, InputBorder.none);
    expect(field.decoration!.enabledBorder, InputBorder.none);
    expect(field.decoration!.focusedBorder, InputBorder.none);
    expect(find.byType(TextButton), findsNothing);
    // 渲染态的标题已被源码替换，下面的段落仍然渲染。
    expect(find.text('标题'), findsNothing);
    expect(find.textContaining('正文加粗内容'), findsOneWidget);

    // 就地改写标题，失焦后写回整篇正文，其余段落保持不变。
    await tester.enterText(find.byType(TextField), '## 新标题');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(controller.text, '## 新标题\n\n正文**加粗**内容\n\n- 列表项\n');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('展开一段后点按另一段，直接切换且不残留旧编辑框', (tester) async {
    final controller = TextEditingController(text: '# 标题\n\n正文段落\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '# 标题',
    );

    // 点按另一段：新的段落就地展开，旧段落回到渲染态。
    await tester.tap(find.text('正文段落'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '正文段落',
    );
    expect(find.text('标题'), findsOneWidget);
    expect(find.textContaining('# 标题'), findsNothing);
  });

  testWidgets('改长一段后点下一段，展开的仍是点击的那一段', (tester) async {
    final controller = TextEditingController(
      text: '第一段\n\n第二段\n\n第三段\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    // 把第一段改长（偏移量整体后移），再点第三段。
    await tester.tap(find.text('第一段'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一段（变长了很多很多字）');
    await tester.pumpAndSettle();

    await tester.tap(find.text('第三段'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '第三段',
    );
    expect(controller.text, '第一段（变长了很多很多字）\n\n第二段\n\n第三段\n');
  });

  testWidgets('点按正文下方空白处收起源码态', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.reset);

    final controller = TextEditingController(text: '唯一一段\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('唯一一段'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 点正文下方的大片空白（避开底部工具条）。
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('唯一一段'), findsOneWidget);
    expect(controller.text, '唯一一段\n');
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

  testWidgets('段首退格：删掉空行接上上一段，光标落在上一行末尾并展开源码', (tester) async {
    final controller = TextEditingController(text: '第一段\n\n第二段\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第二段'));
    await tester.pumpAndSettle();
    final block = tester.widget<TextField>(find.byType(TextField)).controller!;
    // 模拟连续退格删到行首：光标在本段源码开头。
    block.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    // 空行被删掉，两段合成一段；输入框里是整段源码，光标落在上一行行尾。
    expect(controller.text, '第一段\n第二段\n');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '第一段\n第二段');
    expect(field.controller!.selection.baseOffset, 3);

    // 再按一次退格：能删掉上一行的最后一个字（修复前这里删不动）。
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.text, '第一\n第二段\n');
  });

  testWidgets('段首退格：上一段是标题时光标落到标题末尾并展开标题源码', (tester) async {
    final controller = TextEditingController(text: '# 标题\n\n正文段落\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('正文段落'));
    await tester.pumpAndSettle();
    tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    // 空行被删掉；上一段（标题）整段展开成源码，光标在标题末尾。
    expect(controller.text, '# 标题\n正文段落\n');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '# 标题');
    expect(field.controller!.selection.baseOffset, 4);
  });

  testWidgets('正文第一段段首退格不改动正文', (tester) async {
    final controller = TextEditingController(text: '第一段\n\n第二段\n');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第一段'));
    await tester.pumpAndSettle();
    tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, '第一段\n\n第二段\n');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '第一段',
    );
  });

  testWidgets('把一段删空后仍然可以继续退格接上上一段（焦点不丢）', (tester) async {
    final controller = TextEditingController(text: 'AAAA\n\nBBBB');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('BBBB'));
    await tester.pumpAndSettle();
    // 连续退格把整段删空：空段不在分块结果里，但输入框必须留着，
    // 否则焦点随块一起消失，后面的退格就删不动上一行（Android 上必现）。
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(controller.text, 'AAAA\n\n');
    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(controller.text, 'AAAA\n');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'AAAA');
    expect(field.controller!.selection.baseOffset, 4);
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

  // ---------------------------------------------------------------------------
  // 桌面端跨段落拖选：鼠标按住左键向上/向下拖出就地输入框时，
  // 选区要覆盖整段 Markdown 源码，而不是只剩「点击的那一行」。
  // ---------------------------------------------------------------------------

  testWidgets('鼠标向上拖出输入框：选区跨段落覆盖整段源码', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(
      text: '第一段\n\n第二段\n\n第三段',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();
    // 点开最后一段，再从它末尾按住左键向上拖到第一段上方。
    await tester.tap(find.text('第三段'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField));
    await _mouseDrag(
      tester,
      from: Offset(rect.left + 60, rect.bottom - 8),
      to: Offset(rect.left + 40, rect.top - 60),
      steps: 20,
    );

    // 输入框里现在是并起来的多段源码，选区从第一段中间到第三段末尾。
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '第一段\n\n第二段\n\n第三段');
    final selection = field.controller!.selection;
    expect(selection.isValid, isTrue);
    expect(selection.isCollapsed, isFalse);
    final selected = field.controller!.text.substring(
      selection.start,
      selection.end,
    );
    // 跨过段间空行、覆盖到第二段（修复前只能选中点击的那一段）。
    expect(selected, contains('第二段'));
    expect(selected, isNot(selected.trim()));

    // 跨段源码虽然进了同一个输入框，整篇正文不会被重复写入。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(controller.text, '第一段\n\n第二段\n\n第三段');
  });

  testWidgets('鼠标向下拖出输入框：选区跨段落覆盖整段源码', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(
      text: '第一段\n\n第二段\n\n第三段',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第一段'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField));
    await _mouseDrag(
      tester,
      from: Offset(rect.left + 20, rect.top + 6),
      to: Offset(rect.left + 60, rect.bottom + 80),
      steps: 20,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '第一段\n\n第二段\n\n第三段');
    final selection = field.controller!.selection;
    expect(selection.isCollapsed, isFalse);
    expect(
      field.controller!.text.substring(selection.start, selection.end),
      contains('第二段'),
    );
  });

  testWidgets('连续拖过多段时合并范围只增不减', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(
      text: '第一段\n\n第二段\n\n第三段\n\n第四段',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第四段'));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.text('第一段'));
    final rect = tester.getRect(find.byType(TextField));
    await _mouseDrag(
      tester,
      from: Offset(rect.left + 40, rect.bottom - 6),
      to: Offset(first.left + 10, first.top - 4),
      steps: 40,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    // 四段全部并进同一个输入框，中间没有被「掉出去」的段落。
    expect(
      field.controller!.text,
      '第一段\n\n第二段\n\n第三段\n\n第四段',
    );
    final selected = field.controller!.text.substring(
      field.controller!.selection.start,
      field.controller!.selection.end,
    );
    expect(selected, contains('第二段'));
    expect(selected, contains('第三段'));
  });

  testWidgets('框内向上拖选仍只改选区，不并块（不进入跨段模式）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(
      text: '第一行\n第二行\n第三行\n\n下一段',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('第三行'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField));
    await _mouseDrag(
      tester,
      from: Offset(rect.left + 40, rect.bottom - 10),
      to: Offset(rect.left + 40, rect.top + 10),
      steps: 16,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    // 只在当前块内选择：输入框文本仍是点击的那一段。
    expect(field.controller!.text, '第一行\n第二行\n第三行');
    expect(field.controller!.selection.isCollapsed, isFalse);
    expect(controller.text, '第一行\n第二行\n第三行\n\n下一段');
  });

  testWidgets('触摸拖选不触发跨段合并（移动端保持原有长按选词）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.reset);
    final controller = TextEditingController(text: '第一段\n\n第二段');
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二段'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField));
    final gesture = await tester.startGesture(
      Offset(rect.left + 40, rect.bottom - 8),
    );
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 1; i <= 12; i++) {
      await gesture.moveTo(
        Offset(rect.left + 40, rect.bottom - 8 - (rect.height + 60) * i / 12),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // 触摸指针被忽略：不会把上一段并进输入框。
    expect(controller.text, '第一段\n\n第二段');
  });

  testWidgets('渲染态点按代码块主体就地展开该段源码（不是复制）', (tester) async {
    final controller = TextEditingController(
      text: '正文段落\n\n```python\nprint(1)\n```\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_wrap(controller: controller));
    await tester.pumpAndSettle();

    // 渲染态：代码块由 MarkdownCodeBlock 展示，语言角标可读，没有源码输入框。
    expect(find.text('python'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('python'));
    await tester.pumpAndSettle();
    // 点语言按钮是「复制」，正文不该被改写、也不进入编辑态。
    expect(find.byType(TextField), findsNothing);
    expect(controller.text, contains('```python'));

    // 点代码块主体：就地展开这一段源码（实时预览里必须还能编辑代码块）。
    await tester.tap(find.textContaining('print(1)'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '```python\nprint(1)\n```');
    // 展开源码不改变正文，也不产生重复的代码内容。
    expect(controller.text, '正文段落\n\n```python\nprint(1)\n```\n');
  });
}

/// 模拟鼠标「按住左键从 [from] 拖到 [to]」。
Future<void> _mouseDrag(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
  int steps = 12,
}) async {
  final gesture = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 20));
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
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

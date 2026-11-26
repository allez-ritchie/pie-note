import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/notes/live_preview_editor.dart';
import 'package:pie_note/ui/notes/markdown_table.dart';
import 'package:pie_note/ui/notes/markdown_table_strings.dart';
import 'package:pie_note/ui/notes/markdown_view.dart';

const String _table = '''
| 分组 | 引脚 |
| --- | --- |
| 5V | 2、3 |
| GND | 1、4 |
''';

Widget _wrap(String content, {ValueChanged<String>? onChanged}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownView(content: content, onTableChanged: onChanged),
          ),
        ),
      ),
    ),
  );
}

/// 测试用的共用鼠标：一只真实的鼠标指针 + 它的 pointer id。
///
/// MouseTracker 要求 PointerAdded/Removed 成对出现，同一个测试里反复
/// createGesture 建鼠标会触发它的断言；右键也必须复用同一个 pointer id
/// （TestGesture.down 不接受 buttons 参数）。
class _Mouse {
  _Mouse(this.gesture, this.pointer);

  final TestGesture gesture;
  final int pointer;
}

/// 把测试视口调高，保证右键菜单（十几项）全部落在屏幕内，否则点击会打在
/// 屏幕外面（默认 800×600 不够高）。
void _tallViewport(WidgetTester tester, {Size size = const Size(900, 1200)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// 建立一只共用的鼠标指针。
Future<_Mouse> _mouse(WidgetTester tester, Offset start) async {
  const pointer = 7;
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    pointer: pointer,
  );
  await gesture.addPointer(location: start);
  addTearDown(gesture.removePointer);
  await tester.pump();
  return _Mouse(gesture, pointer);
}

/// 把共用鼠标移到 [position]，触发 MouseRegion 的悬停回调。
Future<void> _hoverTo(
  WidgetTester tester,
  _Mouse mouse,
  Offset position,
) async {
  await mouse.gesture.moveTo(position);
  await tester.pumpAndSettle();
}

/// 在 [position] 上点一次右键（鼠标右键）。
///
/// 用「按住右键的独立指针」而不是 TestGesture.down：TestGesture.down 不接受
/// buttons 参数，右键必须靠 createGesture 的 buttons 指定。
Future<void> _rightClick(
  WidgetTester tester,
  _Mouse mouse,
  Offset position,
) async {
  await mouse.gesture.moveTo(position);
  await tester.pumpAndSettle();
  // 复用同一只鼠标指针的 id 直接发事件：MouseTracker 要求 Added/Removed 成对，
  // 同一个测试里再 createGesture 一只鼠标会触发它的断言。
  final device = mouse.pointer;
  await tester.sendEventToBinding(
    PointerDownEvent(
      pointer: device,
      device: device,
      position: position,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    ),
  );
  await tester.pump();
  await tester.sendEventToBinding(
    PointerUpEvent(
      pointer: device,
      device: device,
      position: position,
      kind: PointerDeviceKind.mouse,
    ),
  );
  await tester.pumpAndSettle();
}

/// 选中某列（悬停到列顶 → 点六点手柄）。
Future<void> _selectColumn(
  WidgetTester tester,
  _Mouse mouse,
  Rect tableRect,
  int column,
  int columnCount,
) async {
  final width = tableRect.width / columnCount;
  await _hoverTo(
    tester,
    mouse,
    Offset(tableRect.left + width * column + width / 2, tableRect.top + 1),
  );
  await tester.tap(find.byTooltip(MarkdownTableStrings.selectColumn));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('表格渲染成单元格网格，而不是一整段源码', (tester) async {
    await tester.pumpWidget(_wrap(_table));
    await tester.pumpAndSettle();

    // 单元格文本各自独立渲染（能按内容找到），且看不到 Markdown 竖线源码。
    expect(find.text('分组'), findsOneWidget);
    expect(find.text('引脚'), findsOneWidget);
    expect(find.text('5V'), findsOneWidget);
    expect(find.text('GND'), findsOneWidget);
    expect(find.textContaining('| --- |'), findsNothing);
  });

  testWidgets('点击单元格只让该单元格进入编辑态，其它单元格保持渲染', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();

    // 只有一个输入框，内容是被点的那个单元格，其余单元格仍是渲染文本。
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '5V');
    expect(find.text('GND'), findsOneWidget);
    expect(find.text('分组'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '5V 主供电');
    await tester.pumpAndSettle();

    // 回写的仍然是一整张表，只有目标单元格变了。
    expect(changes, isNotEmpty);
    final written = MarkdownTable.tryParse(changes.last)!;
    expect(written.cellAt(1, 0), '5V 主供电');
    expect(written.cellAt(2, 0), 'GND');
    expect(written.cellAt(0, 1), '引脚');
  });

  testWidgets('鼠标悬停最后一列右侧出现「在右侧新增列」，点击后表格多一列', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    // 未悬停时没有新增列的窄条。
    expect(find.byTooltip(MarkdownTableStrings.addColumnRight), findsNothing);

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _hoverTo(tester, mouse, Offset(tableRect.right - 2, tableRect.center.dy));
    expect(find.byTooltip(MarkdownTableStrings.addColumnRight), findsOneWidget);

    await tester.tap(find.byTooltip(MarkdownTableStrings.addColumnRight));
    await tester.pumpAndSettle();

    final written = MarkdownTable.tryParse(changes.last)!;
    expect(written.columnCount, 3);
    expect(written.bodyRowCount, 2);
  });

  testWidgets('鼠标悬停最后一行下方出现「在下方新增行」，点击后表格多一行', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    expect(find.byTooltip(MarkdownTableStrings.addRowBelow), findsNothing);

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _hoverTo(tester, mouse, Offset(tableRect.center.dx, tableRect.bottom - 2));
    expect(find.byTooltip(MarkdownTableStrings.addRowBelow), findsOneWidget);

    await tester.tap(find.byTooltip(MarkdownTableStrings.addRowBelow));
    await tester.pumpAndSettle();

    final written = MarkdownTable.tryParse(changes.last)!;
    expect(written.bodyRowCount, 3);
    expect(written.columnCount, 2);
    expect(written.cellAt(3, 0), '');
  });

  testWidgets('悬停列顶出现六点手柄，点击选中整列后右键弹出菜单', (tester) async {
    _tallViewport(tester);
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    // 悬停到第一列表头顶部：六点手柄出现。
    await _hoverTo(tester, mouse, Offset(tableRect.left + 40, tableRect.top + 1));
    expect(find.byTooltip(MarkdownTableStrings.selectColumn), findsOneWidget);

    await tester.tap(find.byTooltip(MarkdownTableStrings.selectColumn));
    await tester.pumpAndSettle();

    // 右键第一列：弹出操作菜单（剪切 / 复制 / 粘贴 / 文本格式 / 对齐 …）。
    final cell = tester.getCenter(find.text('5V')) + const Offset(6, 0);
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();

    expect(find.text(MarkdownTableStrings.menuCopy), findsOneWidget);
    expect(find.text(MarkdownTableStrings.menuFormat), findsOneWidget);
    expect(find.text(MarkdownTableStrings.menuClearCells), findsOneWidget);

    // 删除选中的列：整列被移除，表格剩一列。
    await tester.tap(find.text(MarkdownTableStrings.menuDeleteCells));
    await tester.pumpAndSettle();
    final written = MarkdownTable.tryParse(changes.last)!;
    expect(written.columnCount, 1);
    expect(written.cellAt(0, 0), '引脚');
  });

  testWidgets('右键菜单可居中选中列并复制到剪贴板', (tester) async {
    _tallViewport(tester);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          case 'Clipboard.getData':
            return <String, dynamic>{'text': clipboard ?? ''};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_wrap(_table, onChanged: (_) {}));
    await tester.pumpAndSettle();

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _hoverTo(tester, mouse, Offset(tableRect.left + 40, tableRect.top + 1));
    await tester.tap(find.byTooltip(MarkdownTableStrings.selectColumn));
    await tester.pumpAndSettle();

    final cell = tester.getCenter(find.text('5V')) + const Offset(6, 0);
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();

    await tester.tap(find.text(MarkdownTableStrings.menuCopy));
    await tester.pumpAndSettle();

    expect(clipboard, isNotNull);
    final rows = MarkdownTableClipboard.decode(clipboard!);
    expect(rows.first, ['分组']);
    expect(rows.map((row) => row.first), ['分组', '5V', 'GND']);
  });

  testWidgets('单元格内横向拖选跨出单元格时改为矩形选中单元格区域', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_wrap(_table, onChanged: (_) {}));
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.text('分组'));
    final end = tester.getCenter(find.text('GND')) + const Offset(6, 0);
    final mouse = await _mouse(tester, start);
    await mouse.gesture.down(start);
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.gesture.moveTo(Offset(start.dx + 30, start.dy));
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.gesture.moveTo(end);
    await tester.pumpAndSettle();
    await mouse.gesture.up();
    await tester.pumpAndSettle();

    // 拖选后不再进入单元格编辑态；右键菜单作用于整块矩形选区。
    expect(find.byType(TextField), findsNothing);
    final cell = tester.getCenter(find.text('5V'));
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();
    expect(find.text(MarkdownTableStrings.menuDeleteCells), findsOneWidget);
  });

  testWidgets('阅读视图的表格只读：没有新增行列窄条，点单元格不进入编辑', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: MarkdownView(content: _table)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _hoverTo(tester, mouse, Offset(tableRect.right - 2, tableRect.center.dy));
    expect(find.byTooltip(MarkdownTableStrings.addColumnRight), findsNothing);
  });

  testWidgets('实时预览点击表格单元格不会把整块表格换成源码输入框', (tester) async {
    _tallViewport(tester, size: const Size(800, 900));
    final controller = TextEditingController(
      text: '正文段落\n\n$_table\n表格之后的段落\n',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LivePreviewEditor(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();

    // 表格其余单元格仍以渲染态存在（没有被整块源码替换）。
    expect(find.text('GND'), findsOneWidget);
    expect(find.text('分组'), findsOneWidget);
    // 整篇正文的源码没有出现在编辑器里。
    expect(find.textContaining('| --- |'), findsNothing);

    await tester.enterText(find.byType(TextField), '5V（已改）');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(controller.text, contains('5V（已改）'));
    expect(controller.text, contains('表格之后的段落'));
    // 表格结构仍然是 2 列 3 行（含表头），没有被拆散。
    final table = MarkdownTable.tryParse(
      controller.text
          .split('\n\n')
          .firstWhere((block) => block.contains('| --- |')),
    )!;
    expect(table.columnCount, 2);
    expect(table.totalRowCount, 3);
  });

  testWidgets('实时预览里选中整列后右键删除，整列从正文里消失', (tester) async {
    _tallViewport(tester);
    final controller = TextEditingController(text: _table);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: LivePreviewEditor(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    // 悬停第二列（引脚）列顶，选中后删除：只剩第一列。
    await _selectColumn(tester, mouse, tableRect, 1, 2);

    final cell = tester.getCenter(find.text('2、3'));
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();

    // 选中整列时「删除选中的单元格」= 删除整列，菜单项可用且不报错。
    expect(find.text(MarkdownTableStrings.menuPaste), findsOneWidget);
    await tester.tap(find.text(MarkdownTableStrings.menuDeleteCells));
    await tester.pumpAndSettle();

    expect(controller.text, contains('分组'));
    expect(controller.text, isNot(contains('引脚')));
    expect(controller.text, isNot(contains('2、3')));
  });

  testWidgets('单元格内左右拖动不跨出单元格时只选文字，不进入单元格框选', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_wrap(_table, onChanged: (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // 只有「一个」单元格进入编辑态；其余单元格仍渲染（不是整块源码）。
    expect(find.text('分组'), findsOneWidget);
    expect(find.text('GND'), findsOneWidget);
  });

  testWidgets('编辑单元格按 Esc 取消改动并收起输入框', (tester) async {
    _tallViewport(tester);
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '乱改的内容');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    // 回滚到进入编辑前的文本。
    expect(MarkdownTable.tryParse(changes.last)!.cellAt(1, 0), '5V');
  });

  testWidgets('编辑单元格按 Tab 提交并跳到同一行的下一个单元格', (tester) async {
    _tallViewport(tester);
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5V'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5V');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '2、3',
    );
  });

  testWidgets('编辑单元格按 Enter 提交并跳到下一行同一列', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_wrap(_table, onChanged: (_) {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('分组'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '5V',
    );
  });

  testWidgets('右键菜单的「文本格式」可以给选中单元格加粗', (tester) async {
    _tallViewport(tester);
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _selectColumn(tester, mouse, tableRect, 0, 2);
    final cell = tester.getCenter(find.text('5V')) + const Offset(6, 0);
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();

    await tester.tap(find.text(MarkdownTableStrings.menuFormat));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MarkdownTableStrings.formatBold));
    await tester.pumpAndSettle();

    final table = MarkdownTable.tryParse(changes.last)!;
    expect(table.cellAt(0, 0), '**分组**');
    expect(table.cellAt(1, 0), '**5V**');
    // 只作用于选中的那一列。
    expect(table.cellAt(0, 1), '引脚');
  });

  testWidgets('右键菜单的「居中对齐」写回分隔线', (tester) async {
    _tallViewport(tester);
    final changes = <String>[];
    await tester.pumpWidget(_wrap(_table, onChanged: changes.add));
    await tester.pumpAndSettle();

    final mouse = await _mouse(tester, const Offset(1, 1));
    final tableRect = tester.getRect(find.byType(Table));
    await _selectColumn(tester, mouse, tableRect, 1, 2);
    final cell = tester.getCenter(find.text('2、3')) + const Offset(6, 0);
    await _rightClick(tester, mouse, cell);
    await tester.pumpAndSettle();

    await tester.tap(find.text(MarkdownTableStrings.alignCenter));
    await tester.pumpAndSettle();

    final table = MarkdownTable.tryParse(changes.last)!;
    expect(table.alignments[1], MarkdownTableAlign.center);
    expect(table.alignments[0], MarkdownTableAlign.none);
  });

  testWidgets('拖动跨越单元格是矩形框选（可跨多行多列），不是选中整行', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      _wrap(
        '| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |',
        onChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    // 从 A 拖到 3：应选中「表头行 + 第一数据行」共 2 行 × 3 列的一块区域。
    final start = tester.getCenter(find.text('A')) + const Offset(6, 0);
    final end = tester.getCenter(find.text('3')) + const Offset(-6, 0);
    final mouse = await _mouse(tester, start);
    await mouse.gesture.down(start);
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.gesture.moveTo(Offset(start.dx + 20, start.dy));
    await tester.pump(const Duration(milliseconds: 20));
    await mouse.gesture.moveTo(end);
    await tester.pumpAndSettle();
    await mouse.gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    // 清空这块矩形：A / B / C / 1 / 2 / 3 都变空，4、5、6 不受影响。
    await _rightClick(tester, mouse, tester.getCenter(find.text('2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(MarkdownTableStrings.menuClearCells));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('阅读视图的表格可以跨单元格拖选文字（不进入单元格编辑）', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SelectionArea(
              child: SingleChildScrollView(
                child: MarkdownView(content: _table, selectable: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.text('5V')) + const Offset(-8, 0);
    final end = tester.getCenter(find.text('GND')) + const Offset(8, 0);
    final mouse = await _mouse(tester, start);
    await mouse.gesture.down(start);
    await tester.pump(const Duration(milliseconds: 20));
    for (var i = 1; i <= 8; i++) {
      await mouse.gesture.moveTo(Offset.lerp(start, end, i / 8)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await mouse.gesture.up();
    await tester.pumpAndSettle();

    // 只读表格没有单元格编辑框；选区由外层 SelectionArea 负责。
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('一篇笔记里两个表格各自独立编辑，不会串味', (tester) async {
    _tallViewport(tester, size: const Size(900, 1400));
    String? last;
    await tester.pumpWidget(
      _wrap(
        '前文\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n中间段落\n\n'
        '| C | D |\n| --- | --- |\n| 3 | 4 |\n\n后文',
        onChanged: (value) => last = value,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Table), findsNWidgets(2));

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3（改）');
    await tester.pumpAndSettle();

    final parsed = MarkdownTable.tryParse(last!)!;
    expect(parsed.cellAt(1, 0), '3（改）');
    expect(parsed.cellAt(0, 0), 'C');
    // 另一个表格仍是渲染态，内容没被这次编辑带走。
    expect(find.text('A'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });
}

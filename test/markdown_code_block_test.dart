import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/common/strings.dart';
import 'package:pie_note/ui/notes/markdown_code_block.dart';
import 'package:pie_note/ui/notes/markdown_view.dart';

Widget _wrap(String content, {VoidCallback? onTapCodeBlock}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownView(
            content: content,
            onTapCodeBlock: onTapCodeBlock,
          ),
        ),
      ),
    ),
  );
}

/// 拦截系统剪贴板写入，返回可读取的最终文本。
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
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
  return copied;
}

void main() {
  const pythonBlock = '```python\nprint("hi")\n```';

  group('围栏代码块的解析辅助', () {
    testWidgets('info string 的第一个单词作为语言标签', (tester) async {
      await tester.pumpWidget(
        _wrap('```python\nprint(1)\n```\n\n```dart title="a.dart"\nvoid main() {}\n```'),
      );
      await tester.pumpAndSettle();

      final blocks = tester.widgetList<MarkdownCodeBlock>(
        find.byType(MarkdownCodeBlock),
      );
      expect(blocks.map((block) => block.language), ['python', 'dart']);
    });

    testWidgets('没写语言时输入框按 text 展示', (tester) async {
      await tester.pumpWidget(_wrap('```\n纯文本代码\n```'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<MarkdownCodeBlock>(find.byType(MarkdownCodeBlock))
            .language,
        isEmpty,
      );
      expect(find.text(kCodeBlockPlainLabel), findsOneWidget);
    });

    testWidgets('代码正文去掉解析器补的行尾换行', (tester) async {
      await tester.pumpWidget(_wrap(pythonBlock));
      await tester.pumpAndSettle();

      final block = tester.widget<MarkdownCodeBlock>(
        find.byType(MarkdownCodeBlock),
      );
      expect(block.code, 'print("hi")');
    });

    testWidgets('未闭合围栏也按代码块渲染，不丢正文', (tester) async {
      await tester.pumpWidget(_wrap('```\n没有闭合\n'));
      await tester.pumpAndSettle();

      final block = tester.widget<MarkdownCodeBlock>(
        find.byType(MarkdownCodeBlock),
      );
      expect(block.code, '没有闭合');
    });
  });

  group('代码块等宽', () {
    testWidgets('短代码块也铺满正文宽度，与长代码块等宽', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          '```python\nx = 1\n```\n\n'
          '```cpp\n'
          '// 这一行很长很长很长很长很长很长很长很长很长很长很长很长很长很长很长\n'
          '```\n',
        ),
      );
      await tester.pumpAndSettle();

      final blocks = find.byType(MarkdownCodeBlock);
      expect(blocks, findsNWidgets(2));
      final shortWidth = tester.getSize(blocks.at(0)).width;
      final longWidth = tester.getSize(blocks.at(1)).width;
      // 短代码块的底色不再跟着最长一行收缩：两个块宽度一致，且接近整页宽度。
      expect(shortWidth, longWidth);
      expect(shortWidth, greaterThan(600));
    });
  });

  group('点按复制', () {
    testWidgets('只读场景点按整块即复制，语言按钮就地变成「已复制」', (tester) async {
      final copied = _mockClipboard(tester);
      await tester.pumpWidget(_wrap(pythonBlock));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MarkdownCodeBlock));
      await tester.pumpAndSettle();

      expect(copied, ['print("hi")']);
      expect(find.text(S.codeCopied), findsOneWidget);
      expect(find.text('python'), findsNothing);

      // 1.5 秒后恢复语言标签，不影响后续继续复制。
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();
      expect(find.text('python'), findsOneWidget);
    });

    testWidgets('点右上角语言按钮同样复制，且不触发「点按代码块」回调', (tester) async {
      final copied = _mockClipboard(tester);
      var tappedBlock = 0;
      await tester.pumpWidget(
        _wrap(pythonBlock, onTapCodeBlock: () => tappedBlock++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('python'));
      await tester.pumpAndSettle();

      expect(copied, ['print("hi")']);
      expect(tappedBlock, 0);
    });

    testWidgets('传入 onTapCodeBlock 时点块主体交给上层（实时预览就地编辑）', (tester) async {
      var tappedBlock = 0;
      await tester.pumpWidget(
        _wrap(pythonBlock, onTapCodeBlock: () => tappedBlock++),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MarkdownCodeBlock));
      await tester.pumpAndSettle();
      expect(tappedBlock, 1);
    });

    testWidgets('外层套着 SelectionArea（阅读视图）时点按仍能复制', (tester) async {
      final copied = _mockClipboard(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: SingleChildScrollView(
                  child: MarkdownView(content: pythonBlock),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MarkdownCodeBlock));
      await tester.pumpAndSettle();
      expect(copied, ['print("hi")']);
    });

    testWidgets('多行代码原样复制，不丢缩进', (tester) async {
      final copied = _mockClipboard(tester);
      await tester.pumpWidget(
        _wrap('```sh\n#!/bin/sh\nif true; then\n    echo ok\nfi\n```'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MarkdownCodeBlock));
      await tester.pumpAndSettle();
      expect(copied.single, '#!/bin/sh\nif true; then\n    echo ok\nfi');
    });
  });
}

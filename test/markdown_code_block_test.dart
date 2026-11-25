import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/ui/common/strings.dart';
import 'package:pie_note/ui/notes/markdown_code_block.dart';
import 'package:pie_note/ui/notes/markdown_view.dart';
import 'package:pie_note/ui/theme/app_theme.dart';

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

  group('语法高亮', () {
    /// 收集 RichText 里出现过的所有 token 颜色。
    Set<Color> tokenColors(WidgetTester tester) {
      // 代码块里还有语言角标这类普通 Text（同样是 RichText），只看带子
      // span 的那一个——高亮后的代码正文被拆成了多个 token span。
      final richTexts = tester.widgetList<RichText>(
        find.descendant(
          of: find.byType(MarkdownCodeBlock),
          matching: find.byType(RichText),
        ),
      );
      final code = richTexts.firstWhere(
        (widget) =>
            widget.text is TextSpan && ((widget.text as TextSpan).children?.length ?? 0) > 0,
      );
      final colors = <Color>{};
      void visit(InlineSpan span) {
        if (span is! TextSpan) return;
        final text = span.text;
        final color = span.style?.color;
        if (text != null && text.trim().isNotEmpty && color != null) {
          colors.add(color);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }

      visit(code.text);
      return colors;
    }

    testWidgets('Python 代码渲染出多种颜色的 token（不再是单色）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          '```python\n'
          'def greet(name):\n'
          '    return f"hi {name}"  # 注释\n'
          '```',
        ),
      );
      await tester.pumpAndSettle();

      // 关键字 / 字符串 / 注释 至少落到 3 种不同颜色上。
      expect(tokenColors(tester).length, greaterThanOrEqualTo(3));
    });

    testWidgets('未知语言仍是单色，且正文完整显示', (tester) async {
      await tester.pumpWidget(
        _wrap('```wubalubadubdub\nsome plain text here\n```'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('some plain text here', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('高亮不改变正文：复制出来仍是原始代码', (tester) async {
      final copied = _mockClipboard(tester);
      await tester.pumpWidget(
        _wrap('```js\nconst a = 1; // 注释\nconsole.log(a);\n```'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('js'));
      await tester.pumpAndSettle();
      expect(copied.single, 'const a = 1; // 注释\nconsole.log(a);');
    });

    testWidgets('深色主题用另一套高亮配色', (tester) async {
      Future<Set<Color>> colorsIn(ThemeData theme) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: MarkdownView(
                    content: '```python\ndef f(): pass  # c\n```',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return tokenColors(tester);
      }

      final light = await colorsIn(AppTheme.light());
      final dark = await colorsIn(AppTheme.dark());
      expect(light.intersection(dark), isEmpty);
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

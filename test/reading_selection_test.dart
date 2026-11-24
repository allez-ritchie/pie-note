import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/markdown_view.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';

/// 多个不同标题的节，用来验证阅读视图的选取范围能跨节连续。
const String _content = '''
# 第一章

第一章的正文段落。

## 第一节

第一节的正文段落。

# 第二章

第二章的正文段落。
''';

http.Response _json(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

ApiClient _fakeClient() {
  return ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      return _json({
        'id': 'note:demo',
        'title': '选区演示',
        'content': _content,
        'note_type': 'human',
        'updated': '2026-11-24 03:00:00+00:00',
      });
    }),
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  Size size = const Size(1000, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_fakeClient())],
      child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchToReading(WidgetTester tester) async {
  await tester.tap(find.byTooltip(EditorStrings.switchMode));
  await tester.pumpAndSettle();
  await tester.tap(find.text(EditorStrings.modeReading).last);
  await tester.pumpAndSettle();
}

/// 长按 [from] 并拖到 [to]，模拟手指跨段落选择。
///
/// 长按落点会选中手指下的字符，起点可能吃掉第一个字，因此断言只要求
/// 「覆盖到中间与末尾的段落」。
Future<void> _dragSelect(WidgetTester tester, Finder from, Finder to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 把若干 [MarkdownView] 放进**同一个** SelectionArea，并记录最终选区文本。
///
/// 对应阅读视图的真实结构：每个标题一节、每节一个 MarkdownView，
/// 但整页只有一个选区容器。
class _SectionedProbe extends StatefulWidget {
  const _SectionedProbe({required this.sections});

  final List<String> sections;

  @override
  State<_SectionedProbe> createState() => _SectionedProbeState();
}

class _SectionedProbeState extends State<_SectionedProbe> {
  String? selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SelectionArea(
        onSelectionChanged: (content) =>
            setState(() => selected = content?.plainText),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final section in widget.sections)
                MarkdownView(content: section, selectable: true),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  group('渲染组件的选区结构', () {
    testWidgets('selectable 时段落渲染不再各开一个 SelectableText', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: MarkdownView(content: '第一段\n\n第二段\n\n第三段', selectable: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 只用外层一个选区容器；段落是普通 RichText，选区在它们之间连续。
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('非 selectable 时不引入选区容器（实时预览要点按段落）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: MarkdownView(content: '第一段\n\n第二段')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
    });
  });

  group('跨段落选择', () {
    testWidgets('单个渲染块内：拖选可一次覆盖多段', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _SectionedProbe(sections: const ['第一段\n\n第二段\n\n第三段']),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final probe = tester.state<_SectionedProbeState>(
        find.byType(_SectionedProbe),
      );
      await _dragSelect(tester, find.text('第一段'), find.text('第三段'));

      final selected = probe.selected ?? '';
      expect(selected.contains('第二段'), isTrue, reason: '中间段落也应被选中');
      // 长按落点选中手指下的字符，拖到末尾时最后一个字可能不含在内，
      // 因此只要求选区已经进入最后一段。
      expect(selected.contains('第三'), isTrue, reason: '选区应延伸到第三段');
    });

    testWidgets('多个分节（每节一个 MarkdownView）共用一个选区，能跨节选中', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _SectionedProbe(
              sections: const ['# 第一章\n\n第一章的正文段落。', '## 第一节\n\n第一节的正文段落。'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 两节各自渲染，但只有外层一个选区容器。
      expect(find.byType(MarkdownView), findsNWidgets(2));
      expect(find.byType(SelectionArea), findsOneWidget);

      final probe = tester.state<_SectionedProbeState>(
        find.byType(_SectionedProbe),
      );
      await _dragSelect(
        tester,
        find.text('第一章的正文段落。'),
        find.text('第一节的正文段落。'),
      );

      final selected = probe.selected ?? '';
      expect(selected.contains('第一节'), isTrue, reason: '选区应跨到下一节');
    });
  });

  group('阅读视图', () {
    testWidgets('按标题分节渲染时整页只有一个选区容器', (tester) async {
      await _pumpEditor(tester);
      await _switchToReading(tester);

      // 多个分节 + 一个整页选区容器；分节内部不能再套选区，否则跨节选不中。
      expect(find.byType(MarkdownView), findsWidgets);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('窄窗口（无源码对照栏）不出现多余的选区容器', (tester) async {
      await _pumpEditor(tester, size: const Size(680, 880));
      await _switchToReading(tester);

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });
  });
}

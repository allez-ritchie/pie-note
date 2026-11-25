import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notes/editor_scroll_tail.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/live_preview_editor.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';

/// 正文末尾的可滚动留白：让最后一行能滚到屏幕中间（参考 Obsidian）。
///
/// 三个视图（实时预览 / 源码 / 阅读）的滚动实现各不相同，但都要满足：
/// 滚到最底部时，最后一行落在视口垂直中线附近，而不是贴着页面下缘。
const String _lastLine = '这是最后一行正文。';

String _longContent() {
  final buffer = StringBuffer('# 长笔记\n\n');
  for (var i = 1; i <= 40; i++) {
    buffer.writeln('第 $i 段正文，用来撑高滚动区域。\n');
  }
  buffer.write(_lastLine);
  return buffer.toString();
}

http.Response _json(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

ApiClient _fakeClient(String content) {
  return ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      return _json({
        'id': 'note:demo',
        'title': '长笔记',
        'content': content,
        'note_type': 'human',
        'updated': '2026-11-25 03:00:00+00:00',
      });
    }),
  );
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  String? content,
  Size size = const Size(900, 700),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_fakeClient(content ?? _longContent())),
      ],
      child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _switchTo(WidgetTester tester, String modeLabel) async {
  await tester.tap(find.byTooltip(EditorStrings.switchMode));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel).last);
  await tester.pumpAndSettle();
}

/// 把某个滚动区直接拉到最底部。
Future<void> _jumpToBottom(WidgetTester tester, Finder scrollable) async {
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

/// 断言 [target] 的底边落在 [viewport] 的垂直中线附近。
///
/// 留白取半个视口时，滚到底后**最后一行文字的底边**正好压在中线上；
/// 文字本身因此位于中线稍上方（约半个行高），这正是 Obsidian 的观感，
/// 所以这里断言底边而不是中心。
void _expectBottomNearVerticalCenter(
  Rect target,
  Rect viewport, {
  double tolerance = 8,
}) {
  expect(
    (target.bottom - viewport.center.dy).abs(),
    lessThan(tolerance),
    reason: '最后一行底边应停在中线附近，实际 ${target.bottom} vs 中线 ${viewport.center.dy}',
  );
}

void main() {
  group('editorBottomInset', () {
    test('一半视口大于常规内边距时取半个视口', () {
      expect(editorBottomInset(600, 40), 300);
      expect(editorBottomInset(1200, 16), 600);
    });

    test('视口很矮时保留常规内边距，而不是两者相加', () {
      expect(editorBottomInset(80, 40), 40);
      expect(editorBottomInset(0, 32), 32);
    });

    test('无界或非正的视口高度退回常规内边距，避免加出无穷大', () {
      expect(editorBottomInset(double.infinity, 40), 40);
      expect(editorBottomInset(double.nan, 40), 40);
      expect(editorBottomInset(-10, 40), 40);
    });

    test('editorTailBlank 取视口高度的一半', () {
      expect(editorTailBlank(600), 300);
      expect(editorTailBlank(double.infinity), 0);
      expect(editorTailBlank(double.nan), 0);
    });
  });

  testWidgets('实时预览滚到底：最后一行停在视口中线附近', (tester) async {
    await _pumpEditor(tester);

    final scrollable = find
        .descendant(
          of: find.byType(LivePreviewEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    await _jumpToBottom(tester, scrollable);

    _expectBottomNearVerticalCenter(
      tester.getRect(find.text(_lastLine)),
      tester.getRect(scrollable),
    );
  });

  testWidgets('阅读视图滚到底：最后一行停在视口中线附近', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeReading);

    final scrollable = find
        .descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(Scrollable),
        )
        .first;
    await _jumpToBottom(tester, scrollable);

    _expectBottomNearVerticalCenter(
      tester.getRect(find.text(_lastLine)),
      tester.getRect(scrollable),
    );
  });

  testWidgets('源码模式滚到底：最后一行停在视口中线附近', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeSource);

    // 源码模式的滚动在外层 SingleChildScrollView：输入框随正文长高、自身不再滚动。
    final scrollable = find
        .ancestor(
          of: find.byType(TextField).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await _jumpToBottom(tester, scrollable);

    // 用最后一行的渲染矩形判断：光标矩形的底边就是该行的行底。
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byType(TextField).last,
        matching: find.byType(EditableText),
      ),
    );
    final caret = editable.renderEditable.getLocalRectForCaret(
      TextPosition(offset: editable.textEditingValue.text.length),
    );
    final lineBottom = caret.shift(
      editable.renderEditable.localToGlobal(Offset.zero),
    );

    _expectBottomNearVerticalCenter(lineBottom, tester.getRect(scrollable));
  });

  testWidgets('源码模式在末尾继续输入时，外层滚动跟住光标', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeSource);

    final field = find.byType(TextField).last;
    await tester.tapAt(const Offset(450, 300));
    await tester.pumpAndSettle();

    final scrollable = find
        .ancestor(of: field, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);

    // 真实打字（而不是直接改选区）才会触发框架的 caret show-on-screen。
    final controller = tester.widget<TextField>(field).controller!;
    await tester.enterText(field, '${controller.text}\n新输入的一行');
    await tester.pumpAndSettle();

    // 光标停在末尾时，外层已经把正文滚下去，最后一行不再被视口下缘截断。
    expect(position.pixels, greaterThan(0));
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    final caret = editable.renderEditable
        .getLocalRectForCaret(
          TextPosition(offset: controller.text.length),
        )
        .shift(editable.renderEditable.localToGlobal(Offset.zero));
    expect(caret.bottom, lessThanOrEqualTo(tester.getRect(scrollable).bottom));
  });

  testWidgets('短笔记不因末尾留白出现可滚动条（正文仍从顶部开始）', (tester) async {
    await _pumpEditor(tester, content: '# 标题\n\n$_lastLine\n');

    // 视口够高：短笔记在留白之后仍不足以产生滚动，正文保持贴顶。
    final scrollable = find
        .descendant(
          of: find.byType(LivePreviewEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    final state = tester.state<ScrollableState>(scrollable);
    expect(state.position.pixels, 0);
    expect(
      tester.getTopLeft(find.text(_lastLine)).dy,
      lessThan(tester.getRect(scrollable).center.dy),
    );
  });
}

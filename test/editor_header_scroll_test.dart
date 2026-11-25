import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/live_preview_editor.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';

/// 笔记名（标题 + 保存状态行）不常驻：它和正文在同一个滚动区里，
/// 滚轮 / 上划时一起滚出视口（参考 Obsidian）。
const String _noteTitle = '滚动的笔记名';

String _longContent() {
  final buffer = StringBuffer('# 小节\n\n');
  for (var i = 1; i <= 40; i++) {
    buffer.writeln('第 $i 段正文，用来撑高滚动区域。\n');
  }
  buffer.write('最后一行。');
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
        'title': _noteTitle,
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
        apiClientProvider.overrideWithValue(
          _fakeClient(content ?? _longContent()),
        ),
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

/// 把滚动区直接滚到最底部。
Future<void> _jumpToBottom(WidgetTester tester, Finder scrollable) async {
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

/// 笔记名（标题输入框 / 只读标题）在屏幕上的位置。
Finder get _titleWidget => find.text(_noteTitle);

void main() {
  testWidgets('实时预览：滚到底后笔记名滚出视口', (tester) async {
    await _pumpEditor(tester);

    expect(_titleWidget, findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byType(LivePreviewEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    final viewport = tester.getRect(scrollable);
    expect(tester.getRect(_titleWidget).bottom, lessThan(viewport.top + 200));

    await _jumpToBottom(tester, scrollable);

    // 标题是滚动区内容的一部分：滚到底后它已经在视口上方之外。
    expect(tester.getRect(_titleWidget).bottom, lessThan(viewport.top));
  });

  testWidgets('源码模式：滚到底后笔记名滚出视口', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeSource);

    expect(_titleWidget, findsOneWidget);
    final scrollable = find
        .ancestor(
          of: find.byType(TextField).last,
          matching: find.byType(Scrollable),
        )
        .first;
    final viewport = tester.getRect(scrollable);

    await _jumpToBottom(tester, scrollable);
    expect(tester.getRect(_titleWidget).bottom, lessThan(viewport.top));
  });

  testWidgets('阅读视图：滚到底后笔记名滚出视口', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeReading);

    expect(_titleWidget, findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byType(SelectionArea),
          matching: find.byType(Scrollable),
        )
        .first;
    final viewport = tester.getRect(scrollable);

    await _jumpToBottom(tester, scrollable);
    expect(tester.getRect(_titleWidget).bottom, lessThan(viewport.top));
  });

  testWidgets('滚回顶部时笔记名重新出现（不是被移出滚动区）', (tester) async {
    await _pumpEditor(tester);
    final scrollable = find
        .descendant(
          of: find.byType(LivePreviewEditor),
          matching: find.byType(Scrollable),
        )
        .first;
    await _jumpToBottom(tester, scrollable);
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(tester.getRect(_titleWidget).bottom, greaterThan(0));
  });

  testWidgets('实时预览不再显示「点按任意段落…」提示', (tester) async {
    await _pumpEditor(tester);

    // 提示行已删除：正文区顶部直接是笔记名。
    expect(
      find.text('点按任意段落即可就地编辑，点击别处自动收起'),
      findsNothing,
    );
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);

    // 正文仍然点按即进入就地编辑（删掉的只是提示，不是能力）。
    await tester.tap(find.textContaining('第 1 段正文').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('新建草稿：正文为空时仍能编辑笔记名', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: NoteEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 笔记名（标题输入框）在头部里，空正文只是下方的一段占位，不能把头部顶掉。
    final titleField = find.byType(TextField);
    expect(titleField, findsOneWidget);
    await tester.enterText(titleField, '新笔记的标题');
    await tester.pumpAndSettle();
    expect(find.text('新笔记的标题'), findsOneWidget);
    expect(find.text(EditorStrings.startWriting), findsOneWidget);
  });

  testWidgets('实时预览里点标题输入框不会把某段展开成源码', (tester) async {
    await _pumpEditor(tester);

    await tester.tap(_titleWidget);
    await tester.pumpAndSettle();

    // 标题是独立输入框；点它只聚焦标题，不会误触发正文段落就地编辑。
    expect(find.text(EditorStrings.unsavedBadge), findsNothing);
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.map((field) => field.controller!.text).toList(), [_noteTitle]);
  });

  testWidgets('阅读视图的笔记名是纯文本，不与选区抢手势', (tester) async {
    await _pumpEditor(tester);
    await _switchTo(tester, EditorStrings.modeReading);

    // 只读标题不是输入框：整页只有一个选区容器，标题也参与整页选中。
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.text(_noteTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SelectionArea),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
  });
}

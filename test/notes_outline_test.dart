import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';
import 'package:pie_note/ui/notes/notes_outline_panel.dart';

/// 每个标题下垫足够多的正文，让阅读视图必须滚动才能看到后面的标题。
String _filler(String label) =>
    List.generate(12, (i) => '$label第 ${i + 1} 行正文。').join('\n\n');

final String _content =
    '''
# 第一章

${_filler('第一章')}

## 第一节

${_filler('第一节')}

# 第二章

${_filler('第二章')}

## 第二节

${_filler('第二节')}
''';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

ApiClient _fakeClient() {
  return ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      return _json({
        'id': 'note:demo',
        'title': '大纲演示',
        'content': _content,
        'note_type': 'human',
        'updated': '2026-11-24 03:00:00+00:00',
      });
    }),
  );
}

Future<void> _pumpEditor(WidgetTester tester, Size size) async {
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

Future<void> _switchTo(WidgetTester tester, String modeLabel) async {
  await tester.tap(find.byTooltip(EditorStrings.switchMode));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _openOutline(WidgetTester tester) async {
  await tester.tap(find.byTooltip(EditorStrings.outlineTooltip));
  await tester.pumpAndSettle();
}

/// 只在大纲面板里找文本。
Finder _inOutline(String text) => find.descendant(
  of: find.byType(NotesOutlinePanel),
  matching: find.text(text),
);

void main() {
  testWidgets('宽窗口大纲是右侧常驻侧栏，列出各级标题', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _openOutline(tester);

    expect(find.byType(NotesOutlinePanel), findsOneWidget);
    expect(find.text(EditorStrings.outline), findsOneWidget);
    expect(find.text(EditorStrings.outlineCount(4)), findsOneWidget);
    // 标题按层级展示（H1/H2 徽标），且渲染文本不带 `#`。
    expect(find.text('H1'), findsNWidgets(2));
    expect(find.text('H2'), findsNWidgets(2));
    expect(_inOutline('第一章'), findsOneWidget);
    expect(_inOutline('第二节'), findsOneWidget);
    expect(find.textContaining('# 第一章'), findsNothing);

    // 再点一次大纲按钮收起侧栏。
    await tester.tap(find.byTooltip(EditorStrings.outlineHide));
    await tester.pumpAndSettle();
    expect(find.byType(NotesOutlinePanel), findsNothing);
  });

  testWidgets('源码模式点大纲标题，光标跳到该标题的正文处', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _switchTo(tester, EditorStrings.modeSource);
    await _openOutline(tester);

    await tester.tap(_inOutline('第二节'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    final offset = field.controller!.selection.baseOffset;
    // 光标落在「第二节」标题文字上，而不是行首的 `##`。
    expect(_content.substring(offset), startsWith('第二节'));
    // 正文也已滚到该标题（末尾标题在初始视口之外）。源码模式的滚动由外层
    // SingleChildScrollView 负责，输入框随正文长高、自身不再滚动。
    final scrollable = tester.state<ScrollableState>(
      find
          .ancestor(
            of: find.byType(TextField).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
  });

  testWidgets('实时预览点大纲标题，正文滚动到该标题所在段落', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    final probe = find.text('第二章第 1 行正文。');
    final before = tester.getTopLeft(probe).dy;
    expect(before, greaterThan(500));

    await _openOutline(tester);
    await tester.tap(_inOutline('第二章'));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(probe).dy;
    expect(after, lessThan(before));
    expect(after, lessThan(320));
    // 实时预览里点大纲只滚动，不展开就地编辑的源码输入框。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.style?.fontFamily == 'monospace',
      ),
      findsNothing,
    );
  });

  testWidgets('阅读视图点大纲标题，正文滚动到该标题', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _switchTo(tester, EditorStrings.modeReading);

    // 用第二章标题下的正文判断滚动位置，避免与大纲里的同名标题冲突；
    // 目标后面还有第二节的正文，不会被滚动到底部的上限截断。
    final probe = find.text('第二章第 1 行正文。');
    final before = tester.getTopLeft(probe).dy;
    expect(before, greaterThan(500));
    await _openOutline(tester);
    expect(find.byType(NotesOutlinePanel), findsOneWidget);

    await tester.tap(_inOutline('第二章'));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(probe).dy;
    // 目标标题被滚到视口顶部附近：位置明显上移。标题上方留白（Obsidian 风格）
    // 会让正文比纯标题位置再低二十来像素，这里按带留白的距离断言。
    expect(after, lessThan(before));
    expect(after, lessThan(260));
  });

  testWidgets('窄窗口大纲是底部面板，选中标题后关闭并跳转', (tester) async {
    await _pumpEditor(tester, const Size(520, 880));
    await _switchTo(tester, EditorStrings.modeSource);
    await _openOutline(tester);

    // 窄窗口不开侧栏，改用底部面板。
    expect(find.byType(NotesOutlinePanel), findsOneWidget);
    expect(find.byTooltip(EditorStrings.outlineHide), findsNothing);

    await tester.tap(_inOutline('第二章'));
    await tester.pumpAndSettle();

    // 面板关闭，光标已跳到目标标题。
    expect(find.byType(NotesOutlinePanel), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField).last);
    final offset = field.controller!.selection.baseOffset;
    expect(_content.substring(offset), startsWith('第二章'));
  });

  testWidgets('有子标题的标题前有折叠箭头，点箭头只折叠该标题的子标题', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _openOutline(tester);

    // 「第一章」「第二章」各有子标题，其余是叶子标题：只有它们有箭头。
    final toggles = find.descendant(
      of: find.byType(NotesOutlinePanel),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    expect(toggles, findsNWidgets(2));
    expect(_inOutline('第一节'), findsOneWidget);

    // 箭头展开态朝下（0.25 圈），折叠态朝右（0 圈）。
    double firstTurns() => tester
        .widget<AnimatedRotation>(
          find.descendant(
            of: find.byType(NotesOutlinePanel),
            matching: find.byType(AnimatedRotation),
          ).first,
        )
        .turns;
    expect(firstTurns(), 0.25);

    // 点「第一章」前的箭头：它的子标题「第一节」隐藏，兄弟「第二章」不受影响。
    await tester.tap(toggles.first);
    await tester.pumpAndSettle();
    expect(_inOutline('第一节'), findsNothing);
    expect(_inOutline('第二章'), findsOneWidget);
    expect(firstTurns(), 0);

    // 再点一次展开回来。
    await tester.tap(toggles.first);
    await tester.pumpAndSettle();
    expect(_inOutline('第一节'), findsOneWidget);
    expect(firstTurns(), 0.25);
  });

  testWidgets('标题栏「全部折叠 / 全部展开」切换整份大纲', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _openOutline(tester);

    expect(find.text(EditorStrings.outlineCollapseAll), findsOneWidget);
    await tester.tap(find.text(EditorStrings.outlineCollapseAll));
    await tester.pumpAndSettle();

    // 全部折叠后只剩两个一级标题，子标题都藏起来；按钮变成「全部展开」。
    expect(_inOutline('第一节'), findsNothing);
    expect(_inOutline('第二节'), findsNothing);
    expect(_inOutline('第一章'), findsOneWidget);
    expect(find.text(EditorStrings.outlineExpandAll), findsOneWidget);

    await tester.tap(find.text(EditorStrings.outlineExpandAll));
    await tester.pumpAndSettle();
    expect(_inOutline('第一节'), findsOneWidget);
    expect(_inOutline('第二节'), findsOneWidget);
    expect(find.text(EditorStrings.outlineCollapseAll), findsOneWidget);
  });

  testWidgets('折叠某标题后仍可点击其兄弟标题跳转', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    await _switchTo(tester, EditorStrings.modeSource);
    await _openOutline(tester);

    await tester.tap(find.text(EditorStrings.outlineCollapseAll));
    await tester.pumpAndSettle();
    await tester.tap(_inOutline('第二章'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(_content.substring(field.controller!.selection.baseOffset), startsWith('第二章'));
  });

  testWidgets('全部折叠后把光标移到被隐藏的子标题，大纲自动展开上级', (tester) async {
    await _pumpEditor(tester, const Size(1400, 900));
    // 切到源码，把光标放进第二章的「第二节」（被折叠后不可见）。
    await _switchTo(tester, EditorStrings.modeSource);
    final secondSection = _content.indexOf('## 第二节');
    final content = tester.widget<TextField>(find.byType(TextField).last);
    content.controller!.selection = TextSelection.collapsed(offset: secondSection);

    await _openOutline(tester);
    await tester.tap(find.text(EditorStrings.outlineCollapseAll));
    await tester.pumpAndSettle();
    expect(_inOutline('第二节'), findsNothing);

    // 光标移出去再移回来，触发一次活动标题变化。
    content.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    content.controller!.selection = TextSelection.collapsed(offset: secondSection);
    await tester.pumpAndSettle();

    // 上级「第二章」被自动展开，活动标题可见且可点。
    expect(_inOutline('第二节'), findsOneWidget);
    await tester.tap(_inOutline('第二节'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField).last);
    expect(field.controller!.selection.baseOffset, greaterThan(0));
  });

  testWidgets('没有子标题的扁平大纲不显示折叠按钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://127.0.0.1:5055',
              password: 'pw',
              httpClient: MockClient(
                (request) async => _json({
                  'id': 'note:flat',
                  'title': '扁平笔记',
                  'content': '# 甲\n\n正文\n\n# 乙\n\n正文\n',
                  'note_type': 'human',
                }),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:flat')),
      ),
    );
    await tester.pumpAndSettle();
    await _openOutline(tester);

    expect(find.text(EditorStrings.outlineCollapseAll), findsNothing);
    expect(
      find.descendant(
        of: find.byType(NotesOutlinePanel),
        matching: find.byIcon(Icons.chevron_right_rounded),
      ),
      findsNothing,
    );
    expect(_inOutline('甲'), findsOneWidget);
    expect(_inOutline('乙'), findsOneWidget);
  });

  testWidgets('CRLF 行尾的标题也出现在大纲里（混用行尾不丢最后几个 H4）', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);

    // 复现「2026年11月工作记录」：正文前段是 LF，最后几条 H4 是 CRLF。
    // 旧解析用 `[ \t]*$` 收尾，Dart 的 `$` 不允许在 `\r` 前结束匹配，
    // 这几个 CRLF 标题会被整行丢掉。
    const content = '# 11-24\r\n\n'
        '## 1.调试开发板\n\n'
        '#### 1.第一条 LF 结论\n\n'
        '正文\n\n'
        '#### 2.第二条 CRLF 结论\r\n\n'
        '正文\r\n\n'
        '#### 3.第三条 CRLF 结论\r\n';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://127.0.0.1:5055',
              password: 'pw',
              httpClient: MockClient(
                (request) async => _json({
                  'id': 'note:crlf',
                  'title': '混用行尾的笔记',
                  'content': content,
                  'note_type': 'human',
                }),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:crlf')),
      ),
    );
    await tester.pumpAndSettle();
    await _openOutline(tester);

    expect(find.text(EditorStrings.outlineCount(5)), findsOneWidget);
    expect(find.text('H4'), findsNWidgets(3));
    expect(_inOutline('2.第二条 CRLF 结论'), findsOneWidget);
    expect(_inOutline('3.第三条 CRLF 结论'), findsOneWidget);
    // 展示文本不带行尾 `\r`。
    expect(find.textContaining('\r'), findsNothing);
  });

  testWidgets('没有标题的笔记显示大纲空状态', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(
              baseUrl: 'http://127.0.0.1:5055',
              password: 'pw',
              httpClient: MockClient(
                (request) async => _json({
                  'id': 'note:plain',
                  'title': '无标题笔记',
                  'content': '只有正文，没有小标题。\n',
                  'note_type': 'human',
                }),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:plain')),
      ),
    );
    await tester.pumpAndSettle();
    await _openOutline(tester);

    expect(find.text(EditorStrings.outlineEmptyTitle), findsOneWidget);
    expect(find.text(EditorStrings.outlineEmptyMessage), findsOneWidget);
  });
}

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

/// 每个标题下垫足够多的正文，让后文必须滚动才能看到。
String _filler(String label) =>
    List.generate(18, (i) => '$label第 ${i + 1} 行正文。').join('\n\n');

/// 带「目录」的笔记：目录是普通 Markdown 锚点链接（`[标题](#标题)`），
/// 不是大纲面板，也不是双链。
final String _content = '''
# 用 i2c-tools 操作 XS9922B

## 0. 目录

- [1. 准备段](#1-准备段每条命令前先跑一次)
- [2. 五个基本动作](#2-五个基本动作记住这五条就够用)
- [3. 场景 S1](#3-场景-s1确认芯片在线--读芯片-id)
- [9. 不存在的章节](#9-不存在的章节)

---

## 1. 准备段（每条命令前先跑一次）

${_filler('准备段')}

## 2. 五个基本动作（记住这五条就够用）

${_filler('基本动作')}

## 3. 场景 S1：确认芯片在线 + 读芯片 ID

${_filler('场景')}
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
        'title': '目录跳转演示',
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

/// 正文滚动位置：取所有 Scrollable 里最大的 pixels（大纲侧栏、工具条等
/// 内部滚动都是 0，正文才是真正滚动的那个）。
double _bodyScroll(WidgetTester tester) {
  var max = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = tester.state<ScrollableState>(find.byWidget(element.widget));
    if (state.position.pixels > max) max = state.position.pixels;
  }
  return max;
}

/// 目录里的第 [index] 个链接（渲染成富文本的可点片段，用文字定位）。
Finder _tocLink(String text) => find.text(text, findRichText: true).first;

void main() {
  testWidgets('实时预览点目录锚点，正文滚到对应标题', (tester) async {
    await _pumpEditor(tester, const Size(1000, 700));
    expect(_bodyScroll(tester), 0);

    await tester.tap(_tocLink('2. 五个基本动作'));
    await tester.pumpAndSettle();

    expect(_bodyScroll(tester), greaterThan(0));
    // 滚动后目标标题确实进到视口里（而不是滚到别处）。
    expect(find.text('2. 五个基本动作（记住这五条就够用）'), findsWidgets);
  });

  testWidgets('阅读视图点目录锚点，正文滚到对应标题', (tester) async {
    await _pumpEditor(tester, const Size(1000, 700));
    await _switchTo(tester, EditorStrings.modeReading);
    expect(_bodyScroll(tester), 0);

    await tester.tap(_tocLink('3. 场景 S1'));
    await tester.pumpAndSettle();

    expect(_bodyScroll(tester), greaterThan(0));
  });

  testWidgets('目录锚点指向不存在的标题时给出提示，不乱跳', (tester) async {
    await _pumpEditor(tester, const Size(1000, 700));
    await tester.tap(_tocLink('9. 不存在的章节'));
    // 提示是顶部横幅（AnimatedSwitcher 淡入），不能 pumpAndSettle：
    // 它的自动消失定时器会被一次追平，横幅还没断言就没了。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text(EditorStrings.anchorNotFound('9. 不存在的章节')), findsOneWidget);
    expect(_bodyScroll(tester), 0);
  });

  testWidgets('没传 onTapAnchor 时点锚点静默忽略（只读来源正文等场景）', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MarkdownView(content: '[跳到第二节](#第二节)\n\n## 第二节\n\n正文'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_tocLink('跳到第二节'));
    await tester.pumpAndSettle();
    // 没有跳转回调就什么也不做：不抛异常、也不去打开系统浏览器。
    expect(find.text(EditorStrings.anchorNotFound('第二节')), findsNothing);
  });
}

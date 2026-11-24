import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

/// 记录请求的离线后端：GET 返回一条笔记，PUT 原样返回。
({ApiClient client, List<http.Request> requests}) _fakeClient() {
  final requests = <http.Request>[];
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'id': 'note:demo',
          'title': body['title'],
          'content': body['content'],
          'note_type': 'human',
          'updated': '2026-11-23 03:00:00+00:00',
        });
      }
      return _json({
        'id': 'note:demo',
        'title': '演示笔记',
        'content': '# 标题\n\n正文内容\n',
        'note_type': 'human',
        'updated': '2026-11-22 03:00:00+00:00',
      });
    }),
  );
  return (client: client, requests: requests);
}

Future<void> _pumpEditor(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final fake = _fakeClient();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake.client)],
      child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
    ),
  );
  await tester.pumpAndSettle();
}

/// 通过视图模式菜单切换视图。
Future<void> _switchTo(WidgetTester tester, String modeLabel) async {
  await tester.tap(find.byTooltip(EditorStrings.switchMode));
  await tester.pumpAndSettle();
  await tester.tap(find.text(modeLabel).last);
  await tester.pumpAndSettle();
}

Future<void> _switchToReading(WidgetTester tester) =>
    _switchTo(tester, EditorStrings.modeReading);

void main() {
  testWidgets('宽窗口阅读视图左右分栏：左边渲染、右边 Markdown 源码', (tester) async {
    await _pumpEditor(tester, const Size(1280, 820));
    await _switchToReading(tester);

    expect(find.text(EditorStrings.paneSource), findsOneWidget);
    // 右侧一栏是原始 Markdown（带 # 与源码原文），左侧渲染态不会出现 `# `。
    expect(find.textContaining('# 标题'), findsOneWidget);
  });

  testWidgets('窄窗口阅读视图只有单栏，不显示源码对照', (tester) async {
    await _pumpEditor(tester, const Size(520, 880));
    await _switchToReading(tester);

    expect(find.text(EditorStrings.paneSource), findsNothing);
  });

  testWidgets('Ctrl+S 直接保存，无需点按钮', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 800);
    addTearDown(tester.view.reset);

    final fake = _fakeClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(fake.client)],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
      ),
    );
    await tester.pumpAndSettle();
    await _switchTo(tester, EditorStrings.modeSource);

    // 修改正文后按 Ctrl+S。
    await tester.tap(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, '# 改过的正文\n');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(fake.requests.any((request) => request.method == 'PUT'), isTrue);
    expect(find.text(EditorStrings.savedToast), findsOneWidget);

    // 保存提示是顶部轻横幅，不再用底部 SnackBar 遮住正在编辑的正文。
    expect(find.byType(SnackBar), findsNothing);
    expect(
      tester.getTopLeft(find.text(EditorStrings.savedToast)).dy,
      lessThan(200),
    );

    // 自动消失。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(EditorStrings.savedToast), findsNothing);
  });
}

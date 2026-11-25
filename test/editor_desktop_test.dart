import 'dart:convert';

import 'package:flutter/gestures.dart';
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

  testWidgets('实时预览向上跨行拖动后复制，得到整段 Markdown 源码', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 820);
    addTearDown(tester.view.reset);

    final requests = <http.BaseRequest>[];
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:5055',
      password: 'pw',
      httpClient: MockClient((request) async {
        requests.add(request);
        return _json({
          'id': 'note:demo',
          'title': '选区演示',
          // 两段带行内标记的源码：复制结果里必须保留 `**` 等 Markdown 原文。
          'content': '# 标题\n\n第一段**加粗**正文\n\n第二段**加粗**正文\n',
          'note_type': 'human',
          'updated': '2026-11-25 03:00:00+00:00',
        });
      }),
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
      ),
    );
    await tester.pumpAndSettle();

    // 点开第二段（渲染态里 `**` 不显示），再按住左键向上拖过第一段。
    await tester.tap(find.textContaining('第二段加粗正文'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(TextField).last);
    final gesture = await tester.startGesture(
      Offset(rect.left + 120, rect.bottom - 8),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    final target = Offset(rect.left + 40, rect.top - 80);
    for (var i = 1; i <= 20; i++) {
      await gesture.moveTo(
        Offset(
          rect.left + 120,
          rect.bottom - 8 - (rect.bottom - 8 - target.dy) * i / 20,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // 复制选区：内容应是 Markdown 源码（带 `**`），且跨过段间空行。
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, contains('**加粗**'));
    expect(copied, contains('第二段'));
    // 复制本身不会改正文，也不应产生保存请求。
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
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

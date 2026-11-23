import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/sources/add_source_dialog.dart';
import 'package:pie_note/ui/sources/sources_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecretStore implements SecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body, {int statusCode = 200}) =>
    http.Response(jsonEncode(body), statusCode, headers: _jsonHeaders);

/// 记录创建来源的 multipart 请求体（http 按 UTF-8 编码字段值）。
String _bodyOf(http.Request request) {
  return utf8.decode(request.bodyBytes, allowMalformed: true);
}

/// 离线后端：创建来源立即返回 `completed`，状态轮询也返回 `completed`。
ApiClient _fakeClient({required List<http.Request> requests}) {
  var counter = 0;
  return ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path == '/api/notebooks') {
        return _json([
          {
            'id': 'notebook:demo',
            'name': '演示笔记本',
            'description': '',
            'archived': false,
            'note_count': 0,
            'source_count': 0,
          },
          {
            'id': 'notebook:other',
            'name': '另一个笔记本',
            'description': '',
            'archived': false,
            'note_count': 0,
            'source_count': 0,
          },
        ]);
      }
      if (path == '/api/sources' && request.method == 'POST') {
        counter += 1;
        return _json({
          'id': 'source:new$counter',
          'title': '新建来源',
          'topics': <String>[],
          'asset': null,
          'embedded': false,
          'embedded_chunks': 0,
          'insights_count': 0,
          'created': '2026-11-23 03:00:00+00:00',
          'updated': '2026-11-23 03:00:00+00:00',
          'full_text': null,
          'status': 'new',
          'command_id': 'command:c$counter',
          'processing_info': {'async': true, 'queued': true},
        });
      }
      if (path == '/api/sources' && request.method == 'GET') {
        return _json(<Object>[]);
      }
      if (path.endsWith('/status')) {
        return _json({
          'status': 'completed',
          'message': 'Source processing completed successfully',
          'processing_info': null,
          'command_id': 'command:c1',
        });
      }
      return _json(<Object>[]);
    }),
  );
}

Future<ProviderContainer> _openDialog(
  WidgetTester tester, {
  required List<http.Request> requests,
  String? notebookId = 'notebook:demo',
  Size size = const Size(900, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final store = ConfigStore(
    preferences: preferences,
    secretStore: _MemorySecretStore(),
  );
  await store.save(
    const AppConfig(baseUrl: 'http://127.0.0.1:5055', password: 'pw'),
  );

  final container = ProviderContainer(
    overrides: [
      configStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(_fakeClient(requests: requests)),
    ],
  );
  addTearDown(container.dispose);

  // 先让「处理中的轮询」不会挂住 pumpAndSettle：对话框用例里列表是空的。
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddSourceDialog(
                context,
                defaultNotebookId: notebookId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('文本来源：提交 multipart 表单，字段与后端约定一致', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    // 切到「文本」类型。
    await tester.tap(find.text(SourcesStrings.typeText));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, SourcesStrings.addTitleHint), '会议纪要');
    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addContentHint),
      '今天讨论了来源功能的实现。',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    final create = requests.where((r) => r.method == 'POST' && r.url.path == '/api/sources');
    expect(create, hasLength(1));
    final body = _bodyOf(create.single);
    // FastAPI 用 Form(...) 解析 multipart，字段名必须与后端一致。
    expect(body, contains('name="type"'));
    expect(body, contains('text'));
    expect(body, contains('name="content"'));
    expect(body, contains('今天讨论了来源功能的实现。'));
    expect(body, contains('name="title"'));
    expect(body, contains('会议纪要'));
    expect(body, contains('name="notebooks"'));
    // 默认勾选当前笔记本，序列化成 JSON 数组字符串。
    expect(body, contains('notebook:demo'));
    expect(body, contains('name="async_processing"'));
    expect(body, contains('true'));
    expect(body, contains('name="embed"'));
    expect(body, contains('false'));
    // 文本来源不应带文件。
    expect(body, isNot(contains('name="file"')));
  });

  testWidgets('链接来源：多行 URL 批量提交，每条一个来源', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addUrlHint),
      'https://example.com/a\nhttps://example.com/b',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    final create = requests.where((r) => r.method == 'POST' && r.url.path == '/api/sources');
    expect(create, hasLength(2));
    final bodies = create.map(_bodyOf).toList();
    expect(bodies.first, contains('https://example.com/a'));
    expect(bodies.last, contains('https://example.com/b'));
    for (final body in bodies) {
      expect(body, contains('name="type"'));
      expect(body, contains('link'));
    }
  });

  testWidgets('非法链接不提交并显示错误', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addUrlHint),
      'ftp://example.com/a',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    expect(find.text(SourcesStrings.addUrlInvalid), findsOneWidget);
    expect(
      requests.where((r) => r.method == 'POST' && r.url.path == '/api/sources'),
      isEmpty,
    );
  });

  testWidgets('文本来源缺少标题时提示必填且不提交', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    await tester.tap(find.text(SourcesStrings.typeText));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addContentHint),
      '只有正文没有标题',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    expect(find.text(SourcesStrings.addTitleRequired), findsOneWidget);
    expect(
      requests.where((r) => r.method == 'POST' && r.url.path == '/api/sources'),
      isEmpty,
    );
  });

  testWidgets('默认勾选当前笔记本，也可以取消或追加其它笔记本', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    // 当前笔记本默认选中。
    final current = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '演示笔记本'),
    );
    expect(current.selected, isTrue);

    // 再勾一个笔记本。
    await tester.tap(find.widgetWithText(FilterChip, '另一个笔记本'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addUrlHint),
      'https://example.com/a',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    final body = _bodyOf(
      requests.firstWhere((r) => r.method == 'POST' && r.url.path == '/api/sources'),
    );
    expect(body, contains('notebook:demo'));
    expect(body, contains('notebook:other'));
  });

  testWidgets('开启向量化后 embed 字段为 true', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    await tester.tap(find.text(SourcesStrings.addEmbedLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addUrlHint),
      'https://example.com/a',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pumpAndSettle();

    final body = _bodyOf(
      requests.firstWhere((r) => r.method == 'POST' && r.url.path == '/api/sources'),
    );
    expect(body, contains('name="embed"'));
    // multipart 里布尔值以字符串 "true" 提交。
    expect(RegExp(r'name="embed"\r\n\r\ntrue').hasMatch(body), isTrue);
  });

  testWidgets('提交后进入进度态并轮询状态接口', (tester) async {
    final requests = <http.Request>[];
    await _openDialog(tester, requests: requests);

    await tester.enterText(
      find.widgetWithText(TextField, SourcesStrings.addUrlHint),
      'https://example.com/a',
    );
    await tester.tap(find.text(SourcesStrings.addSubmit));
    await tester.pump(); // 提交中
    await tester.pump(const Duration(milliseconds: 100));

    // 提交后对话框切换到进度态（不再显示表单的「取消」按钮）。
    expect(find.text(SourcesStrings.addClose), findsOneWidget);

    // 推进一个轮询周期，状态接口应被调用。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.url.path.endsWith('/status')),
      isNotEmpty,
    );
  });
}

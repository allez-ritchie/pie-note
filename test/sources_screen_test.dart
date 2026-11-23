import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/api_models.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/sources/source_detail_sheet.dart';
import 'package:pie_note/ui/sources/source_meta.dart';
import 'package:pie_note/ui/sources/sources_screen.dart';
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

Map<String, dynamic> _source({
  required String id,
  required String title,
  String? status,
  String? error,
  String? url,
  String? filePath,
  String? fullText,
  int insights = 0,
  bool embedded = false,
}) {
  return {
    'id': id,
    'title': title,
    'topics': <String>[],
    'asset': {'file_path': filePath, 'url': url},
    'embedded': embedded,
    'embedded_chunks': embedded ? 3 : 0,
    'insights_count': insights,
    'created': '2026-11-20 03:00:00+00:00',
    'updated': '2026-11-22 03:00:00+00:00',
    'full_text': fullText,
    'status': status,
    'processing_info': error == null ? null : {'error': error},
  };
}

/// 离线后端：来源列表 + 状态 + 删除，记录请求供断言。
ApiClient _fakeClient({
  required List<Map<String, dynamic>> sources,
  List<http.Request>? requests,
}) {
  return ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      requests?.add(request);
      final path = request.url.path;
      if (path == '/api/notebooks') {
        return _json([
          {
            'id': 'notebook:demo',
            'name': '演示笔记本',
            'description': '',
            'archived': false,
            'note_count': 1,
            'source_count': sources.length,
          },
        ]);
      }
      if (path == '/api/sources' && request.method == 'GET') {
        return _json(sources);
      }
      if (path.startsWith('/api/sources/') && path.endsWith('/status')) {
        final id = Uri.decodeComponent(
          path.substring('/api/sources/'.length, path.length - '/status'.length),
        );
        final source = sources.where((s) => s['id'] == id).firstOrNull;
        return _json({
          'status': source?['status'] ?? 'completed',
          'message': 'done',
          'processing_info': source?['processing_info'],
          'command_id': 'command:dummy',
        });
      }
      if (path.startsWith('/api/sources/') && request.method == 'DELETE') {
        return _json({'message': 'Source deleted successfully'});
      }
      if (path.startsWith('/api/sources/') && path.endsWith('/insights')) {
        return _json(<Object>[]);
      }
      if (path.startsWith('/api/sources/')) {
        final id = Uri.decodeComponent(path.substring('/api/sources/'.length));
        return _json({
          ...sources.firstWhere((s) => s['id'] == id),
          'full_text': '来源正文内容。',
        });
      }
      return _json(<Object>[]);
    }),
  );
}

Future<ProviderContainer> _pumpSources(
  WidgetTester tester, {
  required List<Map<String, dynamic>> sources,
  List<http.Request>? requests,
  String? notebookId = 'notebook:demo',
  Size size = const Size(1280, 900),
  // 列表里有处理中的来源时会启动周期性轮询，`pumpAndSettle` 会一直等下去，
  // 这类用例改成手动 pump。
  bool settle = true,
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
      apiClientProvider.overrideWithValue(
        _fakeClient(sources: sources, requests: requests),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: SourcesScreen(title: '演示笔记本', notebookId: notebookId),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
  return container;
}

void main() {
  testWidgets('来源列表渲染标题与状态胶囊', (tester) async {
    await _pumpSources(
      tester,
      sources: [
        _source(id: 'source:a', title: '网页文章', status: 'completed', url: 'https://x.com'),
        _source(id: 'source:b', title: '一份文档', status: 'failed', error: '解析失败'),
      ],
    );

    expect(find.text('网页文章'), findsOneWidget);
    expect(find.text('一份文档'), findsOneWidget);
    expect(find.text(SourcesStrings.statusCompleted), findsOneWidget);
    expect(find.text(SourcesStrings.statusFailed), findsOneWidget);
    // 失败来源在列表里直接展示后端错误摘要。
    expect(
      find.text(SourcesStrings.processingFailed('解析失败')),
      findsOneWidget,
    );
  });

  testWidgets('空列表显示引导与添加入口', (tester) async {
    await _pumpSources(tester, sources: []);

    expect(find.text(SourcesStrings.emptyTitle), findsOneWidget);
    expect(find.text(SourcesStrings.add), findsWidgets);
  });

  testWidgets('筛选框按标题过滤，清空后恢复', (tester) async {
    await _pumpSources(
      tester,
      sources: [
        _source(id: 'source:a', title: '网页文章', status: 'completed'),
        _source(id: 'source:b', title: '一份文档', status: 'completed'),
      ],
    );

    await tester.enterText(find.byType(TextField).first, '文档');
    await tester.pumpAndSettle();
    expect(find.text('一份文档'), findsOneWidget);
    expect(find.text('网页文章'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    expect(find.text('网页文章'), findsOneWidget);
  });

  testWidgets('删除来源先二次确认，确认后调用 DELETE 并刷新列表', (tester) async {
    final requests = <http.Request>[];
    await _pumpSources(
      tester,
      sources: [
        _source(id: 'source:a', title: '网页文章', status: 'completed'),
      ],
      requests: requests,
    );

    // 打开列表项右侧的「更多」菜单。
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SourcesStrings.delete));
    await tester.pumpAndSettle();

    expect(find.text(SourcesStrings.deleteTitle), findsOneWidget);
    // 取消：不发请求。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      requests.where((r) => r.method == 'DELETE'),
      isEmpty,
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SourcesStrings.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SourcesStrings.delete).last);
    await tester.pumpAndSettle();

    final deletes = requests.where((r) => r.method == 'DELETE').toList();
    expect(deletes, hasLength(1));
    expect(deletes.single.url.path, '/api/sources/source%3Aa');
  });

  testWidgets('失败来源可从菜单重新提交处理', (tester) async {
    final requests = <http.Request>[];
    await _pumpSources(
      tester,
      sources: [
        _source(id: 'source:b', title: '一份文档', status: 'failed', error: '解析失败'),
      ],
      requests: requests,
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(SourcesStrings.retry));
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.method == 'POST' && r.url.path.endsWith('/retry')),
      hasLength(1),
    );
  });

  testWidgets('点击来源打开详情弹窗并加载正文', (tester) async {
    await _pumpSources(
      tester,
      sources: [
        _source(id: 'source:a', title: '网页文章', status: 'completed', url: 'https://x.com'),
      ],
    );

    await tester.tap(find.text('网页文章'));
    await tester.pumpAndSettle();

    expect(find.text(SourcesStrings.detailContent), findsOneWidget);
    expect(find.text('来源正文内容。'), findsOneWidget);
    expect(find.text(SourcesStrings.detailNoInsights), findsOneWidget);
  });

  testWidgets('处理中的来源会启动 3 秒轮询刷新', (tester) async {
    final requests = <http.Request>[];
    final sources = <Map<String, dynamic>>[
      _source(id: 'source:a', title: '处理中文章', status: 'running'),
    ];
    await _pumpSources(
      tester,
      sources: sources,
      requests: requests,
      settle: false,
    );

    final listCallsBefore =
        requests.where((r) => r.method == 'GET' && r.url.path == '/api/sources').length;

    // 推进 3 秒，轮询应再拉一次列表。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final listCallsAfter =
        requests.where((r) => r.method == 'GET' && r.url.path == '/api/sources').length;

    expect(listCallsAfter, greaterThan(listCallsBefore));

    // 让来源变成已完成，轮询应停止（不再产生新的列表请求）。
    sources[0] = _source(
      id: 'source:a',
      title: '处理中文章',
      status: 'completed',
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final settledCalls =
        requests.where((r) => r.method == 'GET' && r.url.path == '/api/sources').length;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(
      requests.where((r) => r.method == 'GET' && r.url.path == '/api/sources').length,
      settledCalls,
    );
  });

  group('SourceMeta', () {
    test('处理中的状态文案与元信息行', () {
      final source = Source.fromJson(
        _source(
          id: 'source:a',
          title: 'x',
          status: 'running',
          insights: 2,
          embedded: true,
        ),
      );
      expect(source.isProcessing, isTrue);
      expect(SourceMeta.statusLabel(source), SourcesStrings.statusProcessing);
      expect(
        SourceMeta.metaLine(source),
        contains('2 ${SourcesStrings.insightsCount}'),
      );
      expect(SourceMeta.metaLine(source), contains(SourcesStrings.embedded));
      // 处理中不用状态图标，改用进度圈。
      expect(SourceMeta.statusIcon(source.status), isNull);
    });

    test('已完成的链接来源图标与文案', () {
      final source = Source.fromJson(
        _source(id: 'source:b', title: 'y', status: 'completed', url: 'https://x.com'),
      );
      expect(source.kind, SourceKind.link);
      expect(sourceKindIcon(source.kind), Icons.link_rounded);
      expect(sourceKindLabel(source.kind), SourcesStrings.typeLinkIcon);
      expect(SourceMeta.statusLabel(source), SourcesStrings.statusCompleted);
    });

    test('来源模型的容错与展示名', () {
      final source = Source.fromJson({
        'id': 'source:c',
        'title': null,
        'asset': {'file_path': '/app/data/uploads/报告.pdf', 'url': null},
        'status': null,
        'created': '2026-11-20 03:00:00+00:00',
        'updated': null,
      });
      expect(source.kind, SourceKind.upload);
      expect(source.status, SourceStatus.unknown);
      // 标题为空时回退到文件名。
      expect(source.displayTitle, '报告.pdf');
      expect(source.updated, isNull);
    });

    test('失败状态带错误摘要', () {
      final source = Source.fromJson(
        _source(id: 'source:d', title: 'z', status: 'failed', error: '抽取失败'),
      );
      expect(source.hasFailed, isTrue);
      expect(source.processingError, '抽取失败');
      expect(SourceMeta.statusLabel(source), SourcesStrings.statusFailed);
      expect(SourceMeta.statusIcon(source.status), Icons.error_outline_rounded);
    });
  });
}

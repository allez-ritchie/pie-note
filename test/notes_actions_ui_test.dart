import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/data/note_pin_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/notebooks/notes_screen.dart';
import 'package:pie_note/ui/notebooks/notes_strings.dart';
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

http.Response _json(Object? body, {int statusCode = 200}) => http.Response(
      body == null ? '' : jsonEncode(body),
      statusCode,
      headers: _jsonHeaders,
    );

/// 离线后端：两个笔记本、三条笔记；记录所有请求便于断言副作用。
ApiClient _fakeClient({required List<http.Request> requests}) {
  final notes = <Map<String, dynamic>>[
    {
      'id': 'note:a',
      'title': '笔记 A',
      'content': '# 笔记 A\n\n第一篇正文。\n',
      'note_type': 'human',
      'created': '2026-11-20 03:00:00+00:00',
      'updated': '2026-11-22 03:00:00+00:00',
    },
    {
      'id': 'note:b',
      'title': '笔记 B',
      'content': '笔记 B 正文\n',
      'note_type': 'human',
      'created': '2026-11-19 03:00:00+00:00',
      'updated': '2026-11-21 03:00:00+00:00',
    },
    {
      'id': 'note:c',
      'title': '笔记 C',
      'content': '笔记 C 正文\n',
      'note_type': 'human',
      'created': '2026-11-18 03:00:00+00:00',
      'updated': '2026-11-20 03:00:00+00:00',
    },
  ];
  var created = 0;
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
            'note_count': 3,
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
      if (path == '/api/notebooks/notebook%3Aother' ||
          path == '/api/notebooks/notebook:other') {
        return _json({
          'id': 'notebook:other',
          'name': '另一个笔记本',
          'description': '',
          'archived': false,
          'note_count': 0,
          'source_count': 0,
        });
      }
      if (path == '/api/notes' && request.method == 'GET') {
        return _json(notes);
      }
      if (path == '/api/notes' && request.method == 'POST') {
        created++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'id': 'note:new-$created',
          'title': body['title'] ?? '',
          'content': body['content'] ?? '',
          'note_type': body['note_type'] ?? 'human',
          'created': '2026-11-23 03:00:00+00:00',
          'updated': '2026-11-23 03:00:00+00:00',
        });
      }
      if (path.startsWith('/api/notes/')) {
        final id = Uri.decodeComponent(path.substring('/api/notes/'.length));
        if (request.method == 'DELETE') {
          notes.removeWhere((note) => note['id'] == id);
          return _json({'message': 'Note deleted successfully'});
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final index = notes.indexWhere((note) => note['id'] == id);
          if (index >= 0) notes[index] = {...notes[index], ...body};
          return _json(notes.firstWhere((note) => note['id'] == id));
        }
        return _json(notes.firstWhere((note) => note['id'] == id));
      }
      if (path == '/api/sources') return _json(<Object>[]);
      if (path == '/api/chat/sessions') return _json(<Object>[]);
      return _json(<Object>[]);
    }),
  );
}

Future<ProviderContainer> _pumpNotes(
  WidgetTester tester, {
  List<http.Request>? requests,
  Size size = const Size(560, 900),
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
      apiClientProvider.overrideWithValue(_fakeClient(requests: requests ?? [])),
      notePinStoreProvider.overrideWithValue(NotePinStore(preferences: preferences)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: NotesScreen(title: '演示笔记本', notebookId: 'notebook:demo'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 某条笔记卡片上的⋯按钮。
Finder _moreOf(String title) => find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(Card),
      ),
      matching: find.byTooltip(NotesStrings.moreTooltip),
    );

void main() {
  testWidgets('⋯ 菜单包含重命名 / 移至笔记本 / 置顶 / 创建副本 / 删除', (tester) async {
    await _pumpNotes(tester);

    await tester.tap(_moreOf('笔记 A'));
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text(NotesStrings.moveToNotebook), findsOneWidget);
    expect(find.text(NotesStrings.pin), findsOneWidget);
    expect(find.text(NotesStrings.duplicate), findsOneWidget);
    expect(find.text(NotesStrings.delete), findsOneWidget);
    // 置顶只在本机生效，必须提示。
    expect(find.text(NotesStrings.pinLocalOnlyHint), findsOneWidget);
  });

  testWidgets('重命名：同步改写正文首行标题并发 PUT', (tester) async {
    final requests = <http.Request>[];
    await _pumpNotes(tester, requests: requests);

    await tester.tap(_moreOf('笔记 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '新标题');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final put = requests.lastWhere((request) => request.method == 'PUT');
    final body = jsonDecode(put.body) as Map<String, dynamic>;
    expect(body['title'], '新标题');
    // 首行是 `# 笔记 A`，应同步改写且保留其余正文。
    expect(body['content'], '# 新标题\n\n第一篇正文。\n');
    expect(find.textContaining(NotesStrings.renamedToast), findsOneWidget);
  });

  testWidgets('置顶：写入本机偏好，置顶笔记排到最前并带图钉', (tester) async {
    final container = await _pumpNotes(tester);

    // 逐字点击最后一条的「置顶」。
    await tester.tap(_moreOf('笔记 C'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.pin));
    await tester.pumpAndSettle();

    expect(
      container.read(pinnedNotesProvider).valueOrNull,
      contains('note:c'),
    );
    expect(find.text(NotesStrings.pinnedSection), findsOneWidget);
    expect(find.text(NotesStrings.othersSection), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsWidgets);

    // 再来一次应取消置顶。
    await tester.tap(_moreOf('笔记 C'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.unpin));
    await tester.pumpAndSettle();
    expect(
      container.read(pinnedNotesProvider).valueOrNull,
      isNot(contains('note:c')),
    );
  });

  testWidgets('创建副本：先取正文再以「标题 副本」创建', (tester) async {
    final requests = <http.Request>[];
    await _pumpNotes(tester, requests: requests);

    await tester.tap(_moreOf('笔记 B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.duplicate));
    await tester.pumpAndSettle();

    final post = requests.lastWhere((request) => request.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['title'], '笔记 B 副本');
    expect(body['content'], '笔记 B 正文\n');
    expect(find.text(NotesStrings.duplicateToast), findsOneWidget);
  });

  testWidgets('移至笔记本：复制到目标笔记本后删除原笔记', (tester) async {
    final requests = <http.Request>[];
    await _pumpNotes(tester, requests: requests);

    await tester.tap(_moreOf('笔记 C'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.moveToNotebook));
    await tester.pumpAndSettle();

    await tester.tap(find.text('另一个笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.moveConfirm));
    await tester.pumpAndSettle();

    final post = requests.lastWhere((request) => request.method == 'POST');
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['notebook_id'], 'notebook:other');
    expect(body['title'], '笔记 C');
    expect(body['content'], '笔记 C 正文\n');
    expect(
      requests.map((request) => '${request.method} ${request.url.path}'),
      contains('DELETE /api/notes/note%3Ac'),
    );
    // 原笔记已删除：刷新后本列表里不再有它。
    expect(find.text(NotesStrings.movedToToast('另一个笔记本')), findsOneWidget);
    expect(find.text('笔记 C'), findsNothing);
  });

  testWidgets('多选：全选 / 反选 / 批量删除都按选中集合生效', (tester) async {
    final requests = <http.Request>[];
    final container = await _pumpNotes(tester, requests: requests);

    await tester.tap(find.byTooltip(NotesStrings.selectTooltip));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(0)), findsOneWidget);

    // 全选（只看可见列表）。
    await tester.tap(find.byTooltip(NotesStrings.selectAll));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(3)), findsOneWidget);

    // 反选后清空选择。
    await tester.tap(find.byTooltip(NotesStrings.invertSelection));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(0)), findsOneWidget);

    // 再全选后批量删除。
    await tester.tap(find.byTooltip(NotesStrings.selectAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(NotesStrings.delete));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.batchDeleteMessage(3)), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(NotesStrings.delete),
      ),
    );
    await tester.pumpAndSettle();

    final deletes = requests
        .where((request) => request.method == 'DELETE')
        .map((request) => request.url.path)
        .toSet();
    expect(deletes, hasLength(3));
    expect(find.text(NotesStrings.batchDeletedToast(3)), findsOneWidget);
    // 删除完成后自动退出多选。
    expect(container.read(pinnedNotesProvider).valueOrNull, isNotNull);
    expect(find.text(NotesStrings.selectedCount(0)), findsNothing);
  });

  testWidgets('窄屏（360x640）：多选底栏不溢出，批量条 4 个操作可用', (tester) async {
    await _pumpNotes(tester, size: const Size(360, 640));

    await tester.longPress(find.text('笔记 A'));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(1)), findsOneWidget);

    // 底栏四个操作都在，且没有 RenderFlex 溢出（溢出会让测试失败）。
    for (final label in [
      NotesStrings.pin,
      NotesStrings.moveToNotebook,
      NotesStrings.batchDuplicate,
      NotesStrings.delete,
    ]) {
      expect(find.text(label), findsWidgets, reason: '缺少批量操作：$label');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按一行进入多选，点另一行切换选中', (tester) async {
    await _pumpNotes(tester);

    await tester.longPress(find.text('笔记 A'));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(1)), findsOneWidget);

    await tester.tap(find.text('笔记 B'));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(2)), findsOneWidget);

    await tester.tap(find.text('笔记 B'));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(1)), findsOneWidget);

    // 关闭按钮退出多选。
    await tester.tap(find.byTooltip(NotesStrings.exitSelection));
    await tester.pumpAndSettle();
    expect(find.text(NotesStrings.selectedCount(1)), findsNothing);
    expect(find.text('笔记 A'), findsOneWidget);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/state/workspace.dart';
import 'package:pie_note/ui/home/desktop_tab_strip.dart';
import 'package:pie_note/ui/home/home_shell.dart';
import 'package:pie_note/ui/home/mobile_floating_bar.dart';
import 'package:pie_note/ui/home/mobile_tab_overview.dart';
import 'package:pie_note/ui/home/workspace_strings.dart';
import 'package:pie_note/ui/notebooks/notes_screen.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';
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

http.Response _json(Object? body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

/// 离线后端：两个笔记本、三条笔记；PUT 原样返回。
ApiClient _fakeClient({List<http.Request>? requests}) {
  final notes = [
    {
      'id': 'note:a',
      'title': '笔记 A',
      'content': '# 笔记 A\n\n第一篇正文。\n',
      'note_type': 'human',
      'notebook_id': 'notebook:demo',
      'updated': '2026-11-22 03:00:00+00:00',
    },
    {
      'id': 'note:b',
      'title': '笔记 B',
      'content': '# 笔记 B\n\n第二篇正文。\n',
      'note_type': 'human',
      'notebook_id': 'notebook:demo',
      'updated': '2026-11-21 03:00:00+00:00',
    },
    {
      'id': 'note:c',
      'title': '笔记 C',
      'content': '# 笔记 C\n\n第三篇正文。\n',
      'note_type': 'human',
      'notebook_id': 'notebook:other',
      'updated': '2026-11-20 03:00:00+00:00',
    },
  ];
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
            'note_count': 2,
            'source_count': 0,
          },
        ]);
      }
      if (path == '/api/notes') {
        return _json(notes);
      }
      if (path.startsWith('/api/notes/')) {
        // 笔记 id 里带冒号，路径会被编码成 note%3Aa。
        final id = Uri.decodeComponent(path.substring('/api/notes/'.length));
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final existing = notes.firstWhere((note) => note['id'] == id);
          return _json({...existing, ...body});
        }
        return _json(notes.firstWhere((note) => note['id'] == id));
      }
      return _json(<Object>[]);
    }),
  );
}

Future<ConfigStore> _configuredStore() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();
  final store = ConfigStore(
    preferences: preferences,
    secretStore: _MemorySecretStore(),
  );
  await store.save(
    const AppConfig(baseUrl: 'http://127.0.0.1:5055', password: 'pw'),
  );
  return store;
}

Future<ProviderContainer> _pumpShell(
  WidgetTester tester,
  Size size, {
  List<http.Request>? requests,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final store = await _configuredStore();
  final container = ProviderContainer(
    overrides: [
      configStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(_fakeClient(requests: requests)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeShell()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 笔记列表里的某条笔记（避开标签条上的同名标题）。
Finder _noteTile(String title) =>
    find.descendant(of: find.byType(NotesScreen), matching: find.text(title));

/// 桌面标签条的标签标题文本。
Finder _chipTitle(String title) => find.descendant(
  of: find.byType(DesktopTabStrip),
  matching: find.text(title),
);

void main() {
  testWidgets('桌面端：点笔记打开标签页，标签条显示标题并可切回', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    // 初始只有一个「笔记本」标签页。
    expect(find.byType(DesktopTabStrip), findsOneWidget);
    expect(_chipTitle('笔记本'), findsOneWidget);

    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();

    final state = container.read(workspaceProvider);
    expect(state.tabs, hasLength(2));
    expect(state.activeTab!.kind, WorkspaceTabKind.note);
    expect(_chipTitle('笔记 A'), findsOneWidget);
    expect(find.byType(NoteEditorScreen), findsOneWidget);

    // 点标签条回到笔记本页。
    await tester.tap(_chipTitle('笔记本'));
    await tester.pumpAndSettle();
    expect(
      container.read(workspaceProvider).activeTab!.kind,
      WorkspaceTabKind.notebooks,
    );
    expect(find.text('全部笔记'), findsWidgets);
  });

  testWidgets('桌面端：已有标签页的笔记再次点击只切换，不会重复开标签', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();
    await tester.tap(_chipTitle('笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();

    final state = container.read(workspaceProvider);
    expect(state.tabs.where((tab) => tab.isNote), hasLength(1));
    expect(state.activeTab!.title, '笔记 A');
  });

  testWidgets('桌面端：关闭标签页的 × 后标签消失，回到临近标签页', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider).tabs, hasLength(2));

    // 标签条上当前激活的标签一定显示关闭按钮；取最后一个（笔记标签）。
    await tester.tap(
      find
          .descendant(
            of: find.byType(DesktopTabStrip),
            matching: find.byTooltip(WorkspaceStrings.closeTab),
          )
          .last,
    );
    await tester.pumpAndSettle();

    final state = container.read(workspaceProvider);
    expect(state.tabs, hasLength(1));
    expect(state.activeTab!.kind, WorkspaceTabKind.notebooks);
    expect(find.byType(NoteEditorScreen), findsNothing);
  });

  testWidgets('桌面端：编辑中的标签关闭前弹「未保存」确认，取消后标签仍在', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();

    // 切到源码模式改一个字，制造脏状态。
    await tester.tap(find.byTooltip(EditorStrings.switchMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(EditorStrings.modeSource).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '# 笔记 A\n\n改过的正文。\n');
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider).activeTab!.dirty, isTrue);

    await tester.tap(
      find
          .descendant(
            of: find.byType(DesktopTabStrip),
            matching: find.byTooltip(WorkspaceStrings.closeTab),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(find.text(WorkspaceStrings.closeDirtyTitle), findsOneWidget);
    await tester.tap(find.text(WorkspaceStrings.closeDirtyCancel));
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).tabs, hasLength(2));
    expect(container.read(workspaceProvider).activeTab!.dirty, isTrue);
  });

  testWidgets('手机端：底部胶囊工具栏打开多标签总览，可切换与关闭', (tester) async {
    final container = await _pumpShell(tester, const Size(430, 880));

    expect(find.byType(MobileFloatingBar), findsOneWidget);
    expect(find.byType(DesktopTabStrip), findsNothing);

    // 打开一个笔记本 → 笔记列表标签页，再打开一条笔记。
    await tester.tap(find.text('演示笔记本'));
    await tester.pumpAndSettle();
    await tester.tap(_noteTile('笔记 A'));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider).tabs, hasLength(3));

    // 打开标签总览。
    await tester.tap(find.byTooltip(WorkspaceStrings.tabListTooltip));
    await tester.pumpAndSettle();
    expect(find.byType(MobileTabOverview), findsOneWidget);
    expect(find.text(WorkspaceStrings.tabCount(3)), findsOneWidget);

    // 点「笔记本」卡片切回并退出总览。
    await tester.tap(find.text('笔记本').last);
    await tester.pumpAndSettle();
    expect(find.byType(MobileTabOverview), findsNothing);
    expect(
      container.read(workspaceProvider).activeTab!.kind,
      WorkspaceTabKind.notebooks,
    );
  });

  testWidgets('手机端：新建按钮每次开一个草稿标签页，标题为「新建笔记」', (tester) async {
    final container = await _pumpShell(tester, const Size(430, 880));

    await tester.tap(
      find.descendant(
        of: find.byType(MobileFloatingBar),
        matching: find.byTooltip(WorkspaceStrings.newTabTooltip),
      ),
    );
    await tester.pumpAndSettle();

    final state = container.read(workspaceProvider);
    expect(state.tabs, hasLength(2));
    expect(state.activeTab!.kind, WorkspaceTabKind.note);
    expect(state.activeTab!.targetId, isNull);
    expect(state.activeTab!.title, WorkspaceStrings.newNoteTab);
  });

  testWidgets('手机端：关闭全部标签后显示空工作区引导', (tester) async {
    final container = await _pumpShell(tester, const Size(430, 880));
    final id = container.read(workspaceProvider).activeId!;

    await tester.tap(
      find.descendant(
        of: find.byType(MobileFloatingBar),
        matching: find.byTooltip(WorkspaceStrings.more),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkspaceStrings.closeAll));
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).tabs, isEmpty);
    expect(find.text(WorkspaceStrings.emptyTitle), findsOneWidget);
    expect(find.text(WorkspaceStrings.openNotebooks), findsOneWidget);

    // 引导页可以直接重新打开笔记本标签页。
    await tester.tap(find.text(WorkspaceStrings.openNotebooks));
    await tester.pumpAndSettle();
    expect(container.read(workspaceProvider).activeId, isNot(id));
  });
}

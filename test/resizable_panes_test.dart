import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/data/panel_layout_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/common/resizable_divider.dart';
import 'package:pie_note/ui/notebooks/notebooks_screen.dart';
import 'package:pie_note/ui/notes/editor_strings.dart';
import 'package:pie_note/ui/notes/note_editor_screen.dart';
import 'package:pie_note/ui/notes/notes_outline_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      final path = request.url.path;
      if (path == '/api/notebooks') {
        return _json([
          {
            'id': 'notebook:demo',
            'name': '演示笔记本',
            'description': '',
            'archived': false,
            'note_count': 1,
            'source_count': 0,
          },
        ]);
      }
      if (path == '/api/notes') {
        return _json([
          {
            'id': 'note:demo',
            'title': '演示笔记',
            'content': '正文内容',
            'note_type': 'human',
            'notebook_id': 'notebook:demo',
          },
        ]);
      }
      return _json({
        'id': 'note:demo',
        'title': '大纲演示',
        'content': '# 第一章\n\n## 第一节\n\n正文。\n',
        'note_type': 'human',
        'updated': '2026-11-24 03:00:00+00:00',
      });
    }),
  );
}

class _MemorySecretStore implements SecretStore {
  final Map<String, String> data = <String, String>{};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<ConfigStore> _configuredStore() async {
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

Future<void> _pumpNotebooks(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
}) async {
  _setSize(tester, size);
  final store = await _configuredStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(_fakeClient()),
      ],
      child: const MaterialApp(home: NotebooksScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(_fakeClient())],
      child: const MaterialApp(home: NoteEditorScreen(noteId: 'note:demo')),
    ),
  );
  await tester.pumpAndSettle();
}

double _dividerWidth(WidgetTester tester, String key) =>
    tester.widget<ResizableDivider>(find.byKey(ValueKey<String>(key))).width;

Future<void> _dragDivider(WidgetTester tester, String key, double dx) async {
  await tester.drag(find.byKey(ValueKey<String>(key)), Offset(dx, 0));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('笔记本双栏宽度可调', () {
    testWidgets('双栏中间有分隔条，拖动后左栏变宽、右侧笔记列表右移', (tester) async {
      await _pumpNotebooks(tester);

      const dividerKey = 'notebooks-pane-divider';
      final before = _dividerWidth(tester, dividerKey);
      final notesLeft = tester.getTopLeft(find.byType(NotebooksScreen)).dx;

      await _dragDivider(tester, dividerKey, 60);

      final after = _dividerWidth(tester, dividerKey);
      expect(after, greaterThan(before));
      expect(after, closeTo(before + 60, 1));
      // 左栏确实变宽了：左栏右边界（= 分隔条起点）跟着右移。
      expect(
        tester.getCenter(find.byKey(const ValueKey<String>(dividerKey))).dx,
        greaterThan(notesLeft + before),
      );
    });

    testWidgets('拖动宽度被夹在可用范围内，不会把右侧挤没', (tester) async {
      await _pumpNotebooks(tester);

      // 使劲往右拖：上限 = 窗口宽 - 右侧最小宽度。
      await _dragDivider(tester, 'notebooks-pane-divider', 2000);
      final wide = _dividerWidth(tester, 'notebooks-pane-divider');
      expect(wide, lessThanOrEqualTo(1280 - NotebooksLayout.notesMinWidth + 1));

      // 使劲往左拖：不小于左栏最小宽度。
      await _dragDivider(tester, 'notebooks-pane-divider', -2000);
      final narrow = _dividerWidth(tester, 'notebooks-pane-divider');
      expect(narrow, closeTo(NotebooksLayout.paneMinWidth, 1));
    });

    testWidgets('拖动后的宽度写入本机偏好，重新进入时沿用', (tester) async {
      await _pumpNotebooks(tester);
      await _dragDivider(tester, 'notebooks-pane-divider', 80);
      final resized = _dividerWidth(tester, 'notebooks-pane-divider');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(PanelLayoutStore.notebookPaneWidthKey),
        closeTo(resized, 0.5),
      );

      // 重建页面（模拟重新进入）：沿用记住的宽度，而不是按窗口比例重算。
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpNotebooks(tester);
      expect(
        _dividerWidth(tester, 'notebooks-pane-divider'),
        closeTo(resized, 0.5),
      );
    });

    testWidgets('双击分隔条恢复默认宽度并清掉偏好', (tester) async {
      await _pumpNotebooks(tester);
      final initial = _dividerWidth(tester, 'notebooks-pane-divider');

      await _dragDivider(tester, 'notebooks-pane-divider', 90);
      expect(
        _dividerWidth(tester, 'notebooks-pane-divider'),
        isNot(closeTo(initial, 0.5)),
      );

      // 双击：tester 的 tap 序列默认不产生 double tap，用两次间隔很短的点击。
      const divider = ValueKey<String>('notebooks-pane-divider');
      await tester.tap(find.byKey(divider));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(divider));
      await tester.pumpAndSettle();

      expect(
        _dividerWidth(tester, 'notebooks-pane-divider'),
        closeTo(initial, 0.5),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PanelLayoutStore.notebookPaneWidthKey), isNull);
    });

    testWidgets('记住的宽度超过窗口可用范围时被夹取', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PanelLayoutStore.notebookPaneWidthKey: 5000.0,
      });
      await _pumpNotebooks(tester);
      final width = _dividerWidth(tester, 'notebooks-pane-divider');
      expect(
        width,
        lessThanOrEqualTo(1280 - NotebooksLayout.notesMinWidth + 1),
      );
    });
  });

  group('大纲侧栏宽度可调', () {
    Future<void> openOutline(WidgetTester tester) async {
      await tester.tap(find.byTooltip(EditorStrings.outlineTooltip));
      await tester.pumpAndSettle();
    }

    testWidgets('宽窗口大纲侧栏左侧有分隔条，向左拖动后侧栏变宽', (tester) async {
      await _pumpEditor(tester);
      await openOutline(tester);

      const dividerKey = 'outline-pane-divider';
      expect(find.byType(NotesOutlinePanel), findsOneWidget);
      final before = _dividerWidth(tester, dividerKey);
      final panelLeft = tester.getTopLeft(find.byType(NotesOutlinePanel)).dx;

      // 分隔条在侧栏左侧：往左拖 = 侧栏变宽。
      await _dragDivider(tester, dividerKey, -60);

      final after = _dividerWidth(tester, dividerKey);
      expect(after, closeTo(before + 60, 1));
      expect(
        tester.getTopLeft(find.byType(NotesOutlinePanel)).dx,
        lessThan(panelLeft),
      );
    });

    testWidgets('侧栏宽度被夹在最小 / 最大值之间，正文不会被挤没', (tester) async {
      await _pumpEditor(tester);
      await openOutline(tester);
      const dividerKey = 'outline-pane-divider';

      await _dragDivider(tester, dividerKey, 2000);
      expect(
        _dividerWidth(tester, dividerKey),
        closeTo(OutlineLayout.minWidth, 1),
      );

      await _dragDivider(tester, dividerKey, -2000);
      expect(
        _dividerWidth(tester, dividerKey),
        lessThanOrEqualTo(OutlineLayout.maxWidth + 0.01),
      );
    });

    testWidgets('大纲宽度写入本机偏好，再次打开大纲时沿用', (tester) async {
      await _pumpEditor(tester);
      await openOutline(tester);
      await _dragDivider(tester, 'outline-pane-divider', -70);
      final resized = _dividerWidth(tester, 'outline-pane-divider');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getDouble(PanelLayoutStore.outlinePaneWidthKey),
        closeTo(resized, 0.5),
      );

      // 收起再打开：沿用记住的宽度。
      await tester.tap(find.byTooltip(EditorStrings.outlineHide));
      await tester.pumpAndSettle();
      expect(find.byType(NotesOutlinePanel), findsNothing);
      await openOutline(tester);
      expect(
        _dividerWidth(tester, 'outline-pane-divider'),
        closeTo(resized, 0.5),
      );
    });

    testWidgets('双击分隔条恢复大纲默认宽度', (tester) async {
      await _pumpEditor(tester);
      await openOutline(tester);
      const dividerKey = 'outline-pane-divider';
      final initial = _dividerWidth(tester, dividerKey);

      await _dragDivider(tester, dividerKey, -60);
      expect(_dividerWidth(tester, dividerKey), isNot(closeTo(initial, 0.5)));

      await tester.tap(find.byKey(const ValueKey<String>(dividerKey)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey<String>(dividerKey)));
      await tester.pumpAndSettle();

      expect(_dividerWidth(tester, dividerKey), closeTo(initial, 0.5));
    });
  });

  group('PanelLayoutStore', () {
    test('宽度按 key 存 / 读，null 清除，脏数据当作没有偏好', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final store = PanelLayoutStore(preferences: preferences);

      expect(await store.loadNotebookPaneWidth(), isNull);

      await store.saveNotebookPaneWidth(320);
      expect(await store.loadNotebookPaneWidth(), 320);

      await store.saveNotebookPaneWidth(null);
      expect(await store.loadNotebookPaneWidth(), isNull);

      await preferences.setString(PanelLayoutStore.outlinePaneWidthKey, 'oops');
      expect(await store.loadOutlinePaneWidth(), isNull);

      await preferences.setDouble(PanelLayoutStore.outlinePaneWidthKey, -12);
      expect(await store.loadOutlinePaneWidth(), isNull);

      // 两个 key 互不影响。
      await store.saveOutlinePaneWidth(300);
      expect(await store.loadOutlinePaneWidth(), 300);
      expect(await store.loadNotebookPaneWidth(), isNull);
    });

    test('clampWidth 处理越界与非法值', () {
      expect(
        PanelLayoutStore.clampWidth(null, fallback: 300, min: 260, max: 420),
        300,
      );
      expect(
        PanelLayoutStore.clampWidth(9999, fallback: 300, min: 260, max: 420),
        420,
      );
      expect(
        PanelLayoutStore.clampWidth(10, fallback: 300, min: 260, max: 420),
        260,
      );
      expect(
        PanelLayoutStore.clampWidth(
          double.nan,
          fallback: 300,
          min: 260,
          max: 420,
        ),
        300,
      );
    });
  });
}

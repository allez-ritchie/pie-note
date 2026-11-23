import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/config_store.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/common/layout.dart';
import 'package:pie_note/ui/home/desktop_tab_strip.dart';
import 'package:pie_note/ui/home/home_shell.dart';
import 'package:pie_note/ui/home/mobile_floating_bar.dart';
import 'package:pie_note/ui/notebooks/notebooks_screen.dart';
import 'package:pie_note/ui/notebooks/notes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存版密码存储：替代 flutter_secure_storage，避免平台通道依赖。
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

/// 完全离线的后端：笔记本 1 个、笔记 1 条，不触网。
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
  await store.save(const AppConfig(baseUrl: 'http://127.0.0.1:5055', password: 'pw'));
  return store;
}

/// 以指定逻辑尺寸渲染一个页面。
Future<void> _pumpAtSize(
  WidgetTester tester,
  Size size,
  Widget child, {
  required ConfigStore store,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        configStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(_fakeClient()),
      ],
      child: MaterialApp(home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('竖屏窄窗口用底部悬浮工具栏，且笔记本页只有单栏', (tester) async {
    final store = await _configuredStore();
    await _pumpAtSize(tester, const Size(420, 880), const HomeShell(), store: store);

    // 移动端是 Obsidian 风格的悬浮胶囊工具栏，而不是 NavigationBar。
    expect(find.byType(MobileFloatingBar), findsOneWidget);
    expect(find.byType(DesktopTabStrip), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);

    // 单栏：不内嵌笔记列表，点笔记本才打开笔记列表标签页。
    expect(find.byType(NotesScreen), findsNothing);
    expect(find.byType(NotebooksScreen), findsOneWidget);
  });

  testWidgets('横屏/桌面宽窗口用侧边导航 + 顶部标签条，笔记本页自动双栏', (tester) async {
    final store = await _configuredStore();
    await _pumpAtSize(tester, const Size(1280, 800), const HomeShell(), store: store);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(DesktopTabStrip), findsOneWidget);
    expect(find.byType(MobileFloatingBar), findsNothing);

    // 双栏：右侧直接内嵌「全部笔记」列表，无需跳转。
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text('演示笔记本'), findsOneWidget);
    expect(find.text('演示笔记'), findsOneWidget);
  });

  testWidgets('宽但高度不足（手机横屏）时退回单栏，避免双栏挤压', (tester) async {
    final store = await _configuredStore();
    await _pumpAtSize(tester, const Size(900, 420), const HomeShell(), store: store);

    expect(find.byType(NotesScreen), findsNothing);
  });

  testWidgets('双栏下点笔记本，右侧切换到该笔记本的笔记', (tester) async {
    final store = await _configuredStore();
    await _pumpAtSize(tester, const Size(1280, 800), const HomeShell(), store: store);

    await tester.tap(find.text('演示笔记本'));
    await tester.pumpAndSettle();

    final notesScreen = tester.widget<NotesScreen>(find.byType(NotesScreen));
    expect(notesScreen.notebookId, 'notebook:demo');
    // 内嵌在双栏里不显示返回按钮。
    expect(notesScreen.showBackButton, isFalse);
  });

  testWidgets('断点判定与屏幕尺寸一致', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cases = <Size, ({bool rail, bool twoPane, bool split})>{
      const Size(420, 880): (rail: false, twoPane: false, split: false),
      const Size(700, 1000): (rail: false, twoPane: false, split: false),
      const Size(900, 420): (rail: true, twoPane: false, split: true),
      const Size(1000, 700): (rail: true, twoPane: true, split: true),
      const Size(1400, 900): (rail: true, twoPane: true, split: true),
    };

    for (final entry in cases.entries) {
      tester.view.physicalSize = entry.key;
      late bool rail;
      late bool twoPane;
      late bool split;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            rail = Responsive.useSideNavigation(context);
            twoPane = Responsive.useTwoPane(context);
            split = Responsive.useEditorSplit(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(rail, entry.value.rail, reason: 'sideNavigation @ ${entry.key}');
      expect(twoPane, entry.value.twoPane, reason: 'twoPane @ ${entry.key}');
      expect(split, entry.value.split, reason: 'editorSplit @ ${entry.key}');
    }
  });
}

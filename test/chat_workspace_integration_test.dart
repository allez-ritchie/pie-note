import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/state/workspace.dart';
import 'package:pie_note/ui/chat/chat_screen.dart';
import 'package:pie_note/ui/chat/chat_strings.dart';
import 'package:pie_note/ui/home/home_shell.dart';

const String _notebookId = 'notebook:demo';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body) =>
    http.Response(jsonEncode(body), 200, headers: _jsonHeaders);

/// 只覆盖工作区外壳 + 对话页需要的接口。
ApiClient _fakeClient() => ApiClient(
      baseUrl: 'http://127.0.0.1:5055',
      password: 'pw',
      httpClient: MockClient((request) async {
        final path = Uri.decodeComponent(request.url.path);
        if (path == '/api/notebooks') {
          return _json([
            {
              'id': _notebookId,
              'name': '演示笔记本',
              'description': '',
              'archived': false,
              'note_count': 0,
              'source_count': 0,
            },
          ]);
        }
        if (path == '/api/notes' || path == '/api/sources') {
          return _json(<Object>[]);
        }
        if (path == '/api/models') {
          return _json(<Object>[
            {
              'id': 'model:a',
              'name': 'Alpha',
              'provider': 'test',
              'type': 'language',
            },
          ]);
        }
        if (path == '/api/models/defaults') {
          return _json({'default_chat_model': 'model:a'});
        }
        if (path == '/api/chat/sessions') {
          return _json(<Object>[]);
        }
        if (path == '/api/chat/context') {
          return _json({
            'context': {
              'sources': <Object>[],
              'notes': <Object>[],
            },
            'token_count': 0,
            'char_count': 0,
          });
        }
        return _json(<Object>[]);
      }),
    );

Future<ProviderContainer> _pumpShell(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(_fakeClient())],
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

/// 按工作区的方式打开对话标签页（Lead 的接入路径）。
void _openChatTab(ProviderContainer container) {
  final element = container.read(workspaceProvider.notifier);
  // WorkspaceNavigator 需要 WidgetRef；这里直接调用 notifier，等价于
  // `WorkspaceNavigator.openChat`。
  element.openChat(notebookId: _notebookId, title: '与「演示笔记本」对话');
}

void main() {
  testWidgets('宽屏工作区：打开对话标签页后渲染 ChatScreen，不出现布局溢出', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    _openChatTab(container);
    await tester.pumpAndSettle();

    expect(container.read(workspaceProvider).activeTab!.kind, WorkspaceTabKind.chat);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text(ChatStrings.noSessionTitle), findsOneWidget);
    // 宽屏：常驻左侧栏 + 模型选择。
    expect(find.text(ChatStrings.sessions), findsWidgets);
    expect(find.text('后端默认（Alpha）'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏工作区：对话标签页单栏铺满，发送入口可用', (tester) async {
    final container = await _pumpShell(tester, const Size(430, 880));

    _openChatTab(container);
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    // 窄屏不再常驻侧栏，通过 AppBar 动作进面板。
    expect(find.byTooltip(ChatStrings.openSessions), findsOneWidget);
    expect(find.byTooltip(ChatStrings.openContext), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机横屏（宽 900 / 高 420）切到分栏布局也不溢出', (tester) async {
    final container = await _pumpShell(tester, const Size(900, 420));

    _openChatTab(container);
    await tester.pumpAndSettle();

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一笔记本只保留一个对话标签页（切换而不是重复创建）', (tester) async {
    final container = await _pumpShell(tester, const Size(1280, 820));

    _openChatTab(container);
    await tester.pumpAndSettle();
    _openChatTab(container);
    await tester.pumpAndSettle();

    final chatTabs = container
        .read(workspaceProvider)
        .tabs
        .where((tab) => tab.kind == WorkspaceTabKind.chat);
    expect(chatTabs, hasLength(1));
    expect(chatTabs.single.targetId, _notebookId);
  });
}

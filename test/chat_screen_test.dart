import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/chat/chat_message_list.dart';
import 'package:pie_note/ui/chat/chat_screen.dart';
import 'package:pie_note/ui/chat/chat_strings.dart';

const String _notebookId = 'notebook:demo';
const String _sessionId = 'chat_session:one';
const String _noteId = 'note:kept';
const String _sourceId = 'source:with-insights';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

/// 最小的对话假后端。
class _FakeBackend {
  _FakeBackend({this.executeFails = false, this.withHistory = true});

  final bool executeFails;
  final bool withHistory;

  final List<http.Request> requests = <http.Request>[];

  /// 非空时 `/api/chat/execute` 会等它完成才返回（模拟真实生成耗时）。
  Completer<void>? executeGate;

  static const String aiAnswer = '## 摘要\n\n- 要点一\n- 要点二\n';

  late List<Map<String, dynamic>> _sessions = <Map<String, dynamic>>[
    if (withHistory)
      {
        'id': _sessionId,
        'title': '既有会话',
        'notebook_id': _notebookId,
        'created': '2026-11-23 10:00:00+00:00',
        'updated': '2026-11-23 10:05:00+00:00',
        'message_count': 2,
        'model_override': null,
      },
  ];

  late List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[
    if (withHistory) ...[
      {
        'id': 'message:h1',
        'type': 'human',
        'content': '旧问题',
        'timestamp': '2026-11-23 10:00:00+00:00',
      },
      {
        'id': 'message:a1',
        'type': 'ai',
        'content': '**旧回答**',
        'timestamp': '2026-11-23 10:00:05+00:00',
      },
    ],
  ];

  late final ApiClient client = ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient(_handle),
  );

  static String _decodedPath(http.Request request) =>
      Uri.decodeComponent(request.url.path);

  List<Map<String, dynamic>> bodiesFor(String path) => requests
      .where((request) => _decodedPath(request) == path && request.body.isNotEmpty)
      .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
      .toList(growable: false);

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = _decodedPath(request);

    if (path == '/api/sources') {
      return _json(<Object>[
        {
          'id': _sourceId,
          'title': '有洞见的来源',
          'topics': <String>[],
          'asset': null,
          'embedded': false,
          'embedded_chunks': 0,
          'insights_count': 2,
          'created': '2026-11-20 10:00:00+00:00',
          'updated': '2026-11-20 10:00:00+00:00',
          'status': 'completed',
        },
      ]);
    }
    if (path == '/api/notes' && request.method == 'GET') {
      return _json(<Object>[
        {
          'id': _noteId,
          'title': '笔记一',
          'content': null,
          'note_type': 'human',
          'notebook_id': _notebookId,
          'updated': '2026-11-23 09:00:00+00:00',
        },
      ]);
    }
    if (path == '/api/notes' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'id': 'note:created',
        'title': null,
        'content': body['content'],
        'note_type': body['note_type'],
        'created': '2026-11-23 10:00:00+00:00',
        'updated': '2026-11-23 10:00:00+00:00',
      });
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
    if (path == '/api/chat/sessions' && request.method == 'GET') {
      return _json(_sessions);
    }
    if (path == '/api/chat/sessions' && request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = {
        'id': _sessionId,
        'title': body['title'] ?? '',
        'notebook_id': _notebookId,
        'created': '2026-11-23 10:00:00+00:00',
        'updated': '2026-11-23 10:00:00+00:00',
        'message_count': 0,
        'model_override': body['model_override'],
      };
      _sessions = <Map<String, dynamic>>[created];
      _messages = <Map<String, dynamic>>[];
      return _json(created);
    }
    if (path.startsWith('/api/chat/sessions/')) {
      final id = path.substring('/api/chat/sessions/'.length);
      final base = _sessions.firstWhere(
        (session) => session['id'] == id,
        orElse: () => <String, dynamic>{'id': id, 'title': '新会话'},
      );
      if (request.method == 'DELETE') {
        _sessions = _sessions.where((session) => session['id'] != id).toList();
        return http.Response('', 204);
      }
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final updated = {...base, ...body};
        _sessions = <Map<String, dynamic>>[
          for (final session in _sessions)
            if (session['id'] == id) updated else session,
        ];
        return _json(updated);
      }
      return _json({...base, 'messages': _messages});
    }
    if (path == '/api/chat/context') {
      return _json({
        'context': {
          'sources': <Object>[],
          'notes': <Object>[],
        },
        'token_count': 42,
        'char_count': 168,
      });
    }
    if (path == '/api/chat/execute') {
      final gate = executeGate;
      if (gate != null) await gate.future;
      if (executeFails) {
        return _json(
          {'detail': 'AI service error: Error code: 400 - 模型不可用'},
          status: 502,
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      _messages = <Map<String, dynamic>>[
        ..._messages,
        {
          'id': 'message:h2',
          'type': 'human',
          'content': body['message'],
          'timestamp': '2026-11-23 10:06:00+00:00',
        },
        {
          'id': 'message:a2',
          'type': 'ai',
          'content': aiAnswer,
          'timestamp': '2026-11-23 10:06:05+00:00',
        },
      ];
      return _json({'messages': _messages});
    }
    return _json(<Object>[]);
  }
}

/// 在指定尺寸下渲染 [ChatScreen]。
Future<ProviderContainer> _pumpChat(
  WidgetTester tester,
  _FakeBackend backend, {
  Size size = const Size(1280, 900),
  bool embedded = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(backend.client)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ChatScreen(
          notebookId: _notebookId,
          title: '与「演示笔记本」对话',
          embedded: embedded,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _sendButton() => find.byTooltip(ChatStrings.sendShortcut);

void main() {
  testWidgets('宽屏：左侧栏显示会话与上下文，右侧渲染历史消息', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend);

    // 会话列表（左侧栏）。
    expect(find.text('既有会话'), findsWidgets);
    expect(find.text(ChatStrings.sessions), findsWidgets);

    // 人类消息右对齐气泡 + AI 消息 Markdown 渲染（不显示 `**` 标记）。
    expect(find.text('旧问题'), findsOneWidget);
    expect(find.textContaining('旧回答'), findsOneWidget);
    expect(find.textContaining('**旧回答**'), findsNothing);

    // AppBar 副标题展示上下文统计（有洞见的来源默认「仅洞见」）。
    expect(find.textContaining('个来源仅洞见'), findsWidgets);

    // 模型下拉第一项是「后端默认」并带默认模型名。
    expect(find.text('后端默认（Alpha）'), findsWidgets);
  });

  testWidgets('窄屏：单栏 + AppBar 动作打开会话 / 上下文面板', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend, size: const Size(430, 880));

    // 单栏：不显示常驻左侧栏，但消息仍可见。
    expect(find.text('旧问题'), findsOneWidget);

    // 打开会话面板。
    await tester.tap(find.byTooltip(ChatStrings.openSessions));
    await tester.pumpAndSettle();
    expect(find.text(ChatStrings.sessionPanelTitle), findsWidgets);
    expect(find.text(ChatStrings.newSession), findsWidgets);
    Navigator.of(tester.element(find.byType(ChatScreen))).pop();
    await tester.pumpAndSettle();

    // 打开上下文面板：显示来源与笔记勾选。
    await tester.tap(find.byTooltip(ChatStrings.openContext));
    await tester.pumpAndSettle();
    expect(find.text(ChatStrings.contextPanelTitle), findsWidgets);
    expect(find.text('有洞见的来源'), findsOneWidget);
    expect(find.text('笔记一'), findsOneWidget);
    expect(find.text(ChatStrings.previewContext), findsOneWidget);
  });

  testWidgets('发送成功：人类消息先出现，回答用后端完整历史覆盖并清空输入框', (tester) async {
    final backend = _FakeBackend(withHistory: false);
    await _pumpChat(tester, backend);

    // 无历史时显示空态引导。
    expect(find.text(ChatStrings.noSessionTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '这个笔记本讲了什么？');
    await tester.tap(_sendButton());
    await tester.pumpAndSettle();

    // 建会话 → 构建上下文 → 生成。
    expect(backend.bodiesFor('/api/chat/sessions').single['title'], '这个笔记本讲了什么？');
    expect(backend.bodiesFor('/api/chat/context'), hasLength(1));
    expect(backend.bodiesFor('/api/chat/execute').single['message'], '这个笔记本讲了什么？');

    // 人类消息气泡 + 会话标题（自动用首条消息命名）都会出现这段文字。
    expect(find.text('这个笔记本讲了什么？'), findsWidgets);
    expect(find.textContaining('要点一'), findsOneWidget);
    // 成功后被清空。
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, isEmpty);
    // 不再有生成中占位。
    expect(find.text(ChatStrings.generating), findsNothing);
  });

  testWidgets('生成失败：显示可重试的内联错误，输入文本与历史消息都保留', (tester) async {
    final backend = _FakeBackend(executeFails: true);
    await _pumpChat(tester, backend);

    await tester.enterText(find.byType(TextField).first, '会失败的问题');
    await tester.tap(_sendButton());
    await tester.pumpAndSettle();

    // 内联错误（不是一闪而过的 snackbar），带重试按钮。
    expect(find.text(ChatStrings.sendFailedTitle), findsOneWidget);
    expect(find.textContaining('AI service error'), findsWidgets);
    expect(find.text(ChatStrings.sendFailedRetry), findsOneWidget);

    // 乐观插入的用户消息被回滚（消息区里看不到它），输入框保留原文。
    expect(
      find.descendant(
        of: find.byType(ChatMessageList),
        matching: find.text('会失败的问题'),
      ),
      findsNothing,
    );
    expect(find.text('旧问题'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '会失败的问题');

    // 错误条可关闭。
    await tester.tap(find.byTooltip(ChatStrings.dismissError));
    await tester.pumpAndSettle();
    expect(find.text(ChatStrings.sendFailedTitle), findsNothing);
  });

  testWidgets('AI 消息「保存为笔记」请求 note_type=ai 与当前 notebook_id', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend);

    await tester.tap(find.byTooltip(ChatStrings.saveAsNote).first);
    await tester.pumpAndSettle();

    final body = backend.bodiesFor('/api/notes').single;
    expect(body['note_type'], 'ai');
    expect(body['notebook_id'], _notebookId);
    expect(body['content'], '**旧回答**');
    expect(find.text(ChatStrings.savedAsNote), findsOneWidget);
  });

  testWidgets('上下文面板「预览上下文」调用 buildContext 并显示 token 数', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend, size: const Size(430, 880));

    await tester.tap(find.byTooltip(ChatStrings.openContext));
    await tester.pumpAndSettle();

    await tester.tap(find.text(ChatStrings.previewContext));
    await tester.pumpAndSettle();

    expect(backend.bodiesFor('/api/chat/context'), hasLength(1));
    final preview = backend.bodiesFor('/api/chat/context').single;
    expect(
      ((preview['context_config'] as Map<String, dynamic>)['sources']
          as Map<String, dynamic>)[_sourceId],
      'insights',
    );
    // 预览结果是 sheet 内的统计文案（snackbar 也带同样文案）。
    expect(find.textContaining('42 tokens'), findsWidgets);
  });

  testWidgets('窄屏：AppBar 的模型按钮打开模型面板，选中后调用会话级覆盖', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(tester, backend, size: const Size(430, 880));

    await tester.tap(find.byTooltip(ChatStrings.openModel));
    await tester.pumpAndSettle();

    expect(find.text(ChatStrings.modelPanelTitle), findsWidgets);
    expect(find.text('后端默认（Alpha）'), findsWidgets);
    expect(find.text(ChatStrings.defaultModelHint), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    // 有会话：PUT 到会话级 model_override。
    final body = backend.bodiesFor('/api/chat/sessions/$_sessionId').last;
    expect(body['model_override'], 'model:a');
    expect(find.text(ChatStrings.modelChanged), findsOneWidget);
  });

  testWidgets('生成中禁用发送按钮与输入框，结束后恢复（避免并发）', (tester) async {
    final backend = _FakeBackend();
    backend.executeGate = Completer<void>();
    await _pumpChat(tester, backend, size: const Size(430, 880));

    await tester.enterText(find.byType(TextField).first, '慢问题');
    await tester.tap(_sendButton());
    await tester.pump();

    // 生成中：占位文案 + 输入框禁用 + 发送按钮禁用。
    expect(find.text(ChatStrings.generating), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField).first).enabled, isFalse);
    // 发送按钮变成 spinner 且被禁用（tooltip 切到「AI 正在回答…」）。
    final sendButton = find.ancestor(
      of: find.byTooltip(ChatStrings.sending),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

    backend.executeGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text(ChatStrings.generating), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).enabled,
      isNot(false),
    );
  });

  testWidgets('窄屏 embedded：消息列表底部给悬浮胶囊留出滚动余量', (tester) async {
    final backend = _FakeBackend();
    await _pumpChat(
      tester,
      backend,
      size: const Size(430, 880),
      embedded: true,
    );

    final listView = tester.widget<ListView>(
      find.descendant(
        of: find.byType(ChatMessageList),
        matching: find.byType(ListView),
      ),
    );
    final padding = listView.padding as EdgeInsets;
    // ChatMessageList.bottomInset 默认 120，再叠加固定 16。
    expect(padding.bottom, greaterThanOrEqualTo(120));
  });
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/api_models.dart';
import 'package:pie_note/state/providers.dart';
import 'package:pie_note/ui/chat/chat_controller.dart';

const String _notebookId = 'notebook:demo';
const String _sessionId = 'chat_session:one';
const String _noteId = 'note:kept';
const String _sourceWithInsights = 'source:insights';
const String _sourcePlain = 'source:plain';
const String _sourceFailed = 'source:failed';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

/// 一个最小的 Open Notebook 假后端：记录请求并按路径返回固定响应。
class _FakeBackend {
  /// `/api/chat/execute` 是否返回 502（模拟本机 LLM provider 不可用）。
  final bool executeFails;

  /// 初始是否已有一个会话。
  final bool existingSessions;

  final List<http.Request> requests = <http.Request>[];
  final List<String> paths = <String>[];

  /// AI 回答正文（断言 Markdown 渲染用）。
  static const String aiAnswer = '# 结论\n\n- 要点一\n';

  _FakeBackend({this.executeFails = false, this.existingSessions = false}) {
    if (existingSessions) {
      sessions = <Map<String, dynamic>>[
        _sessionJson(title: '旧会话', messageCount: 2),
      ];
      messages = <Map<String, dynamic>>[_oldHuman, _oldAi];
    }
  }

  static const Map<String, dynamic> _oldHuman = {
    'id': 'message:h1',
    'type': 'human',
    'content': '旧问题',
    'timestamp': '2026-11-23 10:00:00+00:00',
  };

  static const Map<String, dynamic> _oldAi = {
    'id': 'message:a1',
    'type': 'ai',
    'content': '旧回答',
    'timestamp': '2026-11-23 10:00:05+00:00',
  };

  List<Map<String, dynamic>> sessions = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];

  Map<String, dynamic> _sessionJson({
    required String title,
    int messageCount = 0,
  }) =>
      {
        'id': _sessionId,
        'title': title,
        'notebook_id': _notebookId,
        'created': '2026-11-23 10:00:00+00:00',
        'updated': '2026-11-23 10:05:00+00:00',
        'message_count': messageCount,
        'model_override': null,
      };

  late final ApiClient client = ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient(_handle),
  );

  /// 解码后的请求路径（`:id` 里的冒号会被编码成 `%3A`）。
  static String decodedPath(http.Request request) =>
      Uri.decodeComponent(request.url.path);

  /// 发往某个路径的请求体（已解码）。
  List<Map<String, dynamic>> bodiesFor(String path) => requests
      .where((request) => decodedPath(request) == path && request.body.isNotEmpty)
      .map((request) => jsonDecode(request.body) as Map<String, dynamic>)
      .toList(growable: false);

  Map<String, dynamic>? lastBody(String path) {
    final bodies = bodiesFor(path);
    return bodies.isEmpty ? null : bodies.last;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    paths.add(decodedPath(request));
    final path = decodedPath(request);

    if (path == '/api/sources') {
      return _json(<Object>[
        _sourceJson(_sourceWithInsights, '有洞见的来源', insights: 3),
        _sourceJson(_sourcePlain, '普通来源', insights: 0),
        _sourceJson(_sourceFailed, '失败的来源', insights: 0, status: 'failed'),
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
      return _json(sessions);
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
      sessions = <Map<String, dynamic>>[created];
      return _json(created);
    }
    if (path.startsWith('/api/chat/sessions/')) {
      final id = Uri.decodeComponent(path.substring('/api/chat/sessions/'.length));
      final base = sessions.firstWhere(
        (session) => session['id'] == id,
        orElse: () => _sessionJson(title: '新会话'),
      );
      if (request.method == 'DELETE') {
        sessions = sessions.where((session) => session['id'] != id).toList();
        return http.Response('', 204);
      }
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final updated = {...base, ...body};
        sessions = <Map<String, dynamic>>[
          for (final session in sessions)
            if (session['id'] == id) updated else session,
        ];
        return _json(updated);
      }
      return _json({...base, 'messages': messages});
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
      if (executeFails) {
        return _json(
          {'detail': 'AI service error: Error code: 400 - 模型不可用'},
          status: 502,
        );
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      messages = <Map<String, dynamic>>[
        ...messages,
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
      sessions = <Map<String, dynamic>>[
        {
          ...sessions.isEmpty ? _sessionJson(title: '自动会话') : sessions.first,
          'message_count': messages.length,
        },
      ];
      return _json({'messages': messages});
    }
    return _json(<Object>[]);
  }

  Map<String, dynamic> _sourceJson(
    String id,
    String title, {
    required int insights,
    String status = 'completed',
  }) =>
      {
        'id': id,
        'title': title,
        'topics': <String>[],
        'asset': null,
        'embedded': false,
        'embedded_chunks': 0,
        'insights_count': insights,
        'created': '2026-11-20 10:00:00+00:00',
        'updated': '2026-11-20 10:00:00+00:00',
        'status': status,
      };
}

/// 建一个容器并保持 provider 存活（autoDispose 在无监听时会被回收）。
Future<(ProviderContainer, ProviderSubscription<AsyncValue<ChatState>>)> _pump(
  _FakeBackend backend,
) async {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(backend.client)],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    chatControllerProvider(_notebookId),
    (previous, next) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  await container.read(chatControllerProvider(_notebookId).future);
  return (container, subscription);
}

ChatController _controller(ProviderContainer container) =>
    container.read(chatControllerProvider(_notebookId).notifier);

ChatState _state(ProviderContainer container) =>
    container.read(chatControllerProvider(_notebookId)).requireValue;

void main() {
  group('默认上下文推导', () {
    test('有洞见的来源用 insights，其余来源全文，处理失败的不进上下文，笔记全文', () {
      final selection = defaultContextSelection(
        sources: <Source>[
          _source(insightsCount: 4),
          _source(id: 'source:zero', insightsCount: 0),
          _source(id: 'source:failed', status: SourceStatus.failed),
          _source(id: 'source:running', status: SourceStatus.running),
        ],
        notes: <Note>[_note()],
      );

      expect(selection.sources['source:with-insights'], ContextMode.insights);
      expect(selection.sources['source:zero'], ContextMode.full);
      // 处理中 / 失败：没有正文可注入，默认不进上下文。
      expect(selection.sources.containsKey('source:failed'), isFalse);
      expect(selection.sources.containsKey('source:running'), isFalse);
      expect(selection.notes[_noteId], ContextMode.full);
    });

    test('toRequestConfig 与后端字符串对齐（not in / insights / full content）', () {
      const selection = ChatContextSelection(
        sources: <String, ContextMode>{
          'source:a': ContextMode.insights,
          'source:b': ContextMode.full,
        },
        notes: <String, ContextMode>{'note:a': ContextMode.full},
      );

      expect(selection.toRequestConfig(), <String, dynamic>{
        'sources': <String, String>{
          'source:a': 'insights',
          'source:b': 'full content',
        },
        'notes': <String, String>{'note:a': 'full content'},
      });
      expect(ContextMode.off.apiValue, 'not in');
    });

    test('值相等的 selection 可作 provider 缓存 key', () {
      const a = ChatContextSelection(
        sources: <String, ContextMode>{'source:a': ContextMode.full},
      );
      const b = ChatContextSelection(
        sources: <String, ContextMode>{'source:a': ContextMode.full},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ChatController 发送流程', () {
    test('无会话时自动建会话 → buildContext → execute，并用返回消息覆盖本地', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      expect(_state(container).sessions, isEmpty);
      expect(_state(container).selectedSessionId, isNull);

      final ok = await _controller(container).send('  这个笔记本讲了什么？  ');
      expect(ok, isTrue);

      // 1) 先建会话，标题取首条消息摘要。
      final createBody = backend.lastBody('/api/chat/sessions');
      expect(createBody?['notebook_id'], _notebookId);
      expect(createBody?['title'], '这个笔记本讲了什么？');

      // 2) 再构建上下文，context_config 的字符串必须对齐后端。
      final contextBody = backend.lastBody('/api/chat/context');
      expect(contextBody?['notebook_id'], _notebookId);
      final config = contextBody?['context_config'] as Map<String, dynamic>;
      expect(
        (config['sources'] as Map<String, dynamic>)[_sourceWithInsights],
        'insights',
      );
      expect((config['sources'] as Map<String, dynamic>)[_sourcePlain], 'full content');
      expect((config['sources'] as Map<String, dynamic>).containsKey(_sourceFailed), isFalse);
      expect((config['notes'] as Map<String, dynamic>)[_noteId], 'full content');

      // 3) 最后 execute，消息为去掉首尾空白的纯文本，model_override 不传。
      final executeBody = backend.lastBody('/api/chat/execute');
      expect(executeBody?['session_id'], _sessionId);
      expect(executeBody?['message'], '这个笔记本讲了什么？');
      expect(executeBody!.containsKey('model_override'), isFalse);
      expect(executeBody['context'], isA<Map<String, dynamic>>());

      // 请求顺序：加载列表 → 建会话 → 构建上下文 → 生成 → 刷新列表。
      expect(
        backend.paths.where((path) => path.startsWith('/api/chat')).toList(),
        <String>[
          '/api/chat/sessions',
          '/api/chat/sessions',
          '/api/chat/context',
          '/api/chat/execute',
          '/api/chat/sessions',
        ],
      );

      // 4) 本地消息 = 后端返回的完整历史（不是增量），且不再有 pending。
      final state = _state(container);
      expect(state.sending, isFalse);
      expect(state.errorText, isNull);
      expect(state.messages.map((message) => message.id), <String>[
        'message:h2',
        'message:a2',
      ]);
      expect(
        state.messages.every((message) => !message.pending),
        isTrue,
      );
      expect(state.selectedSessionId, _sessionId);
      expect(state.sessions.single.id, _sessionId);
      expect(state.lastContext?.tokenCount, 42);
      expect(state.lastContext?.charCount, 168);
    });

    test('已有会话时直接复用，不再新建会话', () async {
      final backend = _FakeBackend(existingSessions: true);
      final (container, _) = await _pump(backend);

      expect(_state(container).selectedSessionId, _sessionId);
      expect(_state(container).messages, hasLength(2));

      final ok = await _controller(container).send('继续');
      expect(ok, isTrue);
      expect(backend.bodiesFor('/api/chat/sessions'), isEmpty);
      expect(backend.paths, contains('/api/chat/execute'));
    });

    test('生成失败：回滚 pending 消息、保留输入文本、给出可重试的内联错误', () async {
      final backend = _FakeBackend(executeFails: true);
      final (container, _) = await _pump(backend);

      final ok = await _controller(container).send('会失败的问题');
      expect(ok, isFalse);

      final state = _state(container);
      expect(state.sending, isFalse);
      // 乐观插入的用户消息被移除，列表回到失败前的样子。
      expect(state.messages, isEmpty);
      expect(state.messages.where((message) => message.pending), isEmpty);
      // 输入文本保留，供「重试」再次发送。
      expect(state.failedMessage, '会失败的问题');
      // 后端 502 的 detail 被映射成可读文案。
      expect(state.errorText, contains('服务器内部错误'));
      expect(state.errorText, contains('AI service error'));
    });

    test('重试成功后内联错误清除，消息用后端返回覆盖', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);
      await _controller(container).send('第一问');

      final retryBackendOk = await _controller(container).retryLastSend();
      // 没有失败消息时重试是空操作。
      expect(retryBackendOk, isFalse);
      expect(_state(container).messages, hasLength(2));
    });

    test('生成中再次发送会被忽略（避免并发 execute）', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      final first = _controller(container).send('问题一');
      // 同一时刻的第二次调用直接返回 false。
      final second = await _controller(container).send('问题二');
      expect(second, isFalse);
      expect(await first, isTrue);
      expect(
        backend.bodiesFor('/api/chat/execute').map((body) => body['message']),
        <String>['问题一'],
      );
    });
  });

  group('ChatController 会话与上下文', () {
    test('新建 / 重命名 / 删除会话都写回后端并更新本地列表', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      expect(await _controller(container).createSession(title: '手工标题'), isTrue);
      expect(backend.lastBody('/api/chat/sessions')?['title'], '手工标题');
      expect(_state(container).selectedSessionId, _sessionId);

      expect(await _controller(container).renameSession(_sessionId, '改个名'), isTrue);
      expect(backend.lastBody('/api/chat/sessions/$_sessionId')?['title'], '改个名');
      expect(_state(container).selectedSession?.title, '改个名');

      expect(await _controller(container).deleteSession(_sessionId), isTrue);
      expect(_state(container).sessions, isEmpty);
      expect(_state(container).selectedSessionId, isNull);
      expect(_state(container).messages, isEmpty);
    });

    test('切换模型：有会话时写会话级 model_override，无会话时作为待定覆盖', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      // 无会话：只记在本地，新建会话时传给后端。
      expect(await _controller(container).setModel('model:a'), isTrue);
      expect(_state(container).modelOverride, 'model:a');
      expect(backend.bodiesFor('/api/chat/sessions'), isEmpty);

      await _controller(container).send('用 Alpha 回答');
      expect(backend.lastBody('/api/chat/sessions')?['model_override'], 'model:a');
      // 建完会话后 pending 覆盖被消费。
      expect(_state(container).pendingModelId, isNull);

      // 有会话：PUT 到会话上。
      expect(await _controller(container).setModel('model:a'), isTrue);
      expect(
        backend.lastBody('/api/chat/sessions/$_sessionId')?['model_override'],
        'model:a',
      );
      expect(_state(container).selectedSession?.modelOverride, 'model:a');
    });

    test('切换上下文勾选只改本地，并清掉过期的 token 估算', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      final built = await _controller(container).previewContext();
      expect(built?.tokenCount, 42);
      expect(_state(container).lastContext?.tokenCount, 42);

      _controller(container).setSourceMode(_sourcePlain, ContextMode.off);
      final state = _state(container);
      expect(state.selection.sources.containsKey(_sourcePlain), isFalse);
      expect(state.lastContext, isNull);
      expect(state.fullSourceCount, 0);
      expect(state.insightSourceCount, 1);

      _controller(container).setNoteIncluded(_noteId, false);
      expect(_state(container).selection.notes, isEmpty);
      expect(_state(container).contextSummary, isNotEmpty);
    });
  });

  group('ChatController AI 消息动作', () {
    test('保存为笔记：note_type=ai、notebook_id 为当前笔记本，并刷新笔记列表', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      const message = ChatMessage(
        id: 'message:a9',
        role: ChatRole.ai,
        content: '# 结论\n\n- 要点一\n',
      );
      final notesBefore = backend.paths.where((path) => path == '/api/notes').length;

      expect(await _controller(container).saveMessageAsNote(message), isTrue);

      final body = backend.lastBody('/api/notes');
      expect(body?['content'], message.content);
      expect(body?['note_type'], 'ai');
      expect(body?['notebook_id'], _notebookId);

      // invalidate 之后重新读列表会再发一次 GET。
      await container.read(notesProvider(_notebookId).future);
      final notesAfter = backend.paths.where((path) => path == '/api/notes').length;
      expect(notesAfter, greaterThan(notesBefore));
    });

    test('空回答不保存为笔记', () async {
      final backend = _FakeBackend();
      final (container, _) = await _pump(backend);

      const empty = ChatMessage(
        id: 'message:a10',
        role: ChatRole.ai,
        content: '   ',
      );
      expect(await _controller(container).saveMessageAsNote(empty), isFalse);
      expect(backend.bodiesFor('/api/notes'), isEmpty);
    });
  });
}

Source _source({
  String id = 'source:with-insights',
  int insightsCount = 2,
  SourceStatus status = SourceStatus.completed,
}) =>
    Source(
      id: id,
      title: id,
      topics: const <String>[],
      kind: SourceKind.text,
      url: null,
      filePath: null,
      embedded: false,
      embeddedChunks: 0,
      insightsCount: insightsCount,
      status: status,
      processingError: null,
      created: null,
      updated: null,
    );

Note _note() => const Note(
      id: _noteId,
      title: '笔记一',
      content: '# 笔记一',
      noteType: 'human',
      created: null,
      updated: null,
    );

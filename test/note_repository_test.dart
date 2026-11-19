import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/note_repository.dart';

/// 统一带 `charset=utf-8`，否则 [http.Response] 会用 latin1 编码中文正文。
const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body, {int statusCode = 200}) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    statusCode,
    headers: _jsonHeaders,
  );
}

http.Response _authStatus({bool enabled = true}) => _json({
      'auth_enabled': enabled,
      'message': enabled ? '需要密码' : '无需密码',
    });

/// 构造完全离线的仓库，并记录所有发出的请求。
({NoteRepository repository, List<http.Request> requests}) _buildRepository(
  Future<http.Response> Function(http.Request request) handler, {
  String? password = 'pw',
}) {
  final requests = <http.Request>[];
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: password,
    httpClient: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );
  return (repository: NoteRepository(client), requests: requests);
}

void main() {
  group('NoteRepository.testConnection', () {
    test('后端启用鉴权但密码为空时失败，且提示需要密码', () async {
      final (:repository, :requests) = _buildRepository(
        (request) async {
          if (request.url.path == '/api/auth/status') return _authStatus();
          return _json({'detail': 'unexpected'}, statusCode: 500);
        },
        password: '',
      );

      final result = await repository.testConnection();

      expect(result.ok, isFalse);
      expect(result.message, contains('密码'));
      expect(result.serverVersion, isNull);
      // 密码为空时不应再发注定 401 的业务请求。
      expect(requests.map((request) => request.url.path), ['/api/auth/status']);
    });

    test('密码正确时连接成功并返回服务版本', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        switch (request.url.path) {
          case '/api/auth/status':
            return _authStatus();
          case '/api/notebooks':
            return _json(const <Object>[]);
          case '/api/config':
            return _json({'version': '1.15.1'});
          default:
            return _json({'detail': 'unexpected'}, statusCode: 404);
        }
      });

      final result = await repository.testConnection();

      expect(result.ok, isTrue);
      expect(result.message, '连接成功');
      expect(result.serverVersion, '1.15.1');
      expect(result.authEnabled, isTrue);

      final paths = requests.map((request) => request.url.path).toList();
      expect(paths, containsAll(['/api/auth/status', '/api/notebooks', '/api/config']));
      // 校验密码的请求必须带 Bearer 鉴权头。
      final notebooksRequest =
          requests.firstWhere((request) => request.url.path == '/api/notebooks');
      expect(notebooksRequest.headers['Authorization'], 'Bearer pw');
    });

    test('笔记本接口返回 401 时连接失败，且提示鉴权', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        if (request.url.path == '/api/auth/status') return _authStatus();
        if (request.url.path == '/api/notebooks') {
          return _json({'detail': 'Invalid password'}, statusCode: 401);
        }
        return _json({'detail': 'unexpected'}, statusCode: 500);
      }, password: 'wrong');

      final result = await repository.testConnection();

      expect(result.ok, isFalse);
      expect(result.message, contains('鉴权'));
      expect(result.serverVersion, isNull);
      expect(requests.map((request) => request.url.path), isNot(contains('/api/config')));
    });

    test('/api/config 失败不影响连接判定，版本回退为未知版本', () async {
      final (:repository, requests: _) = _buildRepository((request) async {
        if (request.url.path == '/api/auth/status') return _authStatus();
        if (request.url.path == '/api/notebooks') return _json(const <Object>[]);
        return _json({'detail': 'not found'}, statusCode: 404);
      });

      final result = await repository.testConnection();

      expect(result.ok, isTrue);
      expect(result.serverVersion, '未知版本');
    });
  });

  group('NoteRepository.findNoteByTitle', () {
    Future<http.Response> Function(http.Request) notesHandler() {
      return (request) async {
        expect(request.url.path, '/api/notes');
        return _json([
          {'id': 'note:1', 'title': ' 标题a ', 'content': '正文'},
          {'id': 'note:2', 'title': '其他笔记'},
          {'id': 'note:3', 'title': '', 'content': '正文标题B\n第二行'},
        ]);
      };
    }

    test('标题大小写与首尾空白不敏感', () async {
      final (:repository, requests: _) = _buildRepository(notesHandler());

      final hit = await repository.findNoteByTitle(' 标题A ');

      expect(hit, isNotNull);
      expect(hit!.id, 'note:1');
    });

    test('标题为空时可用正文首行兜底命中', () async {
      final (:repository, requests: _) = _buildRepository(notesHandler());

      final hit = await repository.findNoteByTitle('正文标题B');

      expect(hit, isNotNull);
      expect(hit!.id, 'note:3');
    });

    test('找不到返回 null，空白标题不发请求', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        expect(request.url.path, '/api/notes');
        return _json(const <Object>[]);
      });

      expect(await repository.findNoteByTitle('不存在的标题'), isNull);
      expect(requests.length, 1);

      expect(await repository.findNoteByTitle('   '), isNull);
      expect(requests.length, 1);
    });
  });
}

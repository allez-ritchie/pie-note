import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/api_models.dart';

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

/// 用 [MockClient] 构造完全离线的 [ApiClient]。
ApiClient _buildClient(
  Future<http.Response> Function(http.Request request) handler, {
  String baseUrl = 'http://127.0.0.1:5055',
  String? password,
}) {
  return ApiClient(
    baseUrl: baseUrl,
    password: password,
    httpClient: MockClient(handler),
  );
}

Matcher _throwsBadRequest() {
  return throwsA(
    isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.badRequest),
  );
}

void main() {
  group('normalizeBaseUrl', () {
    test('去掉尾部斜杠并保留主机与端口', () {
      expect(normalizeBaseUrl('http://127.0.0.1:5055/'), 'http://127.0.0.1:5055');
      expect(
        normalizeBaseUrl('  http://127.0.0.1:5055///  '),
        'http://127.0.0.1:5055',
      );
      expect(normalizeBaseUrl('https://example.com'), 'https://example.com');
    });

    test('缺少 scheme 时自动补 http://', () {
      expect(normalizeBaseUrl('192.168.31.24:5055'), 'http://192.168.31.24:5055');
      expect(normalizeBaseUrl('10.0.2.2:5055/'), 'http://10.0.2.2:5055');
      expect(normalizeBaseUrl('example.com/notebook'), 'http://example.com/notebook');
    });

    test('保留反向代理子路径，只去掉末尾斜杠', () {
      expect(
        normalizeBaseUrl('https://example.com/notebook/'),
        'https://example.com/notebook',
      );
    });

    test('空输入抛 ApiException 且 kind 为 badRequest', () {
      expect(() => normalizeBaseUrl(''), _throwsBadRequest());
      expect(() => normalizeBaseUrl('   '), _throwsBadRequest());
    });

    test('非 http/https scheme 抛 ApiException 且 kind 为 badRequest', () {
      expect(() => normalizeBaseUrl('ftp://x'), _throwsBadRequest());
      expect(() => normalizeBaseUrl('ws://127.0.0.1:5055'), _throwsBadRequest());
      expect(() => normalizeBaseUrl('file:///tmp/notebook'), _throwsBadRequest());
    });

    test('中文输入法常见的全角标点会被归一化为半角', () {
      // 真机上中文输入法会把 `:` `.` `/` 打成全角，用户不应因此无法保存配置。
      expect(
        normalizeBaseUrl('http：／／192。168。31。24：5055'),
        'http://192.168.31.24:5055',
      );
      expect(
        normalizeBaseUrl('１９２.１６８.３１.２４:５０５５'),
        'http://192.168.31.24:5055',
      );
      expect(
        normalizeBaseUrl('http://192.168.31.24：5055/'),
        'http://192.168.31.24:5055',
      );
    });

    test('缺少 host 的输入抛 ApiException 且 kind 为 badRequest', () {
      expect(() => normalizeBaseUrl('http://'), _throwsBadRequest());
      expect(() => normalizeBaseUrl('http:///notebook'), _throwsBadRequest());
    });
  });

  group('ApiException.fromStatus', () {
    test('401 映射为 isUnauthorized 且保留状态码', () {
      final error = ApiException.fromStatus(
        401,
        '{"detail":"Missing authorization header"}',
      );
      expect(error.isUnauthorized, isTrue);
      expect(error.kind, ApiErrorKind.unauthorized);
      expect(error.statusCode, 401);
      expect(error.message, contains('鉴权'));
    });

    test('404 映射为 notFound', () {
      final error = ApiException.fromStatus(404, '{}');
      expect(error.kind, ApiErrorKind.notFound);
      expect(error.statusCode, 404);
      expect(error.isUnauthorized, isFalse);
    });

    test('500 映射为 server 且消息包含状态码', () {
      final error = ApiException.fromStatus(500, '{"detail":"boom"}');
      expect(error.kind, ApiErrorKind.server);
      expect(error.statusCode, 500);
      expect(error.message, contains('500'));
      expect(error.message, contains('boom'));
    });

    test('422 解析 FastAPI 的字符串 detail', () {
      final error = ApiException.fromStatus(422, '{"detail":"msg"}');
      expect(error.kind, ApiErrorKind.badRequest);
      expect(error.statusCode, 422);
      expect(error.message, 'msg');
    });

    test('422 解析 FastAPI 的校验错误数组', () {
      final error = ApiException.fromStatus(
        422,
        '{"detail":[{"loc":["body","content"],"msg":"field required","type":"value_error"}]}',
      );
      expect(error.kind, ApiErrorKind.badRequest);
      expect(error.message, 'field required');
    });

    test('422 无 detail 时给出通用参数错误提示', () {
      final error = ApiException.fromStatus(422, '{}');
      expect(error.kind, ApiErrorKind.badRequest);
      expect(error.message, isNotEmpty);
    });

    test('非 JSON 错误体截断后作为消息，不抛解析异常', () {
      final error = ApiException.fromStatus(502, '<html>gateway error</html>');
      expect(error.kind, ApiErrorKind.server);
      expect(error.message, contains('502'));
      expect(error.message, contains('gateway error'));
    });
  });

  group('鉴权头注入', () {
    test('配置密码时请求带 Authorization: Bearer', () async {
      http.Request? captured;
      final client = _buildClient((request) async {
        captured = request;
        return _json(const <Object>[]);
      }, password: 'secret');

      final notes = await client.fetchNotes();

      expect(notes, isEmpty);
      expect(captured, isNotNull);
      expect(captured!.url.path, '/api/notes');
      expect(captured!.headers['Authorization'], 'Bearer secret');
      expect(captured!.headers['Accept'], 'application/json');
    });

    test('password 为 null 时不带 Authorization 头', () async {
      http.Request? captured;
      final client = _buildClient((request) async {
        captured = request;
        return _json(const <Object>[]);
      }, password: null);

      expect(client.hasPassword, isFalse);
      await client.fetchNotes();

      expect(captured, isNotNull);
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('password 为空串时按未配置密码处理，不带 Authorization 头', () async {
      http.Request? captured;
      final client = _buildClient((request) async {
        captured = request;
        return _json(const <Object>[]);
      }, password: '');

      expect(client.hasPassword, isFalse);
      await client.fetchNotes();

      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('fetchAuthStatus 即使配置了密码也不带 Authorization 头', () async {
      http.Request? captured;
      final client = _buildClient((request) async {
        captured = request;
        return _json({'auth_enabled': true, 'message': '需要密码'});
      }, password: 'secret');

      final status = await client.fetchAuthStatus();

      expect(status.authEnabled, isTrue);
      expect(status.message, '需要密码');
      expect(captured, isNotNull);
      expect(captured!.url.path, '/api/auth/status');
      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('解析容错', () {
    test('fetchNotes 容忍 null 字段并过滤掉没有 id 的条目', () async {
      final client = _buildClient((request) async {
        expect(request.url.path, '/api/notes');
        return _json([
          {
            'id': 'note:1',
            'title': null,
            'content': null,
            'note_type': null,
            'created': null,
            'updated': null,
          },
          {'title': 'no id'},
          {'id': '', 'title': 'empty id'},
          'not-a-map',
          {
            'id': 'note:2',
            'title': '标题',
            'content': '正文',
            'note_type': 'human',
            'created': '2026-11-18 03:23:19.814849+00:00',
          },
        ]);
      }, password: 'secret');

      final notes = await client.fetchNotes();

      expect(notes.map((note) => note.id), ['note:1', 'note:2']);
      expect(notes.first.title, isEmpty);
      expect(notes.first.content, isEmpty);
      expect(notes.first.noteType, 'human');
      expect(notes.first.created, isNull);
      expect(notes.last.title, '标题');
      expect(notes.last.content, '正文');
      expect(notes.last.created, isNotNull);
      expect(notes.last.created!.isUtc, isTrue);
    });

    test('fetchNotes 把 notebook_id 放进查询参数', () async {
      http.Request? captured;
      final client = _buildClient((request) async {
        captured = request;
        return _json(const <Object>[]);
      }, password: 'secret');

      await client.fetchNotes(notebookId: 'notebook:abc');

      expect(captured!.url.path, '/api/notes');
      expect(captured!.url.queryParameters['notebook_id'], 'notebook:abc');
    });

    test('fetchNotebooks 解析 note_count / source_count / archived', () async {
      final client = _buildClient((request) async {
        expect(request.url.path, '/api/notebooks');
        expect(request.url.queryParameters['archived'], 'false');
        expect(request.url.queryParameters['order_by'], 'updated desc');
        return _json([
          {
            'id': 'notebook:1',
            'name': '工作',
            'description': '工作笔记本',
            'archived': true,
            'note_count': 3,
            'source_count': 2,
            'created': '2026-11-18 03:23:19+00:00',
            'updated': null,
          },
          {'id': 'notebook:2', 'name': null},
        ]);
      }, password: 'secret');

      final notebooks = await client.fetchNotebooks(archived: false);

      expect(notebooks.length, 2);
      expect(notebooks.first.noteCount, 3);
      expect(notebooks.first.sourceCount, 2);
      expect(notebooks.first.archived, isTrue);
      expect(notebooks.first.hasDescription, isTrue);
      expect(notebooks.first.created!.isUtc, isTrue);
      expect(notebooks.last.name, '未命名笔记本');
      expect(notebooks.last.archived, isFalse);
      expect(notebooks.last.noteCount, 0);
      expect(notebooks.last.sourceCount, 0);
    });
  });

  group('错误映射', () {
    test('后端返回 401 时抛出 isUnauthorized 的 ApiException', () async {
      final client = _buildClient(
        (_) async => _json({'detail': 'Invalid password'}, statusCode: 401),
        password: 'wrong',
      );

      await expectLater(
        client.fetchNotes(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('期望列表却返回 JSON 对象时抛出 ApiException', () async {
      final client = _buildClient(
        (_) async => _json({'detail': 'not a list'}),
        password: 'secret',
      );

      await expectLater(
        client.fetchNotes(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server),
        ),
      );
    });

    test('200 但正文不是合法 JSON 时抛出 ApiException', () async {
      final client = _buildClient(
        (_) async => http.Response(
          'this is not json',
          200,
          headers: _jsonHeaders,
        ),
        password: 'secret',
      );

      await expectLater(
        client.fetchNotes(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server),
        ),
      );
    });
  });

  group('时间解析', () {
    test('parseServerDate 把无 T 分隔符的 UTC 时间解析为 UTC', () {
      final parsed = parseServerDate('2026-11-18 03:23:19.814849+00:00');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isTrue);
      expect(parsed, DateTime.utc(2026, 11, 18, 3, 23, 19, 814, 849));
    });

    test('parseServerDate 把带时区偏移的时间换算成 UTC', () {
      expect(
        parseServerDate('2026-11-18T11:23:19+08:00'),
        DateTime.utc(2026, 11, 18, 3, 23, 19),
      );
    });

    test('parseServerDate 对 null / 非字符串 / 脏数据返回 null', () {
      expect(parseServerDate(null), isNull);
      expect(parseServerDate(12), isNull);
      expect(parseServerDate(''), isNull);
      expect(parseServerDate('not-a-date'), isNull);
    });
  });
}

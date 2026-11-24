import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pie_note/data/api_client.dart';
import 'package:pie_note/data/note_repository.dart';
import 'package:pie_note/data/note_text_edits.dart';

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};

http.Response _json(Object? body, {int statusCode = 200}) => http.Response(
      body == null ? '' : jsonEncode(body),
      statusCode,
      headers: _jsonHeaders,
    );

({NoteRepository repository, List<http.Request> requests}) _buildRepository(
  Future<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final client = ApiClient(
    baseUrl: 'http://127.0.0.1:5055',
    password: 'pw',
    httpClient: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );
  return (repository: NoteRepository(client), requests: requests);
}

Map<String, dynamic> _noteJson({
  required String id,
  String title = '标题',
  String content = '正文',
  String noteType = 'human',
}) =>
    {
      'id': id,
      'title': title,
      'content': content,
      'note_type': noteType,
      'created': '2026-11-18 03:23:19.814849+00:00',
      'updated': '2026-11-20 03:23:19.814849+00:00',
      'command_id': null,
    };

void main() {
  group('NoteRepository.moveNote', () {
    test('先复制到目标笔记本再删除原笔记，返回新笔记 id', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        final path = request.url.path;
        if (path == '/api/notes/note%3Aold') {
          return _json(_noteJson(id: 'note:old', title: '旧笔记', content: '正文'));
        }
        if (path == '/api/notes' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['notebook_id'], 'notebook:target');
          expect(body['title'], '旧笔记');
          expect(body['content'], '正文');
          return _json(_noteJson(id: 'note:new', title: '旧笔记', content: '正文'));
        }
        if (path == '/api/notes/note%3Aold' && request.method == 'DELETE') {
          return _json({'message': 'Note deleted successfully'});
        }
        return _json({'detail': 'unexpected $path'}, statusCode: 500);
      });

      final moved = await repository.moveNote(
        'note:old',
        targetNotebookId: 'notebook:target',
      );

      expect(moved.id, 'note:new');
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        [
          'GET /api/notes/note%3Aold',
          'POST /api/notes',
          'DELETE /api/notes/note%3Aold',
        ],
      );
    });

    test('目标为「全部笔记」时不带 notebook_id', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        final path = request.url.path;
        if (path == '/api/notes/note%3Aold') {
          return _json(_noteJson(id: 'note:old'));
        }
        if (path == '/api/notes' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body.containsKey('notebook_id'), isFalse);
          return _json(_noteJson(id: 'note:new'));
        }
        return _json({'message': 'ok'});
      });

      await repository.moveNote('note:old', targetNotebookId: null);
      expect(requests.where((request) => request.method == 'POST'), hasLength(1));
    });

    test('删除原笔记失败时回滚刚创建的副本，并抛出错误', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        final path = request.url.path;
        if (path == '/api/notes/note%3Aold' && request.method == 'GET') {
          return _json(_noteJson(id: 'note:old'));
        }
        if (path == '/api/notes' && request.method == 'POST') {
          return _json(_noteJson(id: 'note:copy'));
        }
        if (path == '/api/notes/note%3Aold' && request.method == 'DELETE') {
          return _json({'detail': 'boom'}, statusCode: 500);
        }
        if (path == '/api/notes/note%3Acopy' && request.method == 'DELETE') {
          return _json({'message': 'ok'});
        }
        return _json({'detail': 'unexpected'}, statusCode: 500);
      });

      await expectLater(
        repository.moveNote('note:old', targetNotebookId: 'notebook:target'),
        throwsA(isA<ApiException>()),
      );
      // 必须尝试清理副本，避免留下重复笔记。
      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        contains('DELETE /api/notes/note%3Acopy'),
      );
    });
  });

  group('NoteRepository.duplicateNote', () {
    test('先取完整正文，再以「标题 副本」创建', () async {
      final (:repository, :requests) = _buildRepository((request) async {
        final path = request.url.path;
        if (path == '/api/notes/note%3Aa' && request.method == 'GET') {
          // 列表接口不带正文，这里模拟详情接口返回完整正文。
          return _json(_noteJson(id: 'note:a', title: '笔记 A', content: '# 正文'));
        }
        if (path == '/api/notes' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['title'], '笔记 A 副本');
          expect(body['content'], '# 正文');
          return _json(_noteJson(id: 'note:copy'));
        }
        return _json({'detail': 'unexpected'}, statusCode: 500);
      });

      await repository.duplicateNote('note:a', notebookId: 'notebook:x');
      expect(requests.first.url.path, '/api/notes/note%3Aa');
      expect(requests.last.method, 'POST');
    });
  });

  group('NoteTextEdits', () {
    test('识别首行标题', () {
      expect(NoteTextEdits.hasHeadingFirstLine('# 标题\n正文'), isTrue);
      expect(NoteTextEdits.hasHeadingFirstLine('### 标题'), isTrue);
      expect(NoteTextEdits.hasHeadingFirstLine('普通首行\n# 标题'), isFalse);
      expect(NoteTextEdits.hasHeadingFirstLine('#标题'), isFalse);
      expect(NoteTextEdits.hasHeadingFirstLine(''), isFalse);
    });

    test('重命名只改首行标题，其余内容逐字节不变', () {
      const content = '## 旧标题\n\n第一段\n\n- [ ] 任务\n';
      final renamed = NoteTextEdits.renameFirstHeading(content, '新标题');
      expect(renamed, '## 新标题\n\n第一段\n\n- [ ] 任务\n');
    });

    test('没有标题行时原样返回', () {
      const content = '普通正文\n第二行\n';
      expect(NoteTextEdits.renameFirstHeading(content, '新标题'), content);
    });

    test('从正文推导建议标题', () {
      expect(NoteTextEdits.suggestedTitle('\n\n# 我的笔记\n正文'), '我的笔记');
      expect(NoteTextEdits.suggestedTitle('第一行正文\n第二行'), '第一行正文');
      expect(NoteTextEdits.suggestedTitle(''), '');
    });
  });
}

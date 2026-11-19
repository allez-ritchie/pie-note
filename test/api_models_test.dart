import 'package:flutter_test/flutter_test.dart';
import 'package:pie_note/data/api_models.dart';

Note _note({String title = '', String content = '', String noteType = 'human'}) {
  return Note(
    id: 'note:test',
    title: title,
    content: content,
    noteType: noteType,
    created: null,
    updated: null,
  );
}

void main() {
  group('Note.displayTitle', () {
    test('标题非空时返回去除首尾空白的标题', () {
      final note = _note(title: '  真实标题  ', content: '正文');
      expect(note.displayTitle, '真实标题');
    });

    test('标题为空或空白时回退到正文首个非空行', () {
      final note = _note(content: '\n\n   正文第一行   \n第二行');
      expect(note.displayTitle, '正文第一行');

      final blankTitle = _note(title: '   ', content: '\n\n正文标题\n');
      expect(blankTitle.displayTitle, '正文标题');
    });

    test('标题与正文都为空时返回「无标题笔记」', () {
      expect(_note().displayTitle, '无标题笔记');
      expect(_note(title: '  ', content: ' \n\t \n').displayTitle, '无标题笔记');
    });
  });

  group('Note.snippet', () {
    test('去掉代码块、行内代码、图片/链接语法与 Markdown 标记', () {
      final note = _note(
        content: '''
# 标题

这是 **粗体** 和 *斜体*，还有 `inline code` 与 [链接文本](https://x.com) 和 ![图片](a.png)。

```dart
void main() {}
```

- 列表项
''',
      );

      final snippet = note.snippet();

      expect(snippet, contains('标题'));
      expect(snippet, contains('粗体'));
      expect(snippet, contains('斜体'));
      // 代码块整体移除（含代码内容）。
      expect(snippet, isNot(contains('```')));
      expect(snippet, isNot(contains('void main')));
      // 行内代码移除。
      expect(snippet, isNot(contains('inline code')));
      // 图片语法与 URL 移除。
      expect(snippet, isNot(contains('https://x.com')));
      expect(snippet, isNot(contains('a.png')));
      expect(snippet, isNot(contains('![')));
      expect(snippet, isNot(contains('](')));
      // Markdown 标记移除，换行被压缩为空格。
      expect(snippet, isNot(contains('#')));
      expect(snippet, isNot(contains('*')));
      expect(snippet, isNot(contains('\n')));
      // 链接文本应保留（而不是留下替换占位符）。
      expect(snippet, contains('链接文本'));
      expect(snippet, isNot(contains(r'$1')));
    });

    test('压缩连续空白', () {
      final note = _note(content: 'a\n\n\n  b\t\tc  ');
      expect(note.snippet(), 'a b c');
    });

    test('超长内容截断并追加省略号', () {
      final note = _note(content: 'x' * 200);

      final truncated = note.snippet(maxLength: 50);

      expect(truncated.length, 51);
      expect(truncated.startsWith('x' * 50), isTrue);
      expect(truncated.endsWith('…'), isTrue);
      // 未超长时不截断。
      expect(note.snippet(maxLength: 500), 'x' * 200);
      // 默认 maxLength 为 120，截断后 121 个字符。
      expect(note.snippet().length, 121);
    });

    test('空内容返回空摘要', () {
      expect(_note().snippet(), isEmpty);
      expect(_note(content: '   \n  ').snippet(), isEmpty);
    });
  });

  group('SearchHit.fromJson', () {
    test('兼容 id + relevance 字段', () {
      final hit = SearchHit.fromJson({
        'id': 'note:1',
        'title': '标题',
        'content': '正文',
        'parent_id': 'note:parent',
        'notebook_id': 'notebook:1',
        'relevance': 0.9,
      });

      expect(hit.noteId, 'note:1');
      expect(hit.hasNoteId, isTrue);
      expect(hit.parentId, 'note:parent');
      expect(hit.title, '标题');
      expect(hit.content, '正文');
      expect(hit.notebookId, 'notebook:1');
      expect(hit.relevance, 0.9);
    });

    test('兼容 note_id + score 字段', () {
      final hit = SearchHit.fromJson({'note_id': 'note:2', 'score': 0.5});

      expect(hit.noteId, 'note:2');
      expect(hit.relevance, 0.5);
      expect(hit.title, isNull);
      expect(hit.parentId, isNull);
    });

    test('只有 parent_id 时也用它作为 id', () {
      final hit = SearchHit.fromJson({'parent_id': 'note:3'});

      expect(hit.noteId, 'note:3');
      expect(hit.parentId, 'note:3');
      expect(hit.hasNoteId, isTrue);
    });

    test('缺字段时不崩溃，relevance 仅接受数值', () {
      final empty = SearchHit.fromJson(const <String, dynamic>{});
      expect(empty.noteId, isEmpty);
      expect(empty.hasNoteId, isFalse);
      expect(empty.relevance, isNull);

      final intRelevance = SearchHit.fromJson({'id': 'x', 'relevance': 1});
      expect(intRelevance.relevance, 1.0);

      final stringRelevance = SearchHit.fromJson({'id': 'x', 'relevance': '0.9'});
      expect(stringRelevance.relevance, isNull);
    });
  });

  group('Notebook.fromJson', () {
    test('缺 description / archived / 计数字段时给出默认值', () {
      final notebook = Notebook.fromJson({'id': 'notebook:1'});

      expect(notebook.id, 'notebook:1');
      expect(notebook.name, '未命名笔记本');
      expect(notebook.description, isEmpty);
      expect(notebook.hasDescription, isFalse);
      expect(notebook.archived, isFalse);
      expect(notebook.noteCount, 0);
      expect(notebook.sourceCount, 0);
      expect(notebook.created, isNull);
      expect(notebook.updated, isNull);
    });

    test('完整字段与宽松类型解析', () {
      final notebook = Notebook.fromJson({
        'id': 'notebook:2',
        'name': '工作',
        'description': '工作笔记',
        'archived': true,
        'note_count': '5',
        'source_count': 2.7,
        'created': '2026-11-18 03:23:19.814849+00:00',
        'updated': '2026-11-19 01:02:03+00:00',
      });

      expect(notebook.name, '工作');
      expect(notebook.hasDescription, isTrue);
      expect(notebook.archived, isTrue);
      expect(notebook.noteCount, 5);
      expect(notebook.sourceCount, 2);
      expect(notebook.created!.isUtc, isTrue);
      expect(notebook.updated!.isUtc, isTrue);
    });
  });

  group('SearchQuery 相等性', () {
    test('字段相同（含 notebookIds 列表）时 == 与 hashCode 一致', () {
      const a = SearchQuery(query: '关键词', notebookIds: ['notebook:1', 'notebook:2']);
      const b = SearchQuery(query: '关键词', notebookIds: ['notebook:1', 'notebook:2']);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('任一字段不同则不相等', () {
      const base = SearchQuery(query: '关键词', notebookIds: ['notebook:1']);

      expect(base, isNot(const SearchQuery(query: '另一个关键词', notebookIds: ['notebook:1'])));
      expect(base, isNot(const SearchQuery(query: '关键词', notebookIds: ['notebook:2'])));
      expect(base, isNot(const SearchQuery(query: '关键词', notebookIds: ['notebook:1'], type: 'vector')));
      expect(base, isNot(const SearchQuery(query: '关键词', notebookIds: ['notebook:1'], limit: 10)));
      expect(base, isNot(Object()));
    });

    test('默认空 notebookIds 与显式空列表等价', () {
      expect(const SearchQuery(query: 'q'), const SearchQuery(query: 'q', notebookIds: []));
      expect(
        const SearchQuery(query: 'q').hashCode,
        const SearchQuery(query: 'q', notebookIds: []).hashCode,
      );
    });

    test('notebookIds 顺序不同视为不同查询', () {
      const a = SearchQuery(query: 'q', notebookIds: ['a', 'b']);
      const b = SearchQuery(query: 'q', notebookIds: ['b', 'a']);

      expect(a, isNot(b));
    });
  });

  group('AuthStatus / ServerConfig 解析', () {
    test('AuthStatus.fromJson 解析鉴权开关与消息', () {
      final status = AuthStatus.fromJson({
        'auth_enabled': true,
        'message': '需要密码',
      });

      expect(status.authEnabled, isTrue);
      expect(status.message, '需要密码');
    });

    test('AuthStatus.fromJson 缺字段时默认不启用鉴权', () {
      final status = AuthStatus.fromJson(const <String, dynamic>{});

      expect(status.authEnabled, isFalse);
      expect(status.message, isEmpty);
    });

    test('ServerConfig.fromJson 解析版本与数据库状态', () {
      final config = ServerConfig.fromJson({
        'version': '1.15.1',
        'latestVersion': '1.16.0',
        'dbStatus': 'connected',
      });

      expect(config.version, '1.15.1');
      expect(config.latestVersion, '1.16.0');
      expect(config.dbStatus, 'connected');
    });

    test('ServerConfig.fromJson 缺字段时为 null', () {
      final config = ServerConfig.fromJson(const <String, dynamic>{});

      expect(config.version, isNull);
      expect(config.latestVersion, isNull);
      expect(config.dbStatus, isNull);
    });
  });
}

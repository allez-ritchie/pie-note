/// Open Notebook 后端对应的数据模型。
///
/// 这些模型只做「宽松解析」：后端 schema 里大量字段可空，且搜索结果是
/// 未强类型的 object，任何解析失败都不应让整个列表崩溃。
library;

/// 解析后端时间字符串。
///
/// 后端返回形如 `2026-11-18 03:23:19.814849+00:00` 的 UTC 时间（无 `T` 分隔符），
/// Dart 的 [DateTime.parse] 可以解析，但这里仍然统一兜底，避免脏数据抛异常。
DateTime? parseServerDate(Object? value) {
  if (value is! String) return null;
  final raw = value.trim();
  if (raw.isEmpty) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return parsed.isUtc ? parsed : parsed.toUtc();
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 笔记本（Obsidian 里的 vault / 文件夹）。
class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.description,
    required this.archived,
    required this.created,
    required this.updated,
    required this.noteCount,
    required this.sourceCount,
  });

  final String id;
  final String name;
  final String description;
  final bool archived;
  final DateTime? created;
  final DateTime? updated;
  final int noteCount;
  final int sourceCount;

  bool get hasDescription => description.trim().isNotEmpty;

  factory Notebook.fromJson(Map<String, dynamic> json) {
    return Notebook(
      id: _asString(json['id']),
      name: _asString(json['name'], fallback: '未命名笔记本'),
      description: _asString(json['description']),
      archived: json['archived'] == true,
      created: parseServerDate(json['created']),
      updated: parseServerDate(json['updated']),
      noteCount: _asInt(json['note_count']),
      sourceCount: _asInt(json['source_count']),
    );
  }
}

/// 一条 Markdown 笔记。
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.noteType,
    required this.created,
    required this.updated,
    this.commandId,
  });

  final String id;
  final String title;
  final String content;
  final String noteType;
  final DateTime? created;
  final DateTime? updated;
  final String? commandId;

  bool get isAi => noteType.toLowerCase() == 'ai';

  /// 标题为空时用正文首行兜底，保证列表不出现空行。
  String get displayTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final firstLine = content
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return firstLine.isEmpty ? '无标题笔记' : firstLine;
  }

  /// 列表里的纯文本摘要：去掉 Markdown 标记与换行，截断到 [maxLength]。
  String snippet({int maxLength = 120}) => snippetOf(content, maxLength: maxLength);

  /// 对任意 Markdown 文本生成列表摘要。
  ///
  /// 后端按笔记本过滤笔记列表时不返回 `content`，UI 用内容索引补齐后再调用这里。
  static String snippetOf(String markdown, {int maxLength = 120}) {
    final plain = markdown
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (match) => match.group(1) ?? '')
        .replaceAll(RegExp(r'[#>*_~\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length <= maxLength) return plain;
    return '${plain.substring(0, maxLength)}…';
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: _asString(json['id']),
      title: _asString(json['title']),
      content: _asString(json['content']),
      noteType: _asString(json['note_type'], fallback: 'human'),
      created: parseServerDate(json['created']),
      updated: parseServerDate(json['updated']),
      commandId: json['command_id'] == null
          ? null
          : _asString(json['command_id']),
    );
  }
}

/// 搜索结果条目。
///
/// 后端 `/api/search` 的 `results` 是未强类型的 object，不同 `type` 下字段不同，
/// 实测文本搜索返回 `{id, parent_id, relevance, title}`。这里对已知字段做宽松解析。
class SearchHit {
  const SearchHit({
    required this.noteId,
    this.parentId,
    this.title,
    this.content,
    this.notebookId,
    this.relevance,
  });

  /// 命中的笔记 id（后端可能返回 `id` 或 `note_id`）。
  final String noteId;
  final String? parentId;
  final String? title;
  final String? content;
  final String? notebookId;
  final double? relevance;

  bool get hasNoteId => noteId.isNotEmpty;

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    final rawId = json['note_id'] ?? json['id'] ?? json['parent_id'];
    final rawRelevance = json['relevance'] ?? json['score'];
    return SearchHit(
      noteId: _asString(rawId),
      parentId: json['parent_id'] == null ? null : _asString(json['parent_id']),
      title: json['title'] == null ? null : _asString(json['title']),
      content: json['content'] == null ? null : _asString(json['content']),
      notebookId: json['notebook_id'] == null
          ? null
          : _asString(json['notebook_id']),
      relevance: rawRelevance is num ? rawRelevance.toDouble() : null,
    );
  }
}

/// `/api/auth/status` 的响应。
class AuthStatus {
  const AuthStatus({required this.authEnabled, required this.message});

  final bool authEnabled;
  final String message;

  factory AuthStatus.fromJson(Map<String, dynamic> json) {
    return AuthStatus(
      authEnabled: json['auth_enabled'] == true,
      message: _asString(json['message']),
    );
  }
}

/// `/api/config` 的响应（服务版本等）。
class ServerConfig {
  const ServerConfig({this.version, this.latestVersion, this.dbStatus});

  final String? version;
  final String? latestVersion;
  final String? dbStatus;

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      version: json['version'] == null ? null : _asString(json['version']),
      latestVersion: json['latestVersion'] == null
          ? null
          : _asString(json['latestVersion']),
      dbStatus: json['dbStatus'] == null ? null : _asString(json['dbStatus']),
    );
  }
}

/// 搜索请求参数（作为 Riverpod family 的缓存 key，需要值相等语义）。
class SearchQuery {
  const SearchQuery({
    required this.query,
    this.notebookIds = const [],
    this.type = 'text',
    this.limit = 30,
  });

  final String query;
  final List<String> notebookIds;
  final String type;
  final int limit;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchQuery &&
        other.query == query &&
        other.type == type &&
        other.limit == limit &&
        _listEquals(other.notebookIds, notebookIds);
  }

  @override
  int get hashCode => Object.hash(query, type, limit, Object.hashAll(notebookIds));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

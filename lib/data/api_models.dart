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

// ---------------------------------------------------------------------------
// 来源（Source）
// ---------------------------------------------------------------------------

/// 来源的处理状态。
///
/// 后端在 `status` 字段里返回这些取值（异步处理时先 `new` / `queued`，
/// 再由后台命令推进到 `running` / `completed` / `failed`）；老数据可能没有
/// `status`（`null`），这里统一收敛成 [SourceStatus.unknown]。
enum SourceStatus { newSource, queued, running, completed, failed, unknown }

SourceStatus _parseStatus(Object? value) {
  return switch (_asString(value).toLowerCase()) {
    'new' => SourceStatus.newSource,
    'queued' => SourceStatus.queued,
    'running' => SourceStatus.running,
    'processing' => SourceStatus.running,
    'completed' => SourceStatus.completed,
    'success' => SourceStatus.completed,
    'failed' => SourceStatus.failed,
    'error' => SourceStatus.failed,
    _ => SourceStatus.unknown,
  };
}

/// 来源类型（决定图标与「打不开文件」等提示）。
enum SourceKind { link, upload, text }

/// 一条「来源」：链接、上传的文件或纯文本，由后端抽取正文并可向量化。
class Source {
  const Source({
    required this.id,
    required this.title,
    required this.topics,
    required this.kind,
    required this.url,
    required this.filePath,
    required this.embedded,
    required this.embeddedChunks,
    required this.insightsCount,
    required this.status,
    required this.processingError,
    required this.created,
    required this.updated,
    this.fullText,
    this.fileAvailable,
    this.commandId,
    this.notebookIds = const [],
  });

  final String id;
  final String title;
  final List<String> topics;
  final SourceKind kind;

  /// 链接来源的 URL；其它类型为 null。
  final String? url;

  /// 上传来源在后端的文件路径；其它类型为 null。
  final String? filePath;

  final bool embedded;
  final int embeddedChunks;
  final int insightsCount;
  final SourceStatus status;

  /// 处理失败时的错误摘要（后端已截断，最多 200 字）。
  final String? processingError;

  final DateTime? created;
  final DateTime? updated;

  /// 详情接口才返回正文；列表接口通常为 null。
  final String? fullText;

  /// 上传文件是否仍在服务器上（`null` 表示不是文件来源 / 无法判定）。
  final bool? fileAvailable;

  final String? commandId;

  /// 详情接口返回它所属的笔记本 id 列表；列表接口为只读空集合。
  final List<String> notebookIds;

  bool get isProcessing =>
      status == SourceStatus.newSource ||
      status == SourceStatus.queued ||
      status == SourceStatus.running;

  bool get hasFailed => status == SourceStatus.failed;

  String get displayTitle {
    final value = title.trim();
    if (value.isNotEmpty) return value;
    final path = filePath ?? url;
    if (path == null || path.trim().isEmpty) return '未命名来源';
    final segments = path.split('/');
    return segments.isEmpty ? path : segments.last;
  }

  /// 列表里的正文摘要（详情接口有 [fullText] 时才能生成）。
  String snippet({int maxLength = 140}) {
    final text = fullText;
    if (text == null || text.trim().isEmpty) return '';
    return Source.snippetOf(text, maxLength: maxLength);
  }

  /// 对任意纯文本生成摘要（去掉多余空白并截断）。
  static String snippetOf(String text, {int maxLength = 140}) {
    final plain = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.length <= maxLength) return plain;
    return '${plain.substring(0, maxLength)}…';
  }

  factory Source.fromJson(Map<String, dynamic> json) {
    final asset = json['asset'];
    final assetMap = asset is Map ? Map<String, dynamic>.from(asset) : null;
    final url = assetMap?['url'] == null ? null : _asString(assetMap!['url']);
    final filePath =
        assetMap?['file_path'] == null ? null : _asString(assetMap!['file_path']);
    final topicsRaw = json['topics'];
    final notebooksRaw = json['notebooks'];
    final processingInfo = json['processing_info'];
    final error =
        processingInfo is Map ? processingInfo['error'] : null;
    return Source(
      id: _asString(json['id']),
      title: _asString(json['title']),
      topics: topicsRaw is List
          ? topicsRaw.map((topic) => _asString(topic)).where((t) => t.isNotEmpty).toList(growable: false)
          : const <String>[],
      kind: url != null && url.isNotEmpty
          ? SourceKind.link
          : (filePath != null && filePath.isNotEmpty
              ? SourceKind.upload
              : SourceKind.text),
      url: url,
      filePath: filePath,
      embedded: json['embedded'] == true,
      embeddedChunks: _asInt(json['embedded_chunks']),
      insightsCount: _asInt(json['insights_count']),
      status: _parseStatus(json['status']),
      processingError:
          error == null || _asString(error).trim().isEmpty ? null : _asString(error),
      created: parseServerDate(json['created']),
      updated: parseServerDate(json['updated']),
      fullText: json['full_text'] == null ? null : _asString(json['full_text']),
      fileAvailable:
          json['file_available'] is bool ? json['file_available'] as bool : null,
      commandId: json['command_id'] == null ? null : _asString(json['command_id']),
      notebookIds: notebooksRaw is List
          ? notebooksRaw.map((id) => _asString(id)).where((id) => id.isNotEmpty).toList(growable: false)
          : const <String>[],
    );
  }
}

/// 新建来源的三种输入方式。
enum SourceInputKind { link, text, upload }

/// 新建来源的请求参数（`POST /api/sources`）。
class CreateSourceRequest {
  const CreateSourceRequest({
    required this.kind,
    this.title,
    this.url,
    this.content,
    this.filePath,
    this.fileName,
    this.notebookIds = const [],
    this.embed = false,
    this.asyncProcessing = true,
  });

  final SourceInputKind kind;
  final String? title;
  final String? url;
  final String? content;

  /// 本地文件绝对路径（上传时由文件选择器给出）。
  final String? filePath;

  /// 上传时显式指定文件名（缺省取路径末段）。
  final String? fileName;

  final List<String> notebookIds;

  /// 是否请求后端做向量化（后端开关 `default_embedding_option` 由用户决定）。
  final bool embed;

  /// 是否异步处理：true 立即返回并在后台抽取正文，需轮询状态。
  final bool asyncProcessing;

  String get apiType => switch (kind) {
        SourceInputKind.link => 'link',
        SourceInputKind.text => 'text',
        SourceInputKind.upload => 'upload',
      };
}

/// 处理状态轮询结果（`GET /api/sources/{id}/status`）。
class SourceStatusInfo {
  const SourceStatusInfo({
    required this.status,
    required this.message,
    this.processingInfo,
    this.commandId,
  });

  final SourceStatus status;
  final String message;
  final Map<String, dynamic>? processingInfo;
  final String? commandId;

  factory SourceStatusInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['processing_info'];
    return SourceStatusInfo(
      status: _parseStatus(json['status']),
      message: _asString(json['message']),
      processingInfo: raw is Map ? Map<String, dynamic>.from(raw) : null,
      commandId: json['command_id'] == null ? null : _asString(json['command_id']),
    );
  }
}

/// 来源的一则「洞见」（后端用 transformation 生成的摘要 / 要点）。
class SourceInsight {
  const SourceInsight({
    required this.id,
    required this.sourceId,
    required this.insightType,
    required this.content,
    this.created,
    this.updated,
  });

  final String id;
  final String sourceId;
  final String insightType;
  final String content;
  final DateTime? created;
  final DateTime? updated;

  factory SourceInsight.fromJson(Map<String, dynamic> json) {
    return SourceInsight(
      id: _asString(json['id']),
      sourceId: _asString(json['source_id']),
      insightType: _asString(json['insight_type'], fallback: 'Insight'),
      content: _asString(json['content']),
      created: parseServerDate(json['created']),
      updated: parseServerDate(json['updated']),
    );
  }
}

// ---------------------------------------------------------------------------
// 对话（Chat）
// ---------------------------------------------------------------------------

/// 对话消息：用户提问或 AI 回复。
enum ChatRole { human, ai, system, unknown }

ChatRole _parseRole(Object? value) {
  return switch (_asString(value).toLowerCase()) {
    'human' || 'user' => ChatRole.human,
    'ai' || 'assistant' => ChatRole.ai,
    'system' => ChatRole.system,
    _ => ChatRole.unknown,
  };
}

/// 一条对话消息。
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
    this.pending = false,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime? timestamp;

  /// 客户端乐观插入、尚未得到后端确认的消息。
  final bool pending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: _asString(json['id']),
      role: _parseRole(json['type']),
      content: _asString(json['content']),
      timestamp: parseServerDate(json['timestamp']),
    );
  }

  /// 乐观插入的用户消息。
  factory ChatMessage.pendingHuman(String content) => ChatMessage(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        role: ChatRole.human,
        content: content,
        timestamp: DateTime.now().toUtc(),
        pending: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': role == ChatRole.human ? 'human' : 'ai',
        'content': content,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };
}

/// 笔记本对话的一个会话（`/api/chat/sessions`）。
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    this.notebookId,
    this.created,
    this.updated,
    this.messageCount,
    this.modelOverride,
  });

  final String id;
  final String title;
  final String? notebookId;
  final DateTime? created;
  final DateTime? updated;
  final int? messageCount;

  /// 会话级模型覆盖（`model:<id>`）；null 表示使用后端默认对话模型。
  final String? modelOverride;

  String get displayTitle {
    final value = title.trim();
    return value.isEmpty ? '未命名会话' : value;
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: _asString(json['id']),
      title: _asString(json['title']),
      notebookId: json['notebook_id'] == null ? null : _asString(json['notebook_id']),
      created: parseServerDate(json['created']),
      updated: parseServerDate(json['updated']),
      messageCount:
          json['message_count'] == null ? null : _asInt(json['message_count']),
      modelOverride:
          json['model_override'] == null ? null : _asString(json['model_override']),
    );
  }
}

/// 服务端模型（对话时可用于「模型覆盖」）。
class LanguageModel {
  const LanguageModel({
    required this.id,
    required this.name,
    required this.provider,
    required this.type,
  });

  final String id;
  final String name;
  final String provider;
  final String type;

  bool get isLanguage => type == 'language';

  factory LanguageModel.fromJson(Map<String, dynamic> json) {
    return LanguageModel(
      id: _asString(json['id']),
      name: _asString(json['name'], fallback: '未知模型'),
      provider: _asString(json['provider']),
      type: _asString(json['type']),
    );
  }
}

/// 后端的默认模型配置（`GET /api/models/defaults`）。
class ModelDefaults {
  const ModelDefaults({this.defaultChatModel, this.defaultEmbeddingModel});

  final String? defaultChatModel;
  final String? defaultEmbeddingModel;

  factory ModelDefaults.fromJson(Map<String, dynamic> json) {
    return ModelDefaults(
      defaultChatModel: json['default_chat_model'] == null
          ? null
          : _asString(json['default_chat_model']),
      defaultEmbeddingModel: json['default_embedding_model'] == null
          ? null
          : _asString(json['default_embedding_model']),
    );
  }
}

/// 对话上下文：交给 `POST /api/chat/context` 生成，再原样传给
/// `POST /api/chat/execute`。
///
/// 形状由后端 `build_notebook_context` 决定：
/// `{"sources": [{"id","title","insights","full_text"}], "notes": [...]}`。
class ChatContext {
  const ChatContext({required this.sources, required this.notes});

  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> notes;

  bool get isEmpty => sources.isEmpty && notes.isEmpty;

  int get sourceCount => sources.length;

  int get noteCount => notes.length;

  factory ChatContext.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parse(Object? value) {
      if (value is! List) return const <Map<String, dynamic>>[];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    return ChatContext(
      sources: parse(json['sources']),
      notes: parse(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => {'sources': sources, 'notes': notes};

  static const ChatContext empty =
      ChatContext(sources: <Map<String, dynamic>>[], notes: <Map<String, dynamic>>[]);
}

/// `POST /api/chat/context` 的响应：上下文 + 粗略的 token / 字符数。
class BuiltChatContext {
  const BuiltChatContext({
    required this.context,
    required this.tokenCount,
    required this.charCount,
  });

  final ChatContext context;
  final int tokenCount;
  final int charCount;

  factory BuiltChatContext.fromJson(Map<String, dynamic> json) {
    final raw = json['context'];
    return BuiltChatContext(
      context: raw is Map
          ? ChatContext.fromJson(Map<String, dynamic>.from(raw))
          : ChatContext.empty,
      tokenCount: _asInt(json['token_count']),
      charCount: _asInt(json['char_count']),
    );
  }
}

/// 某个条目（来源 / 笔记）是否参与本轮对话的上下文。
enum ContextMode {
  /// 不放进上下文。
  off,

  /// 只放来源的「洞见」摘要（笔记没有该模式，会自动降级为 [full]）。
  insights,

  /// 放完整正文。
  full,
}

extension ContextModeApi on ContextMode {
  /// 后端约定的状态字符串（见 `open_notebook/utils/context_builder.py`）。
  ///
  /// 后端用**子串匹配**：包含 `not in` 直接跳过，包含 `insights` 取短上下文，
  /// 包含 `full content` 取长上下文。因此这里必须与后端字符串完全对齐。
  String get apiValue => switch (this) {
        ContextMode.off => 'not in',
        ContextMode.insights => 'insights',
        ContextMode.full => 'full content',
      };
}

/// 对话上下文的勾选状态：`id → 模式`。
///
/// 作为 Riverpod family 的缓存 key 需要值相等语义。
class ChatContextSelection {
  const ChatContextSelection({
    this.sources = const <String, ContextMode>{},
    this.notes = const <String, ContextMode>{},
  });

  /// `source:<id>` → 模式。
  final Map<String, ContextMode> sources;

  /// `note:<id>` → 模式（只有 [ContextMode.off] / [ContextMode.full]）。
  final Map<String, ContextMode> notes;

  ChatContextSelection copyWith({
    Map<String, ContextMode>? sources,
    Map<String, ContextMode>? notes,
  }) {
    return ChatContextSelection(
      sources: sources ?? this.sources,
      notes: notes ?? this.notes,
    );
  }

  /// 转成后端 `context_config`：`{sources: {...}, notes: {...}}`。
  Map<String, dynamic> toRequestConfig() => {
        'sources': {
          for (final entry in sources.entries) entry.key: entry.value.apiValue,
        },
        'notes': {
          for (final entry in notes.entries) entry.key: entry.value.apiValue,
        },
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatContextSelection &&
        _mapEquals(other.sources, sources) &&
        _mapEquals(other.notes, notes);
  }

  @override
  int get hashCode => Object.hash(_mapHash(sources), _mapHash(notes));

  static bool _mapEquals(Map<String, ContextMode> a, Map<String, ContextMode> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static int _mapHash(Map<String, ContextMode> value) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(entries.map((e) => Object.hash(e.key, e.value)));
  }
}

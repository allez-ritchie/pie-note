import 'api_client.dart';
import 'api_models.dart';

/// 连接测试结果。
class ConnectionTestResult {
  const ConnectionTestResult._({
    required this.ok,
    this.message = '',
    this.serverVersion,
    this.authEnabled = true,
  });

  factory ConnectionTestResult.success({
    required String serverVersion,
    bool authEnabled = true,
  }) =>
      ConnectionTestResult._(
        ok: true,
        message: '连接成功',
        serverVersion: serverVersion,
        authEnabled: authEnabled,
      );

  factory ConnectionTestResult.failure(String message) =>
      ConnectionTestResult._(ok: false, message: message);

  final bool ok;
  final String message;
  final String? serverVersion;
  final bool authEnabled;
}

/// 业务门面：把 API 调用收敛到一处，UI/provider 不直接依赖 [ApiClient]。
///
/// 同时提供少量跨接口组合查询（例如按标题解析 `[[wiki 链接]]`）。
class NoteRepository {
  NoteRepository(this._client);

  final ApiClient _client;

  ApiClient get client => _client;

  // ---------------------------------------------------------------------------
  // 探测
  // ---------------------------------------------------------------------------

  /// 完整连接测试：探测鉴权状态 → 校验密码（拉笔记本列表）→ 读取服务版本。
  ///
  /// 密码为空但后端启用了鉴权时直接返回失败，避免发出注定 401 的请求。
  Future<ConnectionTestResult> testConnection() async {
    try {
      final authStatus = await _client.fetchAuthStatus();
      if (authStatus.authEnabled && !_client.hasPassword) {
        return ConnectionTestResult.failure('该后端启用了密码鉴权，请输入访问密码');
      }
      // 真正会走鉴权的请求，用来验证密码是否正确。
      await _client.fetchNotebooks();
      String version = '未知版本';
      try {
        final config = await _client.fetchServerConfig();
        version = config.version ?? version;
      } on ApiException {
        // 版本信息拿不到不影响连接判定（老版本可能没有 /api/config）。
      }
      return ConnectionTestResult.success(
        serverVersion: version,
        authEnabled: authStatus.authEnabled,
      );
    } on ApiException catch (e) {
      return ConnectionTestResult.failure(e.message);
    } catch (_) {
      return ConnectionTestResult.failure('连接失败，请检查后端地址与网络');
    }
  }

  // ---------------------------------------------------------------------------
  // 笔记本
  // ---------------------------------------------------------------------------

  Future<List<Notebook>> fetchNotebooks({bool? archived}) =>
      _client.fetchNotebooks(archived: archived);

  Future<Notebook> fetchNotebook(String id) => _client.fetchNotebook(id);

  Future<Notebook> createNotebook({required String name, String description = ''}) =>
      _client.createNotebook(name: name, description: description);

  Future<Notebook> updateNotebook(
    String id, {
    String? name,
    String? description,
    bool? archived,
  }) =>
      _client.updateNotebook(id, name: name, description: description, archived: archived);

  Future<void> deleteNotebook(String id) => _client.deleteNotebook(id);

  // ---------------------------------------------------------------------------
  // 笔记
  // ---------------------------------------------------------------------------

  Future<List<Note>> fetchNotes({String? notebookId}) =>
      _client.fetchNotes(notebookId: notebookId);

  Future<Note> fetchNote(String id) => _client.fetchNote(id);

  Future<Note> createNote({
    String? title,
    required String content,
    String? noteType,
    String? notebookId,
  }) =>
      _client.createNote(
        title: title,
        content: content,
        noteType: noteType,
        notebookId: notebookId,
      );

  Future<Note> updateNote(
    String id, {
    String? title,
    String? content,
    String? noteType,
  }) =>
      _client.updateNote(id, title: title, content: content, noteType: noteType);

  Future<void> deleteNote(String id) => _client.deleteNote(id);

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------

  Future<List<SearchHit>> search({
    required String query,
    String type = 'text',
    int limit = 30,
    List<String>? notebookIds,
  }) =>
      _client.search(query: query, type: type, limit: limit, notebookIds: notebookIds);

  /// 在全部笔记中按标题查找（用于 `[[wiki 链接]]` 跳转）。
  ///
  /// 大小写与首尾空白不敏感；找不到返回 null。
  Future<Note?> findNoteByTitle(String title) async {
    final target = title.trim().toLowerCase();
    if (target.isEmpty) return null;
    final notes = await _client.fetchNotes();
    for (final note in notes) {
      if (note.displayTitle.trim().toLowerCase() == target) return note;
      if (note.title.trim().toLowerCase() == target) return note;
    }
    return null;
  }
}

/// 来源相关调用的业务门面。
///
/// 单独抽一个仓库类是为了不把 `NoteRepository` 撑得更大，同时保持
/// 「UI/provider 不直接依赖 [ApiClient]」的约定。
class SourceRepository {
  SourceRepository(this._client);

  final ApiClient _client;

  Future<List<Source>> fetchSources({String? notebookId}) =>
      _client.fetchSources(notebookId: notebookId);

  Future<Source> fetchSource(String id) => _client.fetchSource(id);

  Future<Source> createSource(CreateSourceRequest request) =>
      _client.createSource(request);

  Future<SourceStatusInfo> fetchStatus(String id) => _client.fetchSourceStatus(id);

  Future<Source> retry(String id) => _client.retrySource(id);

  Future<void> deleteSource(String id) => _client.deleteSource(id);

  Future<List<SourceInsight>> fetchInsights(String id) =>
      _client.fetchSourceInsights(id);

  Future<Source> renameSource(String id, String title) =>
      _client.updateSource(id, title: title);
}

/// 笔记本对话的业务门面（会话 + 上下文 + 一轮问答）。
class ChatRepository {
  ChatRepository(this._client);

  final ApiClient _client;

  Future<List<ChatSession>> fetchSessions(String notebookId) =>
      _client.fetchChatSessions(notebookId);

  Future<ChatSession> createSession({
    required String notebookId,
    String? title,
    String? modelOverride,
  }) =>
      _client.createChatSession(
        notebookId: notebookId,
        title: title,
        modelOverride: modelOverride,
      );

  Future<({ChatSession session, List<ChatMessage> messages})> fetchSession(
    String sessionId,
  ) =>
      _client.fetchChatSession(sessionId);

  Future<ChatSession> renameSession(String sessionId, String title) =>
      _client.updateChatSession(sessionId, title: title);

  /// 设置 / 清除会话级模型覆盖（`null` 表示回到后端默认模型）。
  Future<ChatSession> setSessionModel(String sessionId, String? modelId) =>
      _client.updateChatSession(sessionId, modelOverride: modelId);

  Future<void> deleteSession(String sessionId) =>
      _client.deleteChatSession(sessionId);

  Future<BuiltChatContext> buildContext({
    required String notebookId,
    required ChatContextSelection selection,
  }) =>
      _client.buildChatContext(notebookId: notebookId, selection: selection);

  Future<List<ChatMessage>> execute({
    required String sessionId,
    required String message,
    required ChatContext context,
    String? modelOverride,
    bool includeModelOverride = false,
  }) =>
      _client.executeChat(
        sessionId: sessionId,
        message: message,
        context: context,
        modelOverride: modelOverride,
        includeModelOverride: includeModelOverride,
      );

  /// 服务端可用的对话模型 + 默认对话模型。
  Future<({List<LanguageModel> models, String? defaultChatModel})> fetchModels() async {
    final models = await _client.fetchModels();
    String? defaultChatModel;
    try {
      defaultChatModel = (await _client.fetchModelDefaults()).defaultChatModel;
    } on ApiException {
      // 默认模型拿不到不影响选择列表，按「后端默认」展示即可。
    }
    return (
      models: models
          .where((model) => model.isLanguage)
          .toList(growable: false)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      defaultChatModel: defaultChatModel,
    );
  }
}

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

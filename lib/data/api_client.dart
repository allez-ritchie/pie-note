import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_models.dart';

/// HTTP 层统一异常。
///
/// 只暴露可读消息与状态码，**不包含**请求头（里面有密码）。
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.kind = ApiErrorKind.unknown,
  });

  final String message;
  final int? statusCode;
  final ApiErrorKind kind;

  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  bool get isNetwork => kind == ApiErrorKind.network;

  factory ApiException.network([String? message]) => ApiException(
        message ?? '无法连接到服务器，请检查后端地址与网络',
        kind: ApiErrorKind.network,
      );

  factory ApiException.timeout() =>
      const ApiException('连接超时，请检查后端地址与网络', kind: ApiErrorKind.network);

  factory ApiException.unauthorized([String? message]) => ApiException(
        message ?? '鉴权失败，请检查访问密码',
        statusCode: 401,
        kind: ApiErrorKind.unauthorized,
      );

  factory ApiException.fromStatus(int statusCode, String body) {
    final detail = _extractDetail(body);
    switch (statusCode) {
      case 401:
        return const ApiException(
          '鉴权失败，请检查访问密码',
          statusCode: 401,
          kind: ApiErrorKind.unauthorized,
        );
      case 403:
        return const ApiException(
          '没有权限执行该操作',
          statusCode: 403,
          kind: ApiErrorKind.forbidden,
        );
      case 404:
        return const ApiException(
          '资源不存在，可能已被删除',
          statusCode: 404,
          kind: ApiErrorKind.notFound,
        );
      case 422:
        return ApiException(
          detail.isEmpty ? '请求参数不合法' : detail,
          statusCode: 422,
          kind: ApiErrorKind.badRequest,
        );
      default:
        final suffix = detail.isEmpty ? '' : '：$detail';
        if (statusCode >= 500) {
          return ApiException(
            '服务器内部错误（$statusCode）$suffix',
            statusCode: statusCode,
            kind: ApiErrorKind.server,
          );
        }
        return ApiException(
          '请求失败（$statusCode）$suffix',
          statusCode: statusCode,
          kind: ApiErrorKind.unknown,
        );
    }
  }

  /// 从 FastAPI 的错误体里提取 `detail`。`detail` 既可能是字符串，
  /// 也可能是校验错误数组，这里只保留可读文本。
  static String _extractDetail(String body) {
    if (body.isEmpty) return '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] is String) return first['msg'] as String;
        }
      }
      if (decoded is String) return decoded;
    } catch (_) {
      // 非 JSON 错误体：截断原始文本，避免把 HTML 整页塞进提示。
      final trimmed = body.trim();
      return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
    }
    return '';
  }

  @override
  String toString() => message;
}

enum ApiErrorKind { unauthorized, forbidden, notFound, badRequest, server, network, unknown }

/// 归一化用户输入的 Base URL：
/// - 去掉首尾空白与尾部 `/`；
/// - 缺少 scheme 时补 `http://`；
/// - 只接受 `http` / `https`，且必须有 host。
///
/// 非法输入抛 [ApiException]（kind 为 badRequest），由 UI 转成表单错误提示。
String normalizeBaseUrl(String raw) {
  // 中文输入法常把半角标点转成全角（`：`、`。`、`／`），这里先做一次归一化，
  // 避免用户粘贴/输入 `http：／／192。168。31。24：5055` 时被判为非法地址。
  var input = _normalizeFullWidth(raw).trim();
  if (input.isEmpty) {
    throw const ApiException('后端地址不能为空', kind: ApiErrorKind.badRequest);
  }
  if (!input.contains('://')) {
    input = 'http://$input';
  }
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasScheme) {
    throw const ApiException('后端地址格式不正确', kind: ApiErrorKind.badRequest);
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const ApiException('后端地址只支持 http 或 https', kind: ApiErrorKind.badRequest);
  }
  if (uri.host.isEmpty) {
    throw const ApiException('后端地址缺少主机名或 IP', kind: ApiErrorKind.badRequest);
  }
  // 保留可能存在的反向代理子路径，只去掉末尾斜杠。
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return Uri(
    scheme: scheme,
    userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

/// 把全角 ASCII（U+FF01–U+FF5E）与全角空格统一转成半角。
///
/// 中文输入法常把 `:` `.` `/` 甚至数字打成全角，用户不应因此无法保存配置。
/// 全角 ASCII 与半角 ASCII 相差固定 0xFEE0，按码位整体偏移即可。
String _normalizeFullWidth(String raw) {
  final buffer = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x3000) {
      // 全角空格
      buffer.write(' ');
    } else if (rune == 0x3002) {
      // 中文句号「。」常被输入法当作小数点
      buffer.write('.');
    } else if (rune == 0x3001) {
      // 顿号
      buffer.write(',');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Open Notebook REST 客户端。
///
/// 所有请求统一走这里：注入 `Authorization: Bearer <password>`、超时控制、
/// 错误映射。业务层不要自行拼装请求头或直接使用 `http`。
/// 「未传该字段」与「显式传 null」不同的哨兵值（`PUT` 会话的 model_override）。
const Object _unset = Object();

class ApiClient {
  ApiClient({
    required String baseUrl,
    required String? password,
    http.Client? httpClient,
    Duration? timeout,
    Duration? uploadTimeout,
    Duration? longTimeout,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _password = (password == null || password.isEmpty) ? null : password,
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 20),
        _uploadTimeout = uploadTimeout ?? const Duration(minutes: 5),
        _longTimeout = longTimeout ?? const Duration(minutes: 5);

  final String baseUrl;
  final String? _password;
  final http.Client _http;
  final Duration _timeout;

  /// 上传文件 / 后端同步抽取正文可能耗时几分钟，单独给更长的超时。
  final Duration _uploadTimeout;

  /// LLM 生成类请求（对话、上下文构建）的读超时。
  ///
  /// 后端 `/api/chat/execute` 是同步接口：模型回答完整生成后才返回，
  /// 20 秒的默认超时几乎必然超时，这里给 5 分钟。
  final Duration _longTimeout;

  bool get hasPassword => _password != null;

  Map<String, String> _headers({bool useAuth = true}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
    };
    final password = _password;
    if (useAuth && password != null) {
      headers['Authorization'] = 'Bearer $password';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$baseUrl$normalizedPath');
    if (query == null || query.isEmpty) return base;
    final queryParameters = <String, String>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      queryParameters[key] = value.toString();
    });
    if (queryParameters.isEmpty) return base;
    return base.replace(queryParameters: {...base.queryParameters, ...queryParameters});
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Duration? timeout,
    bool useAuth = true,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers.addAll(_headers(useAuth: useAuth));
    if (body != null) {
      request.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(request).timeout(timeout ?? _timeout);
      final response = await http.Response.fromStream(streamed);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (text.trim().isEmpty) return null;
        try {
          return jsonDecode(text);
        } catch (_) {
          return text;
        }
      }
      throw ApiException.fromStatus(response.statusCode, text);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }
  }

  /// 上传文件（multipart/form-data）。
  ///
  /// 与 [_send] 共用鉴权、错误映射与超时；`Content-Type` 不能手写 boundary，
  /// 所以这里单独构造 [http.MultipartRequest]，只注入 `Accept` 与鉴权头。
  Future<dynamic> _sendMultipart(
    String path, {
    required Map<String, String> fields,
    String? filePath,
    String? fileName,
    Duration? timeout,
  }) async {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll({
      'Accept': 'application/json',
      ..._authHeader(),
    });
    request.fields.addAll(fields);
    if (filePath != null) {
      try {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: fileName,
          ).timeout(const Duration(seconds: 30)),
        );
      } on Object {
        throw const ApiException('读取本地文件失败', kind: ApiErrorKind.badRequest);
      }
    }
    try {
      final streamed =
          await _http.send(request).timeout(timeout ?? _uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (text.trim().isEmpty) return null;
        try {
          return jsonDecode(text);
        } catch (_) {
          return text;
        }
      }
      throw ApiException.fromStatus(response.statusCode, text);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    } catch (_) {
      throw ApiException.network();
    }
  }

  Map<String, String> _authHeader({bool useAuth = true}) {
    final password = _password;
    if (!useAuth || password == null) return const <String, String>{};
    return <String, String>{'Authorization': 'Bearer $password'};
  }

  Future<Map<String, dynamic>> _getObject(
    String path, {
    Map<String, dynamic>? query,
    bool useAuth = true,
  }) async {
    final data = await _send('GET', path, query: query, useAuth: useAuth);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('服务器返回了非预期的数据格式', kind: ApiErrorKind.server);
  }

  Future<List<dynamic>> _getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final data = await _send('GET', path, query: query);
    if (data is List) return data;
    throw const ApiException('服务器返回了非预期的数据格式', kind: ApiErrorKind.server);
  }

  // ---------------------------------------------------------------------------
  // 探测与配置
  // ---------------------------------------------------------------------------

  /// 探测后端是否启用密码鉴权（不需要密码）。
  Future<AuthStatus> fetchAuthStatus() async {
    final json = await _getObject('/api/auth/status', useAuth: false);
    return AuthStatus.fromJson(json);
  }

  /// 后端版本与数据库状态（需要鉴权）。
  Future<ServerConfig> fetchServerConfig() async {
    final json = await _getObject('/api/config');
    return ServerConfig.fromJson(json);
  }

  /// 健康检查（不需要鉴权）。
  Future<void> ping() async {
    await _send('GET', '/health', useAuth: false);
  }

  // ---------------------------------------------------------------------------
  // 笔记本
  // ---------------------------------------------------------------------------

  Future<List<Notebook>> fetchNotebooks({
    bool? archived,
    String orderBy = 'updated desc',
  }) async {
    final list = await _getList('/api/notebooks', query: {
      if (archived != null) 'archived': archived,
      'order_by': orderBy,
    });
    return list
        .whereType<Map>()
        .map((json) => Notebook.fromJson(Map<String, dynamic>.from(json)))
        .where((notebook) => notebook.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Notebook> fetchNotebook(String id) async {
    final json = await _getObject('/api/notebooks/${Uri.encodeComponent(id)}');
    return Notebook.fromJson(json);
  }

  Future<Notebook> createNotebook({
    required String name,
    String description = '',
  }) async {
    final data = await _send('POST', '/api/notebooks', body: {
      'name': name,
      'description': description,
    });
    return Notebook.fromJson(_asMap(data));
  }

  Future<Notebook> updateNotebook(
    String id, {
    String? name,
    String? description,
    bool? archived,
  }) async {
    final data = await _send('PUT', '/api/notebooks/${Uri.encodeComponent(id)}', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (archived != null) 'archived': archived,
    });
    return Notebook.fromJson(_asMap(data));
  }

  Future<void> deleteNotebook(
    String id, {
    bool deleteExclusiveSources = false,
  }) async {
    await _send(
      'DELETE',
      '/api/notebooks/${Uri.encodeComponent(id)}',
      query: {'delete_exclusive_sources': deleteExclusiveSources},
    );
  }

  // ---------------------------------------------------------------------------
  // 笔记
  // ---------------------------------------------------------------------------

  Future<List<Note>> fetchNotes({String? notebookId, String orderBy = 'updated desc'}) async {
    final list = await _getList('/api/notes', query: {
      if (notebookId != null && notebookId.isNotEmpty) 'notebook_id': notebookId,
    });
    return list
        .whereType<Map>()
        .map((json) => Note.fromJson(Map<String, dynamic>.from(json)))
        .where((note) => note.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Note> fetchNote(String id) async {
    final json = await _getObject('/api/notes/${Uri.encodeComponent(id)}');
    return Note.fromJson(json);
  }

  Future<Note> createNote({
    String? title,
    required String content,
    String? noteType,
    String? notebookId,
  }) async {
    final data = await _send('POST', '/api/notes', body: {
      if (title != null) 'title': title,
      'content': content,
      if (noteType != null) 'note_type': noteType,
      if (notebookId != null && notebookId.isNotEmpty) 'notebook_id': notebookId,
    });
    return Note.fromJson(_asMap(data));
  }

  Future<Note> updateNote(
    String id, {
    String? title,
    String? content,
    String? noteType,
  }) async {
    final data = await _send('PUT', '/api/notes/${Uri.encodeComponent(id)}', body: {
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (noteType != null) 'note_type': noteType,
    });
    return Note.fromJson(_asMap(data));
  }

  Future<void> deleteNote(String id) async {
    await _send('DELETE', '/api/notes/${Uri.encodeComponent(id)}');
  }

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------

  Future<List<SearchHit>> search({
    required String query,
    String type = 'text',
    int limit = 30,
    List<String>? notebookIds,
  }) async {
    final data = await _send('POST', '/api/search', body: {
      'query': query,
      'type': type,
      'limit': limit,
      if (notebookIds != null && notebookIds.isNotEmpty)
        'notebook_ids': notebookIds,
    });
    final map = _asMap(data);
    final results = map['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((json) => SearchHit.fromJson(Map<String, dynamic>.from(json)))
        .where((hit) => hit.hasNoteId)
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 来源（Source）
  // ---------------------------------------------------------------------------

  /// 来源列表；[notebookId] 为 null 时返回全部来源。
  ///
  /// 后端单页上限 100 条，这里按 [limit] 请求并把 `limit` 压到 1..100。
  Future<List<Source>> fetchSources({
    String? notebookId,
    int limit = 50,
    int offset = 0,
  }) async {
    final list = await _getList('/api/sources', query: {
      if (notebookId != null && notebookId.isNotEmpty) 'notebook_id': notebookId,
      'limit': limit.clamp(1, 100),
      'offset': offset < 0 ? 0 : offset,
      'sort_by': 'updated',
      'sort_order': 'desc',
    });
    return list
        .whereType<Map>()
        .map((json) => Source.fromJson(Map<String, dynamic>.from(json)))
        .where((source) => source.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<Source> fetchSource(String id) async {
    final json = await _getObject('/api/sources/${Uri.encodeComponent(id)}');
    return Source.fromJson(json);
  }

  /// 新建来源。
  ///
  /// 一律走 multipart 表单（与官方前端一致）：`/api/sources` 的入参由
  /// FastAPI 的 `Form` + `File` 定义，`/api/sources/json` 只是兼容用的
  /// legacy 端点，且拿不到文件上传能力，所以这里只用前者。
  Future<Source> createSource(CreateSourceRequest request) async {
    final fields = <String, String>{
      'type': request.apiType,
      if (request.title != null && request.title!.trim().isNotEmpty)
        'title': request.title!.trim(),
      if (request.url != null) 'url': request.url!,
      if (request.content != null) 'content': request.content!,
      if (request.notebookIds.isNotEmpty)
        'notebooks': jsonEncode(request.notebookIds),
      'embed': request.embed ? 'true' : 'false',
      'delete_source': 'false',
      'async_processing': request.asyncProcessing ? 'true' : 'false',
    };
    final data = await _sendMultipart(
      '/api/sources',
      fields: fields,
      filePath: request.kind == SourceInputKind.upload ? request.filePath : null,
      fileName: request.fileName,
    );
    return Source.fromJson(_asMap(data));
  }

  /// 来源处理状态（异步处理时轮询用）。
  Future<SourceStatusInfo> fetchSourceStatus(String id) async {
    final json = await _getObject('/api/sources/${Uri.encodeComponent(id)}/status');
    return SourceStatusInfo.fromJson(json);
  }

  Future<void> deleteSource(String id) async {
    await _send('DELETE', '/api/sources/${Uri.encodeComponent(id)}');
  }

  /// 重新处理一个失败 / 卡住的来源。
  Future<Source> retrySource(String id) async {
    final data = await _send('POST', '/api/sources/${Uri.encodeComponent(id)}/retry');
    return Source.fromJson(_asMap(data));
  }

  Future<Source> updateSource(
    String id, {
    String? title,
    List<String>? topics,
  }) async {
    final data = await _send('PUT', '/api/sources/${Uri.encodeComponent(id)}', body: {
      if (title != null) 'title': title,
      if (topics != null) 'topics': topics,
    });
    return Source.fromJson(_asMap(data));
  }

  /// 来源的「洞见」列表（transformation 生成的结构化摘要）。
  Future<List<SourceInsight>> fetchSourceInsights(String id) async {
    final list =
        await _getList('/api/sources/${Uri.encodeComponent(id)}/insights');
    return list
        .whereType<Map>()
        .map((json) => SourceInsight.fromJson(Map<String, dynamic>.from(json)))
        .toList(growable: false);
  }

  /// 把已有来源加入笔记本（幂等）。
  Future<void> addSourceToNotebook(String notebookId, String sourceId) async {
    await _send(
      'POST',
      '/api/notebooks/${Uri.encodeComponent(notebookId)}'
          '/sources/${Uri.encodeComponent(sourceId)}',
    );
  }

  /// 从笔记本移除来源关联（不删除来源本身）。
  Future<void> removeSourceFromNotebook(String notebookId, String sourceId) async {
    await _send(
      'DELETE',
      '/api/notebooks/${Uri.encodeComponent(notebookId)}'
          '/sources/${Uri.encodeComponent(sourceId)}',
    );
  }

  // ---------------------------------------------------------------------------
  // 对话（Chat）
  // ---------------------------------------------------------------------------

  /// 某个笔记本的对话会话列表。
  Future<List<ChatSession>> fetchChatSessions(String notebookId) async {
    final list = await _getList('/api/chat/sessions', query: {
      'notebook_id': notebookId,
    });
    return list
        .whereType<Map>()
        .map((json) => ChatSession.fromJson(Map<String, dynamic>.from(json)))
        .where((session) => session.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<ChatSession> createChatSession({
    required String notebookId,
    String? title,
    String? modelOverride,
  }) async {
    final data = await _send('POST', '/api/chat/sessions', body: {
      'notebook_id': notebookId,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (modelOverride != null) 'model_override': modelOverride,
    });
    return ChatSession.fromJson(_asMap(data));
  }

  /// 会话详情（含消息列表）。
  Future<({ChatSession session, List<ChatMessage> messages})> fetchChatSession(
    String sessionId,
  ) async {
    final json =
        await _getObject('/api/chat/sessions/${Uri.encodeComponent(sessionId)}');
    final messages = json['messages'];
    return (
      session: ChatSession.fromJson(json),
      messages: messages is List
          ? messages
              .whereType<Map>()
              .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const <ChatMessage>[],
    );
  }

  Future<ChatSession> updateChatSession(
    String sessionId, {
    String? title,
    Object? modelOverride = _unset,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (!identical(modelOverride, _unset)) body['model_override'] = modelOverride;
    final data = await _send(
      'PUT',
      '/api/chat/sessions/${Uri.encodeComponent(sessionId)}',
      body: body,
    );
    return ChatSession.fromJson(_asMap(data));
  }

  Future<void> deleteChatSession(String sessionId) async {
    await _send('DELETE', '/api/chat/sessions/${Uri.encodeComponent(sessionId)}');
  }

  /// 构建对话上下文（由后端按 `context_config` 决定放哪些来源 / 笔记）。
  Future<BuiltChatContext> buildChatContext({
    required String notebookId,
    required ChatContextSelection selection,
  }) async {
    final data = await _send(
      'POST',
      '/api/chat/context',
      body: {
        'notebook_id': notebookId,
        'context_config': selection.toRequestConfig(),
      },
      timeout: _longTimeout,
    );
    return BuiltChatContext.fromJson(_asMap(data));
  }

  /// 执行一轮对话；后端同步返回**完整的消息列表**（不是增量）。
  ///
  /// [modelOverride] 为 `model:<id>` 时覆盖会话级 / 默认模型，null 表示用会话
  /// 或后端默认（显式 null 会被 JSON 编码成 null，与「不传」语义不同，因此
  /// 用 [includeModelOverride] 区分）。
  Future<List<ChatMessage>> executeChat({
    required String sessionId,
    required String message,
    required ChatContext context,
    String? modelOverride,
    bool includeModelOverride = false,
  }) async {
    final data = await _send(
      'POST',
      '/api/chat/execute',
      body: {
        'session_id': sessionId,
        'message': message,
        'context': context.toJson(),
        if (includeModelOverride) 'model_override': modelOverride,
      },
      timeout: _longTimeout,
    );
    final map = _asMap(data);
    final messages = map['messages'];
    if (messages is! List) return const <ChatMessage>[];
    return messages
        .whereType<Map>()
        .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // 模型（对话的「模型覆盖」需要）
  // ---------------------------------------------------------------------------

  /// 服务端已注册的模型列表。
  Future<List<LanguageModel>> fetchModels() async {
    final list = await _getList('/api/models');
    return list
        .whereType<Map>()
        .map((json) => LanguageModel.fromJson(Map<String, dynamic>.from(json)))
        .toList(growable: false);
  }

  /// 服务端默认模型配置。
  Future<ModelDefaults> fetchModelDefaults() async {
    final json = await _getObject('/api/models/defaults');
    return ModelDefaults.fromJson(json);
  }

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('服务器返回了非预期的数据格式', kind: ApiErrorKind.server);
  }

  void dispose() {
    _http.close();
  }
}

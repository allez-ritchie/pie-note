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
  var input = raw.trim();
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

/// Open Notebook REST 客户端。
///
/// 所有请求统一走这里：注入 `Authorization: Bearer <password>`、超时控制、
/// 错误映射。业务层不要自行拼装请求头或直接使用 `http`。
class ApiClient {
  ApiClient({
    required String baseUrl,
    required String? password,
    http.Client? httpClient,
    Duration? timeout,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _password = (password == null || password.isEmpty) ? null : password,
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 20);

  final String baseUrl;
  final String? _password;
  final http.Client _http;
  final Duration _timeout;

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

  static Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ApiException('服务器返回了非预期的数据格式', kind: ApiErrorKind.server);
  }

  void dispose() {
    _http.close();
  }
}

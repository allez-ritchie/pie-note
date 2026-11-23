import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/api_models.dart';
import '../data/config_store.dart';
import '../data/note_repository.dart';

/// 配置存储。测试可通过 `overrideWithValue` 注入内存实现。
final configStoreProvider = Provider<ConfigStore>((ref) => ConfigStore());

/// 应用配置（Base URL + 密码）状态。
///
/// `AsyncValue` 的三态用于根 widget 决定「启动中 / 配置页 / 主界面」。
class AppConfigNotifier extends AsyncNotifier<AppConfig> {
  @override
  Future<AppConfig> build() => ref.read(configStoreProvider).load();

  /// 只做连接测试，不落盘。供配置页「测试连接」按钮使用。
  Future<ConnectionTestResult> testConnection({
    required String baseUrl,
    required String password,
  }) async {
    ApiClient? client;
    try {
      client = ApiClient(
        baseUrl: baseUrl,
        password: password.trim().isEmpty ? null : password.trim(),
      );
      return await NoteRepository(client).testConnection();
    } on ApiException catch (e) {
      return ConnectionTestResult.failure(e.message);
    } catch (_) {
      return ConnectionTestResult.failure('连接失败，请检查后端地址与网络');
    } finally {
      client?.dispose();
    }
  }

  /// 校验并保存配置；地址非法时抛出 [ApiException] 供表单展示。
  Future<void> save({required String baseUrl, required String password}) async {
    final normalized = normalizeBaseUrl(baseUrl);
    final config = AppConfig(baseUrl: normalized, password: password.trim());
    await ref.read(configStoreProvider).save(config);
    state = AsyncData(config);
  }

  /// 退出配置（清除后端地址与密码）。
  Future<void> clear() async {
    await ref.read(configStoreProvider).clear();
    state = const AsyncData(AppConfig.empty);
  }
}

final appConfigProvider =
    AsyncNotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);

/// 主题模式（跟随系统 / 浅色 / 深色）。
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() => ref.read(configStoreProvider).loadThemeMode();

  Future<void> setMode(ThemeMode mode) async {
    await ref.read(configStoreProvider).saveThemeMode(mode);
    state = AsyncData(mode);
  }
}

final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// 当前配置对应的 API 客户端；未配置时为 null。
final apiClientProvider = Provider<ApiClient?>((ref) {
  final config = ref.watch(appConfigProvider).valueOrNull;
  if (config == null || !config.isConfigured) return null;
  final client = ApiClient(
    baseUrl: config.baseUrl,
    password: config.hasPassword ? config.password : null,
  );
  ref.onDispose(client.dispose);
  return client;
});

/// 业务仓库；未配置时为 null。
final repositoryProvider = Provider<NoteRepository?>((ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : NoteRepository(client);
});

NoteRepository _requireRepository(Ref ref) {
  final repository = ref.watch(repositoryProvider);
  if (repository == null) {
    throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
  }
  return repository;
}

/// 来源仓库；未配置时为 null。
final sourceRepositoryProvider = Provider<SourceRepository?>((ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : SourceRepository(client);
});

/// 对话仓库；未配置时为 null。
final chatRepositoryProvider = Provider<ChatRepository?>((ref) {
  final client = ref.watch(apiClientProvider);
  return client == null ? null : ChatRepository(client);
});

SourceRepository _requireSourceRepository(Ref ref) {
  final repository = ref.watch(sourceRepositoryProvider);
  if (repository == null) {
    throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
  }
  return repository;
}

ChatRepository _requireChatRepository(Ref ref) {
  final repository = ref.watch(chatRepositoryProvider);
  if (repository == null) {
    throw const ApiException('尚未配置后端地址', kind: ApiErrorKind.badRequest);
  }
  return repository;
}

/// 笔记本列表（默认按更新时间倒序）。
final notebooksProvider = FutureProvider.autoDispose<List<Notebook>>((ref) async {
  return _requireRepository(ref).fetchNotebooks();
});

/// 已归档笔记本。
final archivedNotebooksProvider = FutureProvider.autoDispose<List<Notebook>>((ref) async {
  return _requireRepository(ref).fetchNotebooks(archived: true);
});

/// 某个笔记本下的笔记列表；参数为 `null` 表示「全部笔记」。
final notesProvider =
    FutureProvider.autoDispose.family<List<Note>, String?>((ref, notebookId) async {
  return _requireRepository(ref).fetchNotes(notebookId: notebookId);
});

/// 单条笔记详情（编辑器首次加载用）。
final noteProvider =
    FutureProvider.autoDispose.family<Note, String>((ref, noteId) async {
  return _requireRepository(ref).fetchNote(noteId);
});

/// 搜索。
final searchProvider =
    FutureProvider.autoDispose.family<List<SearchHit>, SearchQuery>((ref, query) async {
  return _requireRepository(ref).search(
    query: query.query,
    type: query.type,
    limit: query.limit,
    notebookIds: query.notebookIds,
  );
});

/// 服务版本信息（设置页展示）。
final serverConfigProvider = FutureProvider.autoDispose<ServerConfig>((ref) async {
  final repository = _requireRepository(ref);
  return repository.client.fetchServerConfig();
});

/// 全部笔记（首页「全部笔记」入口用），与 [notesProvider] 共享缓存。
final allNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  return _requireRepository(ref).fetchNotes();
});

/// 某个笔记本下的来源列表；参数为 `null` 表示「全部来源」。
final sourcesProvider =
    FutureProvider.autoDispose.family<List<Source>, String?>((ref, notebookId) async {
  return _requireSourceRepository(ref).fetchSources(notebookId: notebookId);
});

/// 单个来源详情（含正文，用于详情弹窗与对话上下文预览）。
final sourceProvider =
    FutureProvider.autoDispose.family<Source, String>((ref, sourceId) async {
  return _requireSourceRepository(ref).fetchSource(sourceId);
});

/// 某个来源的洞见（transformation 生成的结构化摘要）。
final sourceInsightsProvider =
    FutureProvider.autoDispose.family<List<SourceInsight>, String>((ref, sourceId) async {
  return _requireSourceRepository(ref).fetchInsights(sourceId);
});

/// 某个笔记本的对话会话列表。
final chatSessionsProvider =
    FutureProvider.autoDispose.family<List<ChatSession>, String>((ref, notebookId) async {
  return _requireChatRepository(ref).fetchSessions(notebookId);
});

/// 对话会话详情（含消息列表）。
final chatSessionProvider = FutureProvider.autoDispose
    .family<({ChatSession session, List<ChatMessage> messages}), String>(
  (ref, sessionId) async {
    return _requireChatRepository(ref).fetchSession(sessionId);
  },
);

/// 可选的对话模型与服务端默认模型（对话页「模型」下拉用）。
final chatModelsProvider = FutureProvider.autoDispose<
    ({List<LanguageModel> models, String? defaultChatModel})>((ref) async {
  return _requireChatRepository(ref).fetchModels();
});

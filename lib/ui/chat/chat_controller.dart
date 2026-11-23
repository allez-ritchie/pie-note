import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/api_models.dart';
import '../../data/note_repository.dart';
import '../../state/providers.dart';
import '../common/strings.dart';
import 'chat_state.dart';
import 'chat_strings.dart';

export 'chat_state.dart';

/// 从首条用户消息推导默认会话标题（官方前端也是用首条消息做标题）。
///
/// 压平换行与多余空白后截断到 [maxLength]（含省略号），空消息回落到默认标题。
String summarizeChatTitle(String message, {int maxLength = 24}) {
  final plain = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (plain.isEmpty) return ChatStrings.title;
  if (plain.length <= maxLength) return plain;
  return '${plain.substring(0, maxLength)}…';
}

/// 按「官方前端」的默认策略推导上下文勾选状态：
///
/// - 来源：有洞见（`insights_count > 0`）→ [ContextMode.insights]，否则 [ContextMode.full]；
///   处理中 / 处理失败的来源没有可用正文，默认不进上下文；
/// - 笔记：默认全文。
ChatContextSelection defaultContextSelection({
  required Iterable<Source> sources,
  required Iterable<Note> notes,
}) {
  return ChatContextSelection(
    sources: <String, ContextMode>{
      for (final source in sources)
        if (!source.isProcessing && !source.hasFailed)
          source.id:
              source.insightsCount > 0 ? ContextMode.insights : ContextMode.full,
    },
    notes: <String, ContextMode>{
      for (final note in notes) note.id: ContextMode.full,
    },
  );
}



/// 一个笔记本的对话控制器（family 参数 = `notebookId`）。
///
/// 职责边界：会话与消息、上下文勾选、模型覆盖、发送中的状态与错误都放这里；
/// 面板开合、输入框文本等纯 UI 状态留在 [ChatScreen] 的 setState 里。
class ChatController extends AutoDisposeFamilyAsyncNotifier<ChatState, String> {
  ChatRepository get _repository {
    final repository = ref.read(chatRepositoryProvider);
    if (repository == null) {
      throw const ApiException(
        ChatStrings.notConfigured,
        kind: ApiErrorKind.badRequest,
      );
    }
    return repository;
  }

  /// family 参数：对话所属的笔记本 id。
  String get _notebookId => arg;

  @override
  Future<ChatState> build(String notebookId) => _load();

  /// 首次加载 / 手动刷新：默认上下文 + 会话列表 + 最近一个会话的消息。
  Future<ChatState> _load() async {
    final repository = _repository;
    final selection = await _defaultSelection();
    final sessions = _sortSessions(await repository.fetchSessions(_notebookId));
    final selected = sessions.isEmpty ? null : sessions.first;

    List<ChatMessage> messages = const <ChatMessage>[];
    String? messagesError;
    if (selected != null) {
      try {
        messages = (await repository.fetchSession(selected.id)).messages;
      } catch (error) {
        messagesError = _errorText(error);
      }
    }
    return ChatState(
      sessions: sessions,
      selectedSessionId: selected?.id,
      messages: messages,
      messagesError: messagesError,
      selection: selection,
    );
  }

  /// 默认上下文勾选（来源 / 笔记列表加载失败时降级为空上下文，不阻塞对话）。
  ///
  /// 这里直接走仓库而不是 `sourcesProvider` / `notesProvider`：本控制器在
  /// 保存为笔记后会 invalidate 那些 provider，如果在这里 watch / await 它们的
  /// `.future`，会导致控制器被重建、消息列表闪一下、用户勾选被重置。
  Future<ChatContextSelection> _defaultSelection() async {
    final sourceRepository = ref.read(sourceRepositoryProvider);
    final noteRepository = ref.read(repositoryProvider);
    var sources = const <Source>[];
    var notes = const <Note>[];
    if (sourceRepository != null) {
      try {
        sources = await sourceRepository.fetchSources(notebookId: _notebookId);
      } catch (_) {
        // 来源列表不可用时上下文留空，用户仍可对话。
      }
    }
    if (noteRepository != null) {
      try {
        notes = await noteRepository.fetchNotes(notebookId: _notebookId);
      } catch (_) {
        // 同上。
      }
    }
    return defaultContextSelection(sources: sources, notes: notes);
  }

  /// 重新拉取会话列表（发送成功后标题 / 消息数会变）。
  Future<void> _refreshSessions() async {
    try {
      final sessions = _sortSessions(await _repository.fetchSessions(_notebookId));
      _update((current) {
        final selected = current.selectedSessionId;
        final stillExists = sessions.any((session) => session.id == selected);
        return current.copyWith(
          sessions: sessions,
          selectedSessionId: !stillExists && sessions.isNotEmpty
              ? sessions.first.id
              : selected,
        );
      });
    } catch (_) {
      // 列表刷新失败不影响本轮对话结果。
    }
  }

  /// 刷新（下拉刷新 / 重试按钮）。
  Future<void> refresh() async {
    final current = state.valueOrNull;
    if (current != null && current.sending) return;
    state = const AsyncValue<ChatState>.loading();
    state = await AsyncValue.guard(_load);
  }

  // ---------------------------------------------------------------------------
  // 发送
  // ---------------------------------------------------------------------------

  /// 发送一条消息。
  ///
  /// 流程与官方前端一致：先 `POST /api/chat/context` 构建上下文，再
  /// `POST /api/chat/execute`；没有会话时先自动建一个（标题取首条消息摘要）。
  /// 返回 true 表示成功（调用方据此决定是否清空输入框）。
  Future<bool> send(String rawMessage) async {
    final message = rawMessage.trim();
    final current = state.valueOrNull;
    if (current == null || message.isEmpty || current.sending) return false;

    final pending = ChatMessage.pendingHuman(message);
    _update(
      (value) => value.copyWith(
        sending: true,
        errorText: null,
        failedMessage: null,
        messages: <ChatMessage>[...value.messages, pending],
      ),
    );

    try {
      final repository = _repository;

      // 没有会话时先自动建一个，标题用首条消息摘要。
      final activeSession = current.selectedSession ??
          await repository.createSession(
            notebookId: _notebookId,
            title: summarizeChatTitle(message),
            modelOverride: current.pendingModelId,
          );

      final built = await repository.buildContext(
        notebookId: _notebookId,
        selection: current.selection,
      );

      final answers = await repository.execute(
        sessionId: activeSession.id,
        message: message,
        context: built.context,
      );

      _update(
        (value) => value.copyWith(
          sessions: <ChatSession>[
            activeSession,
            ...value.sessions.where((item) => item.id != activeSession.id),
          ],
          selectedSessionId: activeSession.id,
          pendingModelId: null,
          messages: answers.isEmpty
              ? value.messages.where((item) => item.id != pending.id).toList()
              : answers,
          sending: false,
          errorText: null,
          failedMessage: null,
          lastContext: built,
        ),
      );
      await _refreshSessions();
      return true;
    } catch (error) {
      // 回滚乐观插入的消息，保留失败文本供内联「重试」。
      _update(
        (value) => value.copyWith(
          sending: false,
          messages:
              value.messages.where((item) => item.id != pending.id).toList(),
          errorText: _errorText(error),
          failedMessage: message,
        ),
      );
      return false;
    }
  }

  /// 重发上一次失败的消息。
  Future<bool> retryLastSend() async {
    final failed = state.valueOrNull?.failedMessage;
    if (failed == null || failed.isEmpty) return false;
    return send(failed);
  }

  /// 收起内联错误（不清除失败文本以外的任何状态）。
  void dismissError() {
    _update(
      (value) => value.copyWith(errorText: null, failedMessage: null),
    );
  }

  // ---------------------------------------------------------------------------
  // 会话
  // ---------------------------------------------------------------------------

  /// 新建会话并切换过去；[title] 为空时由后端生成 / 首条消息补上。
  Future<bool> createSession({String? title}) async {
    final current = state.valueOrNull;
    if (current == null || current.sending) return false;
    final trimmed = title?.trim() ?? '';
    try {
      final session = await _repository.createSession(
        notebookId: _notebookId,
        title: trimmed.isEmpty ? null : trimmed,
        modelOverride: current.pendingModelId,
      );
      _update(
        (value) => value.copyWith(
          sessions: <ChatSession>[
            session,
            ...value.sessions.where((item) => item.id != session.id),
          ],
          selectedSessionId: session.id,
          messages: const <ChatMessage>[],
          messagesLoading: false,
          messagesError: null,
          sending: false,
          errorText: null,
          failedMessage: null,
          pendingModelId: null,
          lastContext: null,
        ),
      );
      return true;
    } catch (error) {
      _update((value) => value.copyWith(errorText: _errorText(error)));
      return false;
    }
  }

  /// 切换到另一个会话并加载它的消息。
  Future<void> selectSession(String sessionId) async {
    final current = state.valueOrNull;
    if (current == null || current.selectedSessionId == sessionId) return;
    if (current.sending) return;
    _update(
      (value) => value.copyWith(
        selectedSessionId: sessionId,
        messages: const <ChatMessage>[],
        messagesLoading: true,
        messagesError: null,
        errorText: null,
        failedMessage: null,
      ),
    );
    await _loadMessages(sessionId);
  }

  Future<void> _loadMessages(String sessionId) async {
    try {
      final detail = await _repository.fetchSession(sessionId);
      _update((value) {
        // 加载期间又切走了就不覆盖当前会话。
        if (value.selectedSessionId != sessionId) return value;
        return value.copyWith(
          sessions: _replaceSession(value.sessions, detail.session),
          messages: detail.messages,
          messagesLoading: false,
          messagesError: null,
        );
      });
    } catch (error) {
      _update((value) {
        if (value.selectedSessionId != sessionId) return value;
        return value.copyWith(
          messagesLoading: false,
          messagesError: _errorText(error),
        );
      });
    }
  }

  /// 重新加载当前会话的消息（消息区错误的重试）。
  Future<void> reloadMessages() async {
    final sessionId = state.valueOrNull?.selectedSessionId;
    if (sessionId == null) return;
    _update(
      (value) => value.copyWith(messagesLoading: true, messagesError: null),
    );
    await _loadMessages(sessionId);
  }

  Future<bool> renameSession(String sessionId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    try {
      final updated = await _repository.renameSession(sessionId, trimmed);
      _update(
        (value) => value.copyWith(
          sessions: _replaceSession(value.sessions, updated),
        ),
      );
      return true;
    } catch (error) {
      _update((value) => value.copyWith(errorText: _errorText(error)));
      return false;
    }
  }

  /// 删除会话；删掉的是当前会话时自动切到剩下的第一个。
  Future<bool> deleteSession(String sessionId) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _repository.deleteSession(sessionId);
    } catch (error) {
      _update((value) => value.copyWith(errorText: _errorText(error)));
      return false;
    }
    final remaining = current.sessions
        .where((session) => session.id != sessionId)
        .toList(growable: false);
    final wasSelected = current.selectedSessionId == sessionId;
    _update(
      (value) => value.copyWith(
        sessions: remaining,
        selectedSessionId: wasSelected
            ? (remaining.isEmpty ? null : remaining.first.id)
            : value.selectedSessionId,
        messages: wasSelected ? const <ChatMessage>[] : value.messages,
        messagesError: null,
        errorText: null,
        failedMessage: null,
      ),
    );
    if (wasSelected && remaining.isNotEmpty) {
      await _loadMessages(remaining.first.id);
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // 模型
  // ---------------------------------------------------------------------------

  /// 切换模型：有会话时写回会话（`model_override`），没有会话时作为待定覆盖。
  Future<bool> setModel(String? modelId) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    final session = current.selectedSession;
    if (session == null) {
      _update((value) => value.copyWith(pendingModelId: modelId));
      return true;
    }
    try {
      final updated = await _repository.setSessionModel(session.id, modelId);
      _update(
        (value) => value.copyWith(
          sessions: _replaceSession(value.sessions, updated),
          pendingModelId: null,
        ),
      );
      return true;
    } catch (error) {
      _update((value) => value.copyWith(errorText: _errorText(error)));
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 上下文
  // ---------------------------------------------------------------------------

  /// 设置某个来源的上下文模式（[ContextMode.off] 表示移出上下文）。
  void setSourceMode(String sourceId, ContextMode mode) {
    _update((value) {
      final sources = Map<String, ContextMode>.from(value.selection.sources);
      if (mode == ContextMode.off) {
        sources.remove(sourceId);
      } else {
        sources[sourceId] = mode;
      }
      return value.copyWith(
        selection: value.selection.copyWith(sources: sources),
        // 勾选变了，之前算出的 token 数不再准确。
        lastContext: null,
      );
    });
  }

  /// 设置某条笔记是否放进上下文（笔记只有「不进 / 全文」两种）。
  void setNoteIncluded(String noteId, bool included) {
    _update((value) {
      final notes = Map<String, ContextMode>.from(value.selection.notes);
      if (included) {
        notes[noteId] = ContextMode.full;
      } else {
        notes.remove(noteId);
      }
      return value.copyWith(
        selection: value.selection.copyWith(notes: notes),
        lastContext: null,
      );
    });
  }

  /// 恢复默认勾选（测试与「重置」入口用）。
  Future<void> resetSelection() async {
    final selection = await _defaultSelection();
    _update((value) => value.copyWith(selection: selection, lastContext: null));
  }

  /// 「预览上下文」：只构建不发送，展示 token / 字符数。
  Future<BuiltChatContext?> previewContext() async {
    final current = state.valueOrNull;
    if (current == null || current.contextBuilding) return null;
    _update(
      (value) => value.copyWith(contextBuilding: true, contextError: null),
    );
    try {
      final built = await _repository.buildContext(
        notebookId: _notebookId,
        selection: current.selection,
      );
      _update(
        (value) => value.copyWith(
          contextBuilding: false,
          lastContext: built,
          contextError: null,
        ),
      );
      return built;
    } catch (error) {
      _update(
        (value) => value.copyWith(
          contextBuilding: false,
          contextError: _errorText(error),
        ),
      );
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // AI 消息动作
  // ---------------------------------------------------------------------------

  /// 把一条 AI 回答保存为当前笔记本下的 AI 笔记。
  Future<bool> saveMessageAsNote(ChatMessage message) async {
    if (message.content.trim().isEmpty) return false;
    final repository = ref.read(repositoryProvider);
    if (repository == null) {
      _update((value) => value.copyWith(errorText: ChatStrings.notConfigured));
      return false;
    }
    try {
      await repository.createNote(
        content: message.content,
        noteType: 'ai',
        notebookId: _notebookId,
      );
      ref.invalidate(notesProvider(_notebookId));
      ref.invalidate(allNotesProvider);
      ref.invalidate(notebooksProvider);
      return true;
    } catch (error) {
      _update((value) => value.copyWith(errorText: _errorText(error)));
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  ChatState? get _current => state.valueOrNull;

  void _update(ChatState Function(ChatState current) transform) {
    final current = _current;
    if (current == null) return;
    state = AsyncData(transform(current));
  }

  static String _errorText(Object error) {
    if (error is ApiException) return error.message;
    return S.unknownError;
  }

  /// 按更新时间倒序（后端已排序，这里只做兜底，保证「最近一个」稳定）。
  static List<ChatSession> _sortSessions(List<ChatSession> sessions) {
    final sorted = List<ChatSession>.of(sessions);
    sorted.sort((a, b) {
      final aTime = a.updated ?? a.created;
      final bTime = b.updated ?? b.created;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  static List<ChatSession> _replaceSession(
    List<ChatSession> sessions,
    ChatSession updated,
  ) {
    final index = sessions.indexWhere((session) => session.id == updated.id);
    if (index < 0) return <ChatSession>[updated, ...sessions];
    final copy = List<ChatSession>.of(sessions);
    copy[index] = updated;
    return copy;
  }
}

/// 对话控制器（按 `notebookId` 缓存）。
final chatControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatController, ChatState, String>(ChatController.new);

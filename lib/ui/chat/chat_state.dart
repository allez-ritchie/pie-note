import 'package:flutter/foundation.dart';

import '../../data/api_models.dart';
import 'chat_strings.dart';

/// 对话页的业务状态（会话 / 消息 / 上下文勾选 / 发送中 / 内联错误）。
///
/// 纯数据、不可变；所有变更由 [ChatController] 通过 [ChatState.copyWith] 产出。
@immutable
class ChatState {
  const ChatState({
    this.sessions = const <ChatSession>[],
    this.selectedSessionId,
    this.messages = const <ChatMessage>[],
    this.selection = const ChatContextSelection(),
    this.pendingModelId,
    this.messagesLoading = false,
    this.messagesError,
    this.sending = false,
    this.errorText,
    this.failedMessage,
    this.lastContext,
    this.contextBuilding = false,
    this.contextError,
  });

  /// 当前笔记本的会话列表（按更新时间倒序）。
  final List<ChatSession> sessions;

  final String? selectedSessionId;

  /// 当前会话的消息（后端返回的**完整历史**，不是增量）。
  final List<ChatMessage> messages;

  /// 上下文勾选：`source:<id>` / `note:<id>` → 模式。
  final ChatContextSelection selection;

  /// 还没有会话时选择的模型覆盖（`model:<id>`），新建会话时带上。
  final String? pendingModelId;

  final bool messagesLoading;

  /// 拉取会话消息失败的原因（消息区显示 + 重试）。
  final String? messagesError;

  /// 「AI 正在回答…」——生成中禁用发送与输入。
  final bool sending;

  /// 内联错误（发送失败 / 会话操作失败 / 保存为笔记失败）。
  final String? errorText;

  /// 发送失败时保留的用户输入，供内联「重试」按钮重新发送。
  final String? failedMessage;

  /// 最近一次成功构建的上下文（展示 token / 字符数）。
  final BuiltChatContext? lastContext;

  final bool contextBuilding;
  final String? contextError;

  ChatSession? get selectedSession {
    final id = selectedSessionId;
    if (id == null) return null;
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  /// 当前生效的模型覆盖：会话级覆盖优先，其次是没有会话时的待定覆盖。
  String? get modelOverride => selectedSession?.modelOverride ?? pendingModelId;

  bool get hasSession => selectedSessionId != null;

  bool get canSend => !sending;

  int get fullSourceCount =>
      selection.sources.values.where((mode) => mode == ContextMode.full).length;

  int get insightSourceCount => selection.sources.values
      .where((mode) => mode == ContextMode.insights)
      .length;

  int get selectedNoteCount =>
      selection.notes.values.where((mode) => mode != ContextMode.off).length;

  /// 已选统计文案（`2 个来源全文 / 1 个来源仅洞见 / 3 条笔记`）。
  String get contextSummary => ChatStrings.contextSummary(
        fullSourceCount,
        insightSourceCount,
        selectedNoteCount,
      );

  ChatState copyWith({
    List<ChatSession>? sessions,
    Object? selectedSessionId = _unset,
    List<ChatMessage>? messages,
    ChatContextSelection? selection,
    Object? pendingModelId = _unset,
    bool? messagesLoading,
    Object? messagesError = _unset,
    bool? sending,
    Object? errorText = _unset,
    Object? failedMessage = _unset,
    Object? lastContext = _unset,
    bool? contextBuilding,
    Object? contextError = _unset,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      selectedSessionId: identical(selectedSessionId, _unset)
          ? this.selectedSessionId
          : selectedSessionId as String?,
      messages: messages ?? this.messages,
      selection: selection ?? this.selection,
      pendingModelId: identical(pendingModelId, _unset)
          ? this.pendingModelId
          : pendingModelId as String?,
      messagesLoading: messagesLoading ?? this.messagesLoading,
      messagesError: identical(messagesError, _unset)
          ? this.messagesError
          : messagesError as String?,
      sending: sending ?? this.sending,
      errorText:
          identical(errorText, _unset) ? this.errorText : errorText as String?,
      failedMessage: identical(failedMessage, _unset)
          ? this.failedMessage
          : failedMessage as String?,
      lastContext: identical(lastContext, _unset)
          ? this.lastContext
          : lastContext as BuiltChatContext?,
      contextBuilding: contextBuilding ?? this.contextBuilding,
      contextError: identical(contextError, _unset)
          ? this.contextError
          : contextError as String?,
    );
  }
}

const Object _unset = Object();

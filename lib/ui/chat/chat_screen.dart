import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/layout.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'chat_composer.dart';
import 'chat_context_panel.dart';
import 'chat_controller.dart';
import 'chat_message_list.dart';
import 'chat_panels.dart';
import 'chat_session_panel.dart';
import 'chat_strings.dart';

/// 「与笔记本对话」页面。
///
/// - [notebookId]：对话所属笔记本（provider family 的 key）；
/// - [title]：AppBar 标题（工作区标签页标题由外壳传入，通常已带笔记本名）；
/// - [embedded]：作为工作区标签页嵌入时为 true，此时不自己 push 全屏页面，
///   侧栏改用 bottom sheet / 页面内布局，底部给悬浮胶囊留出空间。
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.notebookId,
    required this.title,
    this.embedded = true,
  });

  final String notebookId;
  final String title;
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  /// 宽屏左侧栏显示会话还是上下文；窄屏由 AppBar 动作打开 bottom sheet。
  ChatSidePanel _sidePanel = ChatSidePanel.sessions;

  /// 消息列表底部给工作区胶囊工具栏预留的滚动空间。
  ///
  /// 工作区外壳本身已经给内容加了 84 的底部 padding（胶囊高度），这里再补一点，
  /// 保证最后一条消息滚动到末尾时不被胶囊或输入区压住。
  static const double _messageListInset = 120;

  /// 是否左右分栏：与仓库的编辑器分栏断点保持一致（>=900 且够高）。
  bool get _useSplit => Responsive.useEditorSplit(context);

  /// 是否处于「带底部悬浮胶囊工具栏」的窄屏外壳中。
  bool get _hasFloatingBar =>
      widget.embedded && !Responsive.useSideNavigation(context);

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  ChatController get _controller =>
      ref.read(chatControllerProvider(widget.notebookId).notifier);

  // ---------------------------------------------------------------------------
  // 动作
  // ---------------------------------------------------------------------------

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 发送：成功后清空输入框，失败时输入框与内联错误都保留。
  Future<void> _send([String? overrideText]) async {
    final text = (overrideText ?? _input.text).trim();
    if (text.isEmpty) return;
    final ok = await _controller.send(text);
    if (!mounted) return;
    if (ok) {
      _input.clear();
      _inputFocus.requestFocus();
      _scrollToBottom();
    }
  }

  Future<void> _retrySend() async {
    final ok = await _controller.retryLastSend();
    if (!mounted) return;
    if (ok) {
      _input.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    // 等列表完成一帧布局后再滚到底部，避免拿到旧的 maxScrollExtent。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copyMessage(ChatMessage message) async {
    final ok = await copyChatMessage(message);
    _snack(ok ? ChatStrings.copied : ChatStrings.copyFailed);
  }

  Future<void> _saveAsNote(ChatMessage message) async {
    final ok = await _controller.saveMessageAsNote(message);
    _snack(ok ? ChatStrings.savedAsNote : ChatStrings.saveAsNoteFailed);
  }

  Future<void> _createSession() async {
    final title = await showTextInputDialog(
      context,
      title: ChatStrings.newSessionTitle,
      hintText: ChatStrings.newSessionHint,
      confirmLabel: S.create,
      allowEmpty: true,
    );
    if (title == null || !mounted) return;
    final ok = await _controller.createSession(title: title);
    if (!mounted) return;
    if (ok) _snack(ChatStrings.sessionCreated);
  }

  Future<void> _renameSession(ChatSession session) async {
    final title = await showTextInputDialog(
      context,
      title: ChatStrings.renameSession,
      initialValue: session.displayTitle,
      confirmLabel: S.save,
    );
    if (title == null || !mounted) return;
    await _controller.renameSession(session.id, title);
  }

  Future<void> _deleteSession(ChatSession session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: ChatStrings.deleteSessionTitle,
      message: ChatStrings.deleteSessionMessage,
      confirmLabel: S.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await _controller.deleteSession(session.id);
    if (!mounted) return;
    if (ok) _snack(ChatStrings.sessionDeleted);
  }

  Future<void> _previewContext() async {
    final built = await _controller.previewContext();
    if (!mounted || built == null) return;
    _snack(ChatStrings.contextAmount(built.tokenCount, built.charCount));
  }

  Future<void> _selectModel(String? modelId) async {
    final ok = await _controller.setModel(modelId);
    if (!mounted) return;
    _snack(ok ? ChatStrings.modelChanged : ChatStrings.modelChangeFailed);
  }

  void _showPanel(ChatSidePanel panel) {
    if (_useSplit) {
      setState(() => _sidePanel = panel);
      return;
    }
    final state = ref.read(chatControllerProvider(widget.notebookId)).valueOrNull;
    if (state == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ChatMobileSheet(
          title: panel == ChatSidePanel.sessions
              ? ChatStrings.sessionPanelTitle
              : ChatStrings.contextPanelTitle,
          child: panel == ChatSidePanel.sessions
              ? ChatSessionPanel(
                  sessions: state.sessions,
                  selectedSessionId: state.selectedSessionId,
                  sending: state.sending,
                  compact: true,
                  onSelect: (id) {
                    Navigator.of(sheetContext).pop();
                    _controller.selectSession(id);
                  },
                  onCreate: () {
                    Navigator.of(sheetContext).pop();
                    _createSession();
                  },
                  onRename: (session) {
                    Navigator.of(sheetContext).pop();
                    _renameSession(session);
                  },
                  onDelete: (session) {
                    Navigator.of(sheetContext).pop();
                    _deleteSession(session);
                  },
                )
              : ChatContextPanel(
                  notebookId: widget.notebookId,
                  selection: state.selection,
                  lastContext: state.lastContext,
                  contextBuilding: state.contextBuilding,
                  contextError: state.contextError,
                  compact: true,
                  onSourceModeChanged: _controller.setSourceMode,
                  onNoteIncludedChanged: _controller.setNoteIncluded,
                  onPreview: _previewContext,
                ),
        ),
      ),
    );
  }

  /// 窄屏的模型选择面板（宽屏常驻在左侧栏底部）。
  void _showModelSheet(List<LanguageModel> models, String? defaultModel) {
    final state = ref.read(chatControllerProvider(widget.notebookId)).valueOrNull;
    if (state == null) return;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => ChatMobileSheet(
        title: ChatStrings.modelPanelTitle,
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  state.modelOverride == null
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                ),
                title: Text(_defaultModelLabel(models, defaultModel)),
                subtitle: const Text(ChatStrings.defaultModelHint),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _selectModel(null);
                },
              ),
              if (models.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    ChatStrings.noModels,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              for (final model in models)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  key: ValueKey<String>('chat-model-${model.id}'),
                  leading: Icon(
                    state.modelOverride == model.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                  ),
                  title: Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(model.provider),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _selectModel(model.id);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「后端默认（模型名）」文案，与下拉第一项保持一致。
  String _defaultModelLabel(List<LanguageModel> models, String? defaultModel) {
    for (final model in models) {
      if (model.id == defaultModel) {
        return '${ChatStrings.defaultModel}（${model.name}）';
      }
    }
    return ChatStrings.defaultModel;
  }

  // ---------------------------------------------------------------------------
  // 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // 新消息（含生成中占位）出现后自动滚到底部。
    ref.listen<AsyncValue<ChatState>>(
      chatControllerProvider(widget.notebookId),
      (previous, next) {
        final before = previous?.valueOrNull;
        final after = next.valueOrNull;
        if (after == null) return;
        final grew = after.messages.length >
            (before?.messages.length ?? 0);
        if (grew || (after.sending && before?.sending != true)) {
          _scrollToBottom();
        }
      },
    );
    final async = ref.watch(chatControllerProvider(widget.notebookId));
    final modelsAsync = ref.watch(chatModelsProvider);
    final models = modelsAsync.valueOrNull?.models ?? const <LanguageModel>[];
    final defaultModel = modelsAsync.valueOrNull?.defaultChatModel;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (async.valueOrNull != null)
              Text(
                async.valueOrNull!.contextSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: ChatStrings.openSessions,
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => _showPanel(ChatSidePanel.sessions),
          ),
          IconButton(
            tooltip: ChatStrings.openContext,
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showPanel(ChatSidePanel.context),
          ),
          if (!_useSplit)
            IconButton(
              tooltip: ChatStrings.openModel,
              icon: const Icon(Icons.memory_rounded),
              onPressed: () => _showModelSheet(models, defaultModel),
            ),
          IconButton(
            tooltip: ChatStrings.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controller.refresh(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => const AppLoadingView(message: ChatStrings.sessionLoading),
          error: (error, _) => AppErrorView(
            title: ChatStrings.loadFailed,
            message: describeError(error),
            onRetry: () => _controller.refresh(),
          ),
          data: (state) => _buildBody(
            state,
            models: models,
            defaultModel: defaultModel,
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ChatState state, {
    required List<LanguageModel> models,
    required String? defaultModel,
  }) {
    final wide = _useSplit;
    final composer = ChatComposer(
      controller: _input,
      focusNode: _inputFocus,
      sending: state.sending,
      // 生成中禁用输入，避免用户以为新内容会被这一轮带走。
      enabled: !state.sending,
      onSend: _send,
    );

    final messagesArea = Column(
      children: [
        if (state.errorText != null)
          ChatInlineError(
            message: state.errorText!,
            onRetry: state.failedMessage == null ? null : _retrySend,
            onDismiss: _controller.dismissError,
          ),
        Expanded(child: _buildMessages(state)),
        composer,
      ],
    );

    if (!wide) return messagesArea;

    // 宽屏：左侧栏（会话 / 上下文切换）+ 右侧消息区。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: ChatSidePanelContainer(
            panel: _sidePanel,
            onPanelChanged: (panel) => setState(() => _sidePanel = panel),
            sessionPanel: ChatSessionPanel(
              sessions: state.sessions,
              selectedSessionId: state.selectedSessionId,
              sending: state.sending,
              onSelect: _controller.selectSession,
              onCreate: _createSession,
              onRename: _renameSession,
              onDelete: _deleteSession,
            ),
            contextPanel: ChatContextPanel(
              notebookId: widget.notebookId,
              selection: state.selection,
              lastContext: state.lastContext,
              contextBuilding: state.contextBuilding,
              contextError: state.contextError,
              onSourceModeChanged: _controller.setSourceMode,
              onNoteIncludedChanged: _controller.setNoteIncluded,
              onPreview: _previewContext,
            ),
            modelBar: ChatModelBar(
              models: models,
              defaultChatModel: defaultModel,
              selectedModelId: state.modelOverride,
              sending: state.sending,
              onChanged: _selectModel,
              compact: true,
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: messagesArea),
      ],
    );
  }

  Widget _buildMessages(ChatState state) {
    if (state.messagesLoading && state.messages.isEmpty) {
      return const AppLoadingView(message: ChatStrings.sessionLoading);
    }
    if (state.messagesError != null && state.messages.isEmpty) {
      return ChatMessagesError(
        message: state.messagesError!,
        onRetry: _controller.reloadMessages,
      );
    }
    if (state.messages.isEmpty && !state.sending) {
      return ChatEmptyState(onStart: _createSession);
    }
    return ChatMessageList(
      controller: _scroll,
      messages: state.messages,
      sending: state.sending,
      onCopy: _copyMessage,
      onSaveAsNote: _saveAsNote,
      bottomInset: _hasFloatingBar ? _messageListInset : 0,
    );
  }
}

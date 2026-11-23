import 'package:flutter/material.dart';

import '../../data/api_models.dart';
import 'chat_session_panel.dart';
import 'chat_strings.dart';

/// 对话页的布局组件（从 `chat_screen.dart` 拆出来控制单文件长度）。
///
/// 只在 `lib/ui/chat/` 内部使用，不对外暴露 API。

/// 侧栏展示哪种面板（宽屏左栏 / 窄屏 bottom sheet 共用）。
enum ChatSidePanel { sessions, context }

/// 宽屏左侧栏：会话 / 上下文两个页签 + 模型选择。
class ChatSidePanelContainer extends StatelessWidget {
  const ChatSidePanelContainer({
    super.key,
    required this.panel,
    required this.onPanelChanged,
    required this.sessionPanel,
    required this.contextPanel,
    required this.modelBar,
  });

  final ChatSidePanel panel;
  final ValueChanged<ChatSidePanel> onPanelChanged;
  final Widget sessionPanel;
  final Widget contextPanel;
  final Widget modelBar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SegmentedButton<ChatSidePanel>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const <ButtonSegment<ChatSidePanel>>[
              ButtonSegment<ChatSidePanel>(
                value: ChatSidePanel.sessions,
                label: Text(ChatStrings.sessions),
                icon: Icon(Icons.forum_outlined, size: 16),
              ),
              ButtonSegment<ChatSidePanel>(
                value: ChatSidePanel.context,
                label: Text(ChatStrings.context),
                icon: Icon(Icons.tune_rounded, size: 16),
              ),
            ],
            selected: <ChatSidePanel>{panel},
            onSelectionChanged: (values) => onPanelChanged(values.first),
          ),
        ),
        Expanded(
          child: panel == ChatSidePanel.sessions ? sessionPanel : contextPanel,
        ),
        const Divider(height: 1),
        modelBar,
      ],
    );
  }
}

/// 模型选择条：第一项「后端默认」，其余是后端注册的对话模型。
class ChatModelBar extends StatelessWidget {
  const ChatModelBar({
    super.key,
    required this.models,
    required this.defaultChatModel,
    required this.selectedModelId,
    required this.sending,
    required this.onChanged,
    this.compact = false,
  });

  final List<LanguageModel> models;
  final String? defaultChatModel;
  final String? selectedModelId;
  final bool sending;
  final ValueChanged<String?> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 6, 12, compact ? 10 : 4),
      decoration: compact
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
      child: Row(
        children: [
          Icon(
            Icons.memory_rounded,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ChatModelSelector(
              models: models,
              defaultChatModel: defaultChatModel,
              selectedModelId: selectedModelId,
              enabled: !sending,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 窄屏面板容器（bottom sheet 内容）。
class ChatMobileSheet extends StatelessWidget {
  const ChatMobileSheet({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                tooltip: ChatStrings.closePanel,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api_models.dart';
import '../common/formatters.dart';
import '../common/strings.dart';
import '../notes/markdown_view.dart';
import 'chat_strings.dart';

/// 消息区：人类消息右对齐气泡、AI 消息左对齐并渲染 Markdown。
///
/// 只在列表末尾追加「AI 正在回答…」占位，不替换已有消息，避免生成过程中
/// 内容闪烁；发送失败由页面顶部的内联错误条承担（消息已回滚）。
class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.sending,
    required this.onCopy,
    required this.onSaveAsNote,
    this.controller,
    this.bottomInset = 0,
  });

  final List<ChatMessage> messages;

  /// 是否正在等待模型回答。
  final bool sending;

  final ValueChanged<ChatMessage> onCopy;
  final ValueChanged<ChatMessage> onSaveAsNote;

  /// 消息列表滚动控制器（发送后自动滚动到底部）。
  final ScrollController? controller;

  /// 底部额外留白（工作区胶囊工具栏）。
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !sending) {
      return const SizedBox.shrink();
    }
    final itemCount = messages.length + (sending ? 1 : 0);
    return ListView.builder(
      key: const PageStorageKey<String>('chat-messages'),
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return const ChatGeneratingIndicator(
            key: ValueKey<String>('chat-generating'),
          );
        }
        final message = messages[index];
        return Padding(
          key: ValueKey<String>('chat-message-${message.id}'),
          padding: const EdgeInsets.only(bottom: 14),
          child: message.role == ChatRole.human
              ? _HumanBubble(message: message)
              : _AiBubble(
                  message: message,
                  onCopy: () => onCopy(message),
                  onSaveAsNote: () => onSaveAsNote(message),
                ),
        );
      },
    );
  }
}

/// 人类消息：右对齐浅色气泡。
class _HumanBubble extends StatelessWidget {
  const _HumanBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message.pending
                    ? ChatStrings.sending
                    : Formatters.relativeTime(message.timestamp),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI 消息：左对齐卡片，正文走 [MarkdownView]（支持复制选中、任务框、双链）。
class _AiBubble extends StatelessWidget {
  const _AiBubble({
    required this.message,
    required this.onCopy,
    required this.onSaveAsNote,
  });

  final ChatMessage message;
  final VoidCallback onCopy;
  final VoidCallback onSaveAsNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  ChatStrings.roleAi,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message.timestamp != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    Formatters.relativeTime(message.timestamp),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (message.content.trim().isEmpty)
              Text(
                ChatStrings.emptyAnswer,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              MarkdownView(content: message.content, selectable: true),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AiAction(
                  icon: Icons.copy_all_rounded,
                  tooltip: ChatStrings.copy,
                  onPressed: onCopy,
                ),
                _AiAction(
                  icon: Icons.note_add_outlined,
                  tooltip: ChatStrings.saveAsNote,
                  onPressed: onSaveAsNote,
                ),
              ],
            ),
            const Divider(height: 18),
          ],
        ),
      ),
    );
  }
}

/// AI 消息下方的图标动作（复制 / 保存为笔记）。
class _AiAction extends StatelessWidget {
  const _AiAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

/// 「AI 正在回答…」占位（生成中插到消息列表末尾）。
class ChatGeneratingIndicator extends StatelessWidget {
  const ChatGeneratingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ChatStrings.generating,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ChatStrings.generatingHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 发送失败的内联错误条：可重试、可关闭，消息与输入都保留。
class ChatInlineError extends StatelessWidget {
  const ChatInlineError({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ChatStrings.sendFailedTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text(ChatStrings.sendFailedRetry),
            ),
          IconButton(
            tooltip: ChatStrings.dismissError,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// 把消息正文写进系统剪贴板（复制按钮的实现，测试可直接调用）。
Future<bool> copyChatMessage(ChatMessage message) async {
  final text = message.content.trim();
  if (text.isEmpty) return false;
  try {
    await Clipboard.setData(ClipboardData(text: message.content));
    return true;
  } catch (_) {
    return false;
  }
}

/// 空对话占位（没有会话也没有消息时）。
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, this.onStart});

  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              ChatStrings.noSessionTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              ChatStrings.noSessionMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (onStart != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text(ChatStrings.startChat),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 消息区错误占位（历史消息加载失败）。
class ChatMessagesError extends StatelessWidget {
  const ChatMessagesError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 36, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(S.retry),
            ),
          ],
        ),
      ),
    );
  }
}

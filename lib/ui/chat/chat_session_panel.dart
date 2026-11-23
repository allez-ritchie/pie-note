import 'package:flutter/material.dart';

import '../../data/api_models.dart';
import '../common/formatters.dart';
import '../common/strings.dart';
import 'chat_strings.dart';

/// 会话列表（宽屏左侧栏 / 窄屏 bottom sheet 共用）。
///
/// 只负责展示与回调，状态来自 [ChatController]；标题、消息数、模型覆盖都由
/// 后端返回的 [ChatSession] 驱动。
class ChatSessionPanel extends StatelessWidget {
  const ChatSessionPanel({
    super.key,
    required this.sessions,
    required this.selectedSessionId,
    required this.onSelect,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    this.sending = false,
    this.compact = false,
  });

  final List<ChatSession> sessions;
  final String? selectedSessionId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<ChatSession> onRename;
  final ValueChanged<ChatSession> onDelete;

  /// 生成中：切换 / 新建 / 删除会话会打断上下文，直接禁用。
  final bool sending;

  /// 紧凑模式（bottom sheet 内）不显示标题头。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = <Widget>[];
    if (!compact) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Row(
            children: [
              Text(
                ChatStrings.sessions,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: ChatStrings.newSession,
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                visualDensity: VisualDensity.compact,
                onPressed: sending ? null : onCreate,
              ),
            ],
          ),
        ),
      );
    }
    if (sessions.isEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
          child: Text(
            ChatStrings.noSessionsInPanel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      for (final session in sessions) {
        items.add(
          _SessionTile(
            key: ValueKey<String>('chat-session-${session.id}'),
            session: session,
            selected: session.id == selectedSessionId,
            enabled: !sending,
            onTap: () => onSelect(session.id),
            onRename: () => onRename(session),
            onDelete: () => onDelete(session),
          ),
        );
      }
    }
    return ListView(
      shrinkWrap: compact,
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 12),
      children: [
        if (compact)
          Row(
            children: [
              Text(
                ChatStrings.sessionPanelTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: sending ? null : onCreate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(ChatStrings.newSession),
              ),
            ],
          ),
        ...items,
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    super.key,
    required this.session,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSession session;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = session.messageCount ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 17,
                  color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count > 0
                            ? ChatStrings.messageCount(count)
                            : Formatters.relativeTime(
                                session.updated ?? session.created,
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: ChatStrings.selectSession,
                  enabled: enabled,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'rename',
                      child: Text(ChatStrings.renameSession),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(ChatStrings.deleteSession),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'rename') {
                      onRename();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 模型下拉：第一项是「后端默认」（显示服务端默认模型名）。
class ChatModelSelector extends StatelessWidget {
  const ChatModelSelector({
    super.key,
    required this.models,
    required this.defaultChatModel,
    required this.selectedModelId,
    required this.onChanged,
    this.enabled = true,
    this.loading = false,
    this.dense = true,
  });

  final List<LanguageModel> models;

  /// 服务端默认对话模型（`model:<id>`），可能为 null。
  final String? defaultChatModel;

  /// 当前覆盖模型 id（`model:<id>`），null 表示跟随默认。
  final String? selectedModelId;

  final ValueChanged<String?> onChanged;
  final bool enabled;
  final bool loading;
  final bool dense;

  /// 「后端默认」项的展示文案：带上默认模型名，让用户知道实际用哪个模型。
  String get defaultLabel {
    final name = _nameOf(defaultChatModel);
    return name == null
        ? ChatStrings.defaultModel
        : '${ChatStrings.defaultModel}（$name）';
  }

  String? _nameOf(String? modelId) {
    if (modelId == null) return null;
    for (final model in models) {
      if (model.id == modelId) return model.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (loading) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            S.loading,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    // 当前选中的模型不在列表里（例如后端删掉了）时仍然显示它，避免下拉报错。
    final known = models.any((model) => model.id == selectedModelId);
    final value = known && selectedModelId != null ? selectedModelId : null;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: value,
        isDense: dense,
        borderRadius: BorderRadius.circular(14),
        isExpanded: true,
        hint: Text(defaultLabel, overflow: TextOverflow.ellipsis),
        onChanged: enabled
            ? (modelId) => onChanged(modelId)
            : null,
        items: <DropdownMenuItem<String?>>[
          DropdownMenuItem<String?>(
            value: null,
            child: Text(defaultLabel, overflow: TextOverflow.ellipsis),
          ),
          for (final model in models)
            DropdownMenuItem<String?>(
              value: model.id,
              child: Text(
                '${model.name} · ${model.provider}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (selectedModelId != null && !known)
            DropdownMenuItem<String?>(
              value: selectedModelId,
              child: Text(selectedModelId!, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

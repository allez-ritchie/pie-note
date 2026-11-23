import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import 'chat_strings.dart';

/// 对话上下文面板：列出当前笔记本的来源与笔记，逐项选择是否放进上下文。
///
/// - 来源三态：[ContextMode.off] / [ContextMode.insights] / [ContextMode.full]；
///   没有洞见的来源禁用「仅洞见」（后端只会返回空数组，没有意义）；
/// - 笔记二态：不进 / 全文（后端不支持笔记的「仅洞见」）；
/// - 顶部显示已选统计，底部显示最近一次构建的 token / 字符数。
class ChatContextPanel extends ConsumerWidget {
  const ChatContextPanel({
    super.key,
    required this.notebookId,
    required this.selection,
    required this.onSourceModeChanged,
    required this.onNoteIncludedChanged,
    required this.onPreview,
    this.lastContext,
    this.contextBuilding = false,
    this.contextError,
    this.compact = false,
  });

  final String notebookId;

  final ChatContextSelection selection;
  final void Function(String sourceId, ContextMode mode) onSourceModeChanged;
  final void Function(String noteId, bool included) onNoteIncludedChanged;
  final VoidCallback onPreview;

  /// 最近一次 `buildContext` 的结果（token / 字符数）。
  final BuiltChatContext? lastContext;

  final bool contextBuilding;
  final String? contextError;

  /// 紧凑模式（bottom sheet 内）：不显示标题头、列表不强制撑满。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sourcesAsync = ref.watch(sourcesProvider(notebookId));
    final notesAsync = ref.watch(notesProvider(notebookId));
    final sources = sourcesAsync.valueOrNull ?? const <Source>[];
    final notes = notesAsync.valueOrNull ?? const <Note>[];

    return ListView(
      shrinkWrap: compact,
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 12, 12, 16),
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ChatStrings.contextPanelTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        _SummaryCard(
          selection: selection,
          lastContext: lastContext,
          contextBuilding: contextBuilding,
          contextError: contextError,
          onPreview: onPreview,
        ),
        const SizedBox(height: 14),
        _SectionHeader(title: ChatStrings.sourcesSection),
        if (sourcesAsync.isLoading && !sourcesAsync.hasValue)
          const _SmallSpinner()
        else if (sources.isEmpty)
          _EmptyHint(text: ChatStrings.noSources)
        else
          for (final source in sources)
            _SourceRow(
              key: ValueKey<String>('chat-context-source-${source.id}'),
              source: source,
              mode: selection.sources[source.id] ?? ContextMode.off,
              onChanged: (mode) => onSourceModeChanged(source.id, mode),
            ),
        if (sourcesAsync.hasError)
          _EmptyHint(text: '${ChatStrings.loadFailed}：${sourcesAsync.error}'),
        const SizedBox(height: 14),
        _SectionHeader(title: ChatStrings.notesSection),
        if (notesAsync.isLoading && !notesAsync.hasValue)
          const _SmallSpinner()
        else if (notes.isEmpty)
          _EmptyHint(text: ChatStrings.noNotes)
        else
          for (final note in notes)
            _NoteRow(
              key: ValueKey<String>('chat-context-note-${note.id}'),
              note: note,
              included: selection.notes[note.id] != null,
              onChanged: (included) => onNoteIncludedChanged(note.id, included),
            ),
        const SizedBox(height: 4),
        Text(
          ChatStrings.contextHelp,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 顶部统计 + 「预览上下文」。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.selection,
    required this.lastContext,
    required this.contextBuilding,
    required this.contextError,
    required this.onPreview,
  });

  final ChatContextSelection selection;
  final BuiltChatContext? lastContext;
  final bool contextBuilding;
  final String? contextError;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final built = lastContext;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChatStrings.contextSummary(
              selection.sources.values
                  .where((mode) => mode == ContextMode.full)
                  .length,
              selection.sources.values
                  .where((mode) => mode == ContextMode.insights)
                  .length,
              selection.notes.values
                  .where((mode) => mode != ContextMode.off)
                  .length,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (built != null) ...[
            const SizedBox(height: 4),
            Text(
              ChatStrings.contextAmount(built.tokenCount, built.charCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (contextError != null) ...[
            const SizedBox(height: 4),
            Text(
              '${ChatStrings.contextFailed}：$contextError',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.error),
            ),
          ],
          Row(
            children: [
              TextButton.icon(
                onPressed: contextBuilding ? null : onPreview,
                icon: contextBuilding
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_outlined, size: 18),
                label: Text(
                  contextBuilding
                      ? ChatStrings.previewingContext
                      : ChatStrings.previewContext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 来源一行：标题 / 元信息 + 三态模式按钮。
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.mode,
    required this.onChanged,
  });

  final Source source;
  final ContextMode mode;
  final ValueChanged<ContextMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasInsights = source.insightsCount > 0;
    final unavailable = source.isProcessing || source.hasFailed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: unavailable
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
              ),
              if (hasInsights)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    ChatStrings.insightsBadge(source.insightsCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<ContextMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: <ButtonSegment<ContextMode>>[
              const ButtonSegment<ContextMode>(
                value: ContextMode.off,
                label: Text(ChatStrings.modeOff),
                tooltip: ChatStrings.modeOffTooltip,
              ),
              ButtonSegment<ContextMode>(
                value: ContextMode.insights,
                label: const Text(ChatStrings.modeInsights),
                tooltip: ChatStrings.modeInsightsTooltip,
                enabled: hasInsights,
              ),
              const ButtonSegment<ContextMode>(
                value: ContextMode.full,
                label: Text(ChatStrings.modeFull),
                tooltip: ChatStrings.modeFullTooltip,
              ),
            ],
            selected: <ContextMode>{mode},
            onSelectionChanged: unavailable
                ? null
                : (values) => onChanged(values.first),
          ),
          if (unavailable)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                ChatStrings.sourceUnavailable,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 笔记一行：复选框决定是否放进上下文（笔记只有全文模式）。
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.included,
    required this.onChanged,
  });

  final Note note;
  final bool included;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CheckboxListTile(
      value: included,
      onChanged: (value) => onChanged(value ?? false),
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        note.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

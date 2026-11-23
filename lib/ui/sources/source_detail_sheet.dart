import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'source_meta.dart';
import 'sources_strings.dart';

/// 来源详情弹窗：正文 + 洞见 + 元信息。
///
/// 列表接口不返回正文，所以这里按需加载 [sourceProvider] / [sourceInsightsProvider]；
/// 宽度随窗口自适应（窄屏近似全屏 bottom sheet，宽屏居中对话框）。
Future<void> showSourceDetailSheet(
  BuildContext context, {
  required Source source,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _SourceDetailSheet(source: source),
    ),
  );
}

class _SourceDetailSheet extends ConsumerWidget {
  const _SourceDetailSheet({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = ref.watch(sourceProvider(source.id));
    final insights = ref.watch(sourceInsightsProvider(source.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Icon(
                sourceKindIcon(source.kind),
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sourceKindLabel(source.kind)} · '
                      '${SourceMeta.statusLabel(source)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: S.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (source.status == SourceStatus.failed)
                _FailedBanner(source: source),
              if (source.isProcessing)
                _ProcessingBanner(message: SourcesStrings.processingHint),
              _MetaCard(source: source),
              const SizedBox(height: 18),
              _SectionTitle(title: SourcesStrings.detailInsights),
              const SizedBox(height: 8),
              insights.when(
                loading: () => const _InlineLoading(),
                error: (error, _) => _InlineError(
                  message: describeError(error),
                  onRetry: () =>
                      ref.invalidate(sourceInsightsProvider(source.id)),
                ),
                data: (items) => items.isEmpty
                    ? _Hint(text: SourcesStrings.detailNoInsights)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final insight in items)
                            _InsightCard(
                              key: ValueKey('insight-${insight.id}'),
                              insight: insight,
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _SectionTitle(title: SourcesStrings.detailContent),
                  ),
                  if (source.url != null)
                    TextButton.icon(
                      onPressed: () => _openLink(context, source.url!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text(SourcesStrings.detailOpenLink),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              detail.when(
                loading: () => const _InlineLoading(),
                error: (error, _) => _InlineError(
                  message: describeError(error),
                  onRetry: () => ref.invalidate(sourceProvider(source.id)),
                ),
                data: (loaded) {
                  final text = loaded.fullText?.trim() ?? '';
                  if (text.isEmpty) {
                    return const _Hint(text: SourcesStrings.detailNoContent);
                  }
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(SourcesStrings.detailOpenFailed)),
      );
    }
  }
}

/// 详情里的元信息卡片。
class _MetaCard extends StatelessWidget {
  const _MetaCard({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <(String, String)>[
      (SourcesStrings.detailKind, sourceKindLabel(source.kind)),
      (SourcesStrings.detailCreated, Formatters.dateTime(source.created)),
      (SourcesStrings.updatedAt, Formatters.dateTime(source.updated)),
      (
        SourcesStrings.detailChunks,
        '${source.embeddedChunks} · '
            '${source.embedded ? SourcesStrings.embedded : SourcesStrings.notEmbedded}',
      ),
      if (source.notebookIds.isNotEmpty)
        (SourcesStrings.detailNotebooks, source.notebookIds.join('\n')),
      if (source.url != null) (SourcesStrings.addUrlLabel, source.url!),
      if (source.filePath != null)
        (SourcesStrings.detailFilePath, source.filePath!),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({super.key, required this.insight});

  final SourceInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 16,
                  color: scheme.tertiary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    insight.insightType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.tertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              insight.content,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedBanner extends StatelessWidget {
  const _FailedBanner({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              source.processingError == null
                  ? SourcesStrings.statusFailed
                  : SourcesStrings.processingFailed(source.processingError!),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingBanner extends StatelessWidget {
  const _ProcessingBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.error,
            ),
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text(S.retry)),
      ],
    );
  }
}

/// 来源类型对应的图标。
IconData sourceKindIcon(SourceKind kind) {
  return switch (kind) {
    SourceKind.link => Icons.link_rounded,
    SourceKind.upload => Icons.upload_file_rounded,
    SourceKind.text => Icons.subject_rounded,
  };
}

/// 来源类型的展示名。
String sourceKindLabel(SourceKind kind) {
  return switch (kind) {
    SourceKind.link => SourcesStrings.typeLinkIcon,
    SourceKind.upload => SourcesStrings.typeUpload,
    SourceKind.text => SourcesStrings.typeText,
  };
}

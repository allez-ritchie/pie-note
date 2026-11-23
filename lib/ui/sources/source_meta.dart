import 'package:flutter/material.dart';

import '../../data/api_models.dart';
import 'sources_strings.dart';

/// 来源状态 / 元信息的展示辅助（列表与详情共用）。
class SourceMeta {
  const SourceMeta._();

  /// 状态文案。
  static String statusLabel(Source source) {
    return switch (source.status) {
      SourceStatus.newSource || SourceStatus.queued => SourcesStrings.statusQueued,
      SourceStatus.running => SourcesStrings.statusProcessing,
      SourceStatus.completed => SourcesStrings.statusCompleted,
      SourceStatus.failed => SourcesStrings.statusFailed,
      SourceStatus.unknown => SourcesStrings.statusUnknown,
    };
  }

  /// 状态图标；处理中返回 null（改用进度圈）。
  static IconData? statusIcon(SourceStatus status) {
    return switch (status) {
      SourceStatus.newSource || SourceStatus.queued => Icons.schedule_rounded,
      SourceStatus.running => null,
      SourceStatus.completed => Icons.check_circle_outline_rounded,
      SourceStatus.failed => Icons.error_outline_rounded,
      SourceStatus.unknown => Icons.help_outline_rounded,
    };
  }

  /// 状态配色：[color] 文字/图标，[background] 胶囊底色。
  static ({Color color, Color background}) statusColors(
    BuildContext context,
    Source source,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (source.status) {
      SourceStatus.completed => (
        color: scheme.primary,
        background: scheme.primaryContainer.withValues(alpha: 0.55),
      ),
      SourceStatus.failed => (
        color: scheme.error,
        background: scheme.errorContainer.withValues(alpha: 0.6),
      ),
      _ => (
        color: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHighest,
      ),
    };
  }

  /// 元信息行：`3 个洞见 · 已向量化 · 更新于 3 小时前`。
  static String metaLine(Source source) {
    final parts = <String>[
      if (source.insightsCount > 0)
        '${source.insightsCount} ${SourcesStrings.insightsCount}',
      if (source.embedded) SourcesStrings.embedded,
      if (source.topics.isNotEmpty) source.topics.take(3).join(' · '),
    ];
    return parts.join(' · ');
  }
}

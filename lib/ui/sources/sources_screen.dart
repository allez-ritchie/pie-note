import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/layout.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'add_source_dialog.dart';
import 'source_detail_sheet.dart';
import 'source_meta.dart';
import 'sources_strings.dart';

/// 来源列表页：管理一个笔记本（或全部）的链接 / 文件 / 文本来源。
///
/// - [notebookId] 为 `null` 表示「全部来源」；
/// - 作为工作区标签页嵌入时 [embedded] 为 true：不自己 push 页面，
///   详情用 bottom sheet，添加用对话框；
/// - 列表里存在处理中的来源时每 3 秒刷新一次，直到后端处理完成。
class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({
    super.key,
    this.notebookId,
    required this.title,
    this.embedded = true,
  });

  final String? notebookId;
  final String title;
  final bool embedded;

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  final TextEditingController _filterController = TextEditingController();
  String _filter = '';
  Timer? _pollTimer;

  /// 有处理中的来源时才轮询。
  static const Duration _pollInterval = Duration(seconds: 3);

  @override
  void dispose() {
    _pollTimer?.cancel();
    _filterController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _invalidate() {
    ref.invalidate(sourcesProvider(widget.notebookId));
    ref.invalidate(notebooksProvider);
  }

  // ---------------------------------------------------------------------------
  // 轮询
  // ---------------------------------------------------------------------------

  /// 列表数据变化后同步轮询定时器：有处理中的来源就开，没有就停。
  void _syncPolling(List<Source> sources) {
    final hasProcessing = sources.any((source) => source.isProcessing);
    if (hasProcessing && _pollTimer == null) {
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        if (!mounted) return;
        ref.invalidate(sourcesProvider(widget.notebookId));
      });
    } else if (!hasProcessing && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // 动作
  // ---------------------------------------------------------------------------

  Future<void> _addSource() async {
    final outcome = await showAddSourceDialog(
      context,
      defaultNotebookId: widget.notebookId,
    );
    if (outcome == null || !mounted) return;
    if (outcome == AddSourceOutcome.submitted) {
      _invalidate();
      _showSnack(SourcesStrings.addBatchSummary);
    }
  }

  Future<void> _retry(Source source) async {
    final repository = ref.read(sourceRepositoryProvider);
    if (repository == null) return;
    try {
      await repository.retry(source.id);
      _invalidate();
      _showSnack(SourcesStrings.retriedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _delete(Source source) async {
    final confirmed = await showConfirmDialog(
      context,
      title: SourcesStrings.deleteTitle,
      message: SourcesStrings.deleteMessage(source.displayTitle),
      confirmLabel: SourcesStrings.delete,
      destructive: true,
    );
    if (!confirmed) return;
    final repository = ref.read(sourceRepositoryProvider);
    if (repository == null) return;
    try {
      await repository.deleteSource(source.id);
      _invalidate();
      _showSnack(SourcesStrings.deletedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _rename(Source source) async {
    final name = await showTextInputDialog(
      context,
      title: SourcesStrings.renameTitle,
      hintText: SourcesStrings.renameHint,
      initialValue: source.displayTitle,
    );
    if (name == null || name.trim().isEmpty || name == source.title) return;
    final repository = ref.read(sourceRepositoryProvider);
    if (repository == null) return;
    try {
      await repository.renameSource(source.id, name.trim());
      _invalidate();
      _showSnack(SourcesStrings.renamedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _openDetail(Source source) async {
    await showSourceDetailSheet(context, source: source);
    if (!mounted) return;
    // 详情里可能触发了重试 / 处理完成，回来刷新一次。
    _invalidate();
  }

  Future<void> _refresh() async {
    ref.invalidate(sourcesProvider(widget.notebookId));
    try {
      await ref.read(sourcesProvider(widget.notebookId).future);
    } catch (_) {
      // 错误由 AsyncValue 渲染，这里只负责结束下拉动画。
    }
  }

  List<Source> _visible(List<Source> sources) {
    final keyword = _filter.trim().toLowerCase();
    if (keyword.isEmpty) return sources;
    return sources
        .where(
          (source) =>
              source.title.toLowerCase().contains(keyword) ||
              (source.fullText ?? '').toLowerCase().contains(keyword),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider(widget.notebookId));
    // 数据变化后同步轮询状态（只在 build 里读取，避免在 provider 构建期改状态）。
    final data = sourcesAsync.valueOrNull;
    if (data != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPolling(data);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.notebookId == null ? SourcesStrings.allSources : widget.title),
        actions: [
          IconButton(
            tooltip: SourcesStrings.add,
            onPressed: _addSource,
            icon: const Icon(Icons.add_link_rounded),
          ),
          IconButton(
            tooltip: S.refresh,
            onPressed: _invalidate,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      // 手机端不放右下角 FAB：会与底部悬浮胶囊工具栏重叠。
      floatingActionButton: Responsive.useSideNavigation(context)
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: _addSource,
              icon: const Icon(Icons.add_rounded),
              label: const Text(SourcesStrings.add),
            )
          : null,
      body: sourcesAsync.when(
        loading: () => const AppLoadingView(message: S.loading),
        error: (error, _) => AppErrorView(
          title: SourcesStrings.loadErrorTitle,
          message: describeError(error),
          onRetry: _invalidate,
        ),
        data: (sources) {
          final visible = _visible(sources);
          final content = Column(
            children: [
              if (sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: TextField(
                    controller: _filterController,
                    onChanged: (value) => setState(() => _filter = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: SourcesStrings.filterHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _filter.isEmpty
                          ? null
                          : IconButton(
                              tooltip: S.clear,
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filter = '');
                              },
                            ),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: _buildEmpty(sources.isEmpty),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          // 底部为手机端胶囊工具栏留出空间。
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final source = visible[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SourceTile(
                                key: ValueKey(source.id),
                                source: source,
                                onTap: () => _openDetail(source),
                                onRetry: () => _retry(source),
                                onDelete: () => _delete(source),
                                onRename: () => _rename(source),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
          return ContentFrame(maxWidth: 860, child: content);
        },
      ),
    );
  }

  Widget _buildEmpty(bool notebookEmpty) {
    if (!notebookEmpty) {
      return AppEmptyView(
        icon: Icons.search_off_rounded,
        title: SourcesStrings.filterEmptyTitle,
        message: SourcesStrings.filterEmptyMessage,
        actionLabel: S.clearFilter,
        onAction: () {
          _filterController.clear();
          setState(() => _filter = '');
        },
      );
    }
    return AppEmptyView(
      icon: Icons.travel_explore_rounded,
      title: widget.notebookId == null
          ? SourcesStrings.emptyAllTitle
          : SourcesStrings.emptyTitle,
      message: widget.notebookId == null
          ? SourcesStrings.emptyAllMessage
          : SourcesStrings.emptyMessage,
      actionLabel: widget.notebookId == null ? null : SourcesStrings.add,
      onAction: widget.notebookId == null ? null : _addSource,
    );
  }
}

/// 单条来源卡片。
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.source,
    required this.onTap,
    required this.onRetry,
    required this.onDelete,
    required this.onRename,
  });

  final Source source;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = SourceMeta.metaLine(source);
    final updated = source.updated ?? source.created;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  sourceKindIcon(source.kind),
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(source: source),
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (source.status == SourceStatus.failed &&
                        source.processingError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        SourcesStrings.processingFailed(source.processingError!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (updated != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${SourcesStrings.updatedAt} ${Formatters.relativeTime(updated)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: S.more,
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                    case 'retry':
                      onRetry();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drive_file_rename_outline_rounded),
                      title: Text(SourcesStrings.rename),
                    ),
                  ),
                  if (source.hasFailed || source.isProcessing)
                    const PopupMenuItem(
                      value: 'retry',
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.refresh_rounded),
                        title: Text(SourcesStrings.retry),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text(SourcesStrings.delete),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态胶囊：处理中显示小进度圈，失败显示错误图标。
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final colors = SourceMeta.statusColors(context, source);
    final icon = SourceMeta.statusIcon(source.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: colors.color,
              ),
            )
          else
            Icon(icon, size: 12, color: colors.color),
          const SizedBox(width: 4),
          Text(
            SourceMeta.statusLabel(source),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

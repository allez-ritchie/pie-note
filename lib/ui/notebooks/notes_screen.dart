import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/navigation.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'notes_strings.dart';

enum _NoteSort {
  updated,
  created,
  title,
}

/// 某个笔记本下的笔记列表；[notebookId] 为 null 表示全部笔记。
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, required this.title, this.notebookId});

  final String title;
  final String? notebookId;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final TextEditingController _filterController = TextEditingController();
  _NoteSort _sort = _NoteSort.updated;
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _invalidateLists() {
    ref.invalidate(notesProvider(widget.notebookId));
    ref.invalidate(allNotesProvider);
    ref.invalidate(notebooksProvider);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openNote(Note note) async {
    final changed = await AppNavigator.openEditor(context, noteId: note.id);
    if (changed == true) _invalidateLists();
  }

  Future<void> _createNote() async {
    final changed = await AppNavigator.openEditor(
      context,
      notebookId: widget.notebookId,
    );
    if (changed == true) _invalidateLists();
  }

  Future<void> _deleteNote(Note note) async {
    final confirmed = await showConfirmDialog(
      context,
      title: NotesStrings.deleteTitle,
      message: NotesStrings.deleteMessage(note.displayTitle),
      confirmLabel: NotesStrings.delete,
      destructive: true,
    );
    if (!confirmed) return;
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.deleteNote(note.id);
      _invalidateLists();
      _showSnack(NotesStrings.deletedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  List<Note> _visibleNotes(List<Note> notes) {
    final keyword = _filter.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? notes
        : notes
            .where((note) =>
                note.displayTitle.toLowerCase().contains(keyword) ||
                note.content.toLowerCase().contains(keyword))
            .toList();
    final sorted = List<Note>.of(filtered);
    int compareDate(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (_sort) {
      case _NoteSort.updated:
        sorted.sort((a, b) => compareDate(a.updated, b.updated));
      case _NoteSort.created:
        sorted.sort((a, b) => compareDate(a.created, b.created));
      case _NoteSort.title:
        sorted.sort((a, b) =>
            a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
    }
    return sorted;
  }

  /// 构造「笔记 id → 正文」索引，用于列表摘要。
  ///
  /// 后端 `GET /api/notes?notebook_id=...` 为了性能**不返回 content**
  /// （见 AGENTS.md 第 2.3 节），而 `GET /api/notes`（不带过滤）会返回正文。
  /// 因此这里复用 [allNotesProvider] 的结果补齐摘要；拿不到时降级为不显示摘要。
  Map<String, String> _contentIndex(List<Note> notes) {
    final needsContent = notes.any((note) => note.content.isEmpty);
    if (!needsContent) return const {};
    final allNotes = ref.watch(allNotesProvider).valueOrNull;
    if (allNotes == null) return const {};
    return {
      for (final note in allNotes)
        if (note.content.isNotEmpty) note.id: note.content,
    };
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider(widget.notebookId));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<_NoteSort>(
            tooltip: NotesStrings.sortTooltip,
            onSelected: (value) => setState(() => _sort = value),
            initialValue: _sort,
            icon: const Icon(Icons.sort_rounded),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _NoteSort.updated,
                child: Text(NotesStrings.sortUpdated),
              ),
              PopupMenuItem(
                value: _NoteSort.created,
                child: Text(NotesStrings.sortCreated),
              ),
              PopupMenuItem(
                value: _NoteSort.title,
                child: Text(NotesStrings.sortTitle),
              ),
            ],
          ),
          IconButton(
            tooltip: S.refresh,
            onPressed: () => ref.invalidate(notesProvider(widget.notebookId)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNote,
        icon: const Icon(Icons.edit_rounded),
        label: const Text(NotesStrings.create),
      ),
      body: notesAsync.when(
        loading: () => const AppLoadingView(message: S.loading),
        error: (error, _) => AppErrorView(
          title: NotesStrings.loadErrorTitle,
          message: describeError(error),
          onRetry: () => ref.invalidate(notesProvider(widget.notebookId)),
        ),
        data: (notes) {
          final visible = _visibleNotes(notes);
          final contentIndex = _contentIndex(notes);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _filterController,
                  onChanged: (value) => setState(() => _filter = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: NotesStrings.filterHint,
                    prefixIcon: const Icon(Icons.filter_list_rounded, size: 20),
                    suffixIcon: _filter.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空',
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
                  onRefresh: () async {
                    ref.invalidate(notesProvider(widget.notebookId));
                    try {
                      await ref.read(notesProvider(widget.notebookId).future);
                    } catch (_) {
                      // 错误由 AsyncValue 渲染。
                    }
                  },
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: _buildEmpty(notes.isEmpty),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final note = visible[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _NoteTile(
                                key: ValueKey(note.id),
                                note: note,
                                contentOverride: contentIndex[note.id],
                                onTap: () => _openNote(note),
                                onDelete: () => _deleteNote(note),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmpty(bool notebookEmpty) {
    if (!notebookEmpty) {
      return AppEmptyView(
        icon: Icons.search_off_rounded,
        title: NotesStrings.filterEmptyTitle,
        message: NotesStrings.filterEmptyMessage,
        actionLabel: '清空筛选',
        onAction: () {
          _filterController.clear();
          setState(() => _filter = '');
        },
      );
    }
    return AppEmptyView(
      icon: Icons.description_outlined,
      title: widget.notebookId == null
          ? NotesStrings.emptyAllTitle
          : NotesStrings.emptyTitle,
      message: widget.notebookId == null
          ? NotesStrings.emptyAllMessage
          : NotesStrings.emptyMessage,
      actionLabel: NotesStrings.create,
      onAction: _createNote,
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    super.key,
    required this.note,
    required this.onTap,
    required this.onDelete,
    this.contentOverride,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 列表接口未返回正文时，用内容索引里的正文生成摘要。
  final String? contentOverride;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final override = contentOverride;
    final snippet = (override == null || override.isEmpty)
        ? note.snippet()
        : Note.snippetOf(override);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            note.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (note.isAi) ...[
                          const SizedBox(width: 6),
                          _AiBadge(),
                        ],
                      ],
                    ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      '${NotesStrings.updatedAt} ${Formatters.relativeTime(note.updated)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (_) => onDelete(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text(NotesStrings.delete),
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

class _AiBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        NotesStrings.aiBadge,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

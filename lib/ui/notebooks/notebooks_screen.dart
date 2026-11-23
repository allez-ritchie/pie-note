import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/formatters.dart';
import '../common/layout.dart';
import '../common/navigation.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import 'notebooks_strings.dart';
import 'notes_screen.dart';

/// 笔记本列表（一级页面）。
///
/// 宽屏（手机横屏 / 平板 / 桌面窗口）下自动变为「左笔记本、右笔记」双栏：
/// 选中笔记本后右侧直接展示笔记列表，不再用二级页面跳转。
class NotebooksScreen extends ConsumerStatefulWidget {
  const NotebooksScreen({super.key});

  @override
  ConsumerState<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends ConsumerState<NotebooksScreen> {
  bool _showArchived = false;

  /// 双栏布局下右侧选中的笔记本；`null` 表示「全部笔记」。
  String? _selectedNotebookId;
  String _selectedTitle = NotebooksStrings.allNotes;

  void _selectNotebook(String? id, String title) {
    if (id == _selectedNotebookId) return;
    setState(() {
      _selectedNotebookId = id;
      _selectedTitle = title;
    });
  }

  /// 选中的笔记本被删除或列表刷新后不存在时，回退到「全部笔记」。
  void _syncSelection(List<Notebook> notebooks) {
    final selected = _selectedNotebookId;
    if (selected == null) return;
    if (notebooks.any((notebook) => notebook.id == selected)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedNotebookId != selected) return;
      setState(() {
        _selectedNotebookId = null;
        _selectedTitle = NotebooksStrings.allNotes;
      });
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(notebooksProvider);
    try {
      await ref.read(notebooksProvider.future);
    } catch (_) {
      // 错误由 AsyncValue 渲染，这里只负责结束下拉动画。
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createNotebook() async {
    final name = await showTextInputDialog(
      context,
      title: NotebooksStrings.createDialogTitle,
      hintText: NotebooksStrings.createDialogHint,
    );
    if (name == null || name.isEmpty) return;
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.createNotebook(name: name);
      ref.invalidate(notebooksProvider);
      _showSnack(NotebooksStrings.createdToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _renameNotebook(Notebook notebook) async {
    final name = await showTextInputDialog(
      context,
      title: NotebooksStrings.renameDialogTitle,
      initialValue: notebook.name,
      hintText: NotebooksStrings.renameDialogHint,
    );
    if (name == null || name == notebook.name) return;
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.updateNotebook(notebook.id, name: name);
      ref.invalidate(notebooksProvider);
      _showSnack(NotebooksStrings.updatedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _toggleArchive(Notebook notebook) async {
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.updateNotebook(notebook.id, archived: !notebook.archived);
      ref.invalidate(notebooksProvider);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _deleteNotebook(Notebook notebook) async {
    final confirmed = await showConfirmDialog(
      context,
      title: NotebooksStrings.deleteTitle,
      message: NotebooksStrings.deleteMessage(notebook.name),
      confirmLabel: NotebooksStrings.delete,
      destructive: true,
    );
    if (!confirmed) return;
    final repository = ref.read(repositoryProvider);
    if (repository == null) return;
    try {
      await repository.deleteNotebook(notebook.id);
      ref.invalidate(notebooksProvider);
      ref.invalidate(allNotesProvider);
      if (_selectedNotebookId == notebook.id) {
        setState(() => _selectedNotebookId = null);
      }
      _showSnack(NotebooksStrings.deletedToast);
    } catch (error) {
      _showSnack(describeError(error));
    }
  }

  Future<void> _openNotebook(Notebook notebook) async {
    if (Responsive.useTwoPane(context)) {
      _selectNotebook(notebook.id, notebook.name);
      return;
    }
    await AppNavigator.openNotes(
      context,
      title: notebook.name,
      notebookId: notebook.id,
    );
    // 笔记增删后笔记本的 note_count / updated 会变化。
    ref.invalidate(notebooksProvider);
  }

  @override
  Widget build(BuildContext context) {
    final notebooksAsync = ref.watch(notebooksProvider);
    final twoPane = Responsive.useTwoPane(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(NotebooksStrings.title),
        actions: [
          IconButton(
            tooltip: S.refresh,
            onPressed: () => ref.invalidate(notebooksProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<bool>(
            tooltip: '更多',
            onSelected: (value) => setState(() => _showArchived = value),
            itemBuilder: (context) => [
              CheckedPopupMenuItem<bool>(
                value: true,
                checked: _showArchived,
                child: const Text(NotebooksStrings.showArchived),
              ),
            ],
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      // 双栏时「新建笔记本」按钮放进左栏，避免盖住右侧笔记列表自己的按钮。
      floatingActionButton: twoPane
          ? null
          : FloatingActionButton.extended(
              onPressed: _createNotebook,
              icon: const Icon(Icons.create_new_folder_rounded),
              label: const Text(NotebooksStrings.create),
            ),
      body: notebooksAsync.when(
        loading: () => const AppLoadingView(message: S.loading),
        error: (error, _) => AppErrorView(
          title: NotebooksStrings.loadErrorTitle,
          message: describeError(error),
          onRetry: () => ref.invalidate(notebooksProvider),
        ),
        data: (notebooks) {
          _syncSelection(notebooks);
          final active = notebooks.where((n) => !n.archived).toList(growable: false);
          final archived = notebooks.where((n) => n.archived).toList(growable: false);
          final totalNotes =
              notebooks.fold<int>(0, (sum, notebook) => sum + notebook.noteCount);
          final list = RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _AllNotesCard(
                  totalNotes: totalNotes,
                  selected: twoPane && _selectedNotebookId == null,
                  onSelect: () {
                    if (twoPane) {
                      _selectNotebook(null, NotebooksStrings.allNotes);
                    } else {
                      AppNavigator.openNotes(
                        context,
                        title: NotebooksStrings.allNotes,
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: NotebooksStrings.title,
                  trailing: NotebooksStrings.notebookCount(active.length),
                ),
                const SizedBox(height: 8),
                if (active.isEmpty)
                  _EmptyNotebooks(onCreate: _createNotebook)
                else
                  ...active.map(
                    (notebook) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NotebookTile(
                        notebook: notebook,
                        selected: _selectedNotebookId == notebook.id,
                        onTap: () => _openNotebook(notebook),
                        onRename: () => _renameNotebook(notebook),
                        onToggleArchive: () => _toggleArchive(notebook),
                        onDelete: () => _deleteNotebook(notebook),
                      ),
                    ),
                  ),
                if (_showArchived && archived.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionHeader(
                    title: NotebooksStrings.showArchived,
                    trailing: NotebooksStrings.notebookCount(archived.length),
                  ),
                  const SizedBox(height: 8),
                  ...archived.map(
                    (notebook) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NotebookTile(
                        notebook: notebook,
                        selected: _selectedNotebookId == notebook.id,
                        onTap: () => _openNotebook(notebook),
                        onRename: () => _renameNotebook(notebook),
                        onToggleArchive: () => _toggleArchive(notebook),
                        onDelete: () => _deleteNotebook(notebook),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
          // 单栏时（手机竖屏 / 横屏）也收敛内容宽度，横屏下不会把卡片拉得过宽。
          if (!twoPane) return ContentFrame(maxWidth: 780, child: list);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                // 左栏随窗口弹性变化：窄窗口 320、宽窗口最多 420。
                width: (MediaQuery.sizeOf(context).width * 0.32)
                    .clamp(320.0, 420.0),
                child: Stack(
                  children: [
                    Positioned.fill(child: list),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.extended(
                        heroTag: null,
                        onPressed: _createNotebook,
                        icon: const Icon(Icons.create_new_folder_rounded),
                        label: const Text(NotebooksStrings.create),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: NotesScreen(
                  // 切换笔记本时重建，避免沿用上一条笔记的滚动位置与筛选词。
                  key: ValueKey<String?>(_selectedNotebookId),
                  title: _selectedTitle,
                  notebookId: _selectedNotebookId,
                  padded: true,
                  showBackButton: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AllNotesCard extends StatelessWidget {
  const _AllNotesCard({
    required this.totalNotes,
    required this.selected,
    required this.onSelect,
  });

  final int totalNotes;

  /// 双栏布局下是否正在展示「全部笔记」。
  final bool selected;

  /// 点击行为：双栏切右侧内容，单栏推入笔记列表页。
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        onTap: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.library_books_rounded, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NotebooksStrings.allNotes,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      NotebooksStrings.allNotesSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$totalNotes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    S.noteUnit,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

class _NotebookTile extends StatelessWidget {
  const _NotebookTile({
    required this.notebook,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final Notebook notebook;

  /// 双栏布局下是否是右侧正在展示的笔记本。
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updated = notebook.updated;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: selected ? 1.6 : 1,
        ),
      ),
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.28) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: notebook.archived
                      ? scheme.surfaceContainerHighest
                      : scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  notebook.archived ? Icons.archive_rounded : Icons.folder_rounded,
                  color: notebook.archived
                      ? scheme.onSurfaceVariant
                      : scheme.onSecondaryContainer,
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
                            notebook.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (notebook.archived) ...[
                          const SizedBox(width: 6),
                          _Badge(text: NotebooksStrings.archivedBadge),
                        ],
                      ],
                    ),
                    if (notebook.hasDescription) ...[
                      const SizedBox(height: 2),
                      Text(
                        notebook.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          NotebooksStrings.noteCount(notebook.noteCount),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (updated != null) ...[
                          Text(
                            '  ·  ${Formatters.relativeTime(updated)}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                    case 'archive':
                      onToggleArchive();
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
                      title: Text(NotebooksStrings.editName),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        notebook.archived
                            ? Icons.unarchive_rounded
                            : Icons.archive_outlined,
                      ),
                      title: Text(
                        notebook.archived
                            ? NotebooksStrings.unarchive
                            : NotebooksStrings.archive,
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text(NotebooksStrings.delete),
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

class _EmptyNotebooks extends StatelessWidget {
  const _EmptyNotebooks({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: AppEmptyView(
        icon: Icons.folder_open_rounded,
        title: NotebooksStrings.emptyTitle,
        message: NotebooksStrings.emptyMessage,
        actionLabel: NotebooksStrings.create,
        onAction: onCreate,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            ),
      ),
    );
  }
}
